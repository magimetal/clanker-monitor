import Foundation

func fetchCopilot(token: String) async -> ProviderResult {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ProviderResult(errorMessage: "Copilot: No token. Add your GitHub PAT in Settings.", updatedAt: Date())
    }

    do {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else {
            return ProviderResult(errorMessage: "Copilot: bad URL", updatedAt: Date())
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("token \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return ProviderResult(errorMessage: "Copilot: invalid response", updatedAt: Date())
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            return ProviderResult(errorMessage: "Copilot token invalid or expired.", updatedAt: Date())
        }

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Int($0) }
                .map { " Retry in \(formatDuration(seconds: $0))." } ?? ""
            return ProviderResult(
                errorMessage: "Copilot rate-limited.\(retryAfter)",
                updatedAt: Date())
        }

        guard (200...299).contains(http.statusCode) else {
            return ProviderResult(errorMessage: "Copilot: HTTP \(http.statusCode)", updatedAt: Date())
        }

        let usage = try JSONDecoder().decode(CopilotUserResponse.self, from: data)

        let premium = usage.quotaSnapshots.premiumInteractions
        let chat = usage.quotaSnapshots.chat

        let planLabel = "Copilot \(usage.copilotPlan.capitalized)"

        let resetDescription = makeCopilotResetDescription(usage.quotaResetDateUtc)

        if let premium, !premium.unlimited {
            let usedPercent = computeCopilotUsedPercent(premium)
            let usedCount = computeCopilotUsedCount(premium)

            let weeklyUsedPercent = computeCopilotWeeklyPace(
                used: usedCount,
                entitlement: premium.entitlement,
                resetDate: usage.quotaResetDateUtc)

            let weeklyDescription: String? = weeklyUsedPercent.map { pace in
                let paceLabel = pace >= 100 ? "over budget" : pace >= 90 ? "near limit" : "on pace"
                return "weekly pace: \(paceLabel)"
            }

            let overageNote: String? = premium.overageCount > 0
                ? "\(formatCopilotCount(premium.overageCount)) overage"
                : nil

            return ProviderResult(
                usedPercent: usedPercent,
                resetDescription: makeCopilotUsageDescription(snapshot: premium, resetDescription: resetDescription, overageNote: overageNote),
                weeklyUsedPercent: weeklyUsedPercent,
                weeklyResetDescription: weeklyDescription,
                planLabel: planLabel,
                errorMessage: nil,
                updatedAt: Date())
        }

        if let chat, chat.unlimited {
            return ProviderResult(
                usedPercent: 0,
                resetDescription: nil,
                weeklyUsedPercent: nil,
                weeklyResetDescription: nil,
                planLabel: "\(planLabel) (Unlimited)",
                errorMessage: nil,
                updatedAt: Date())
        }

        if let chat {
            let usedPercent = computeCopilotUsedPercent(chat)
            return ProviderResult(
                usedPercent: usedPercent,
                resetDescription: makeCopilotUsageDescription(snapshot: chat, resetDescription: resetDescription, overageNote: nil),
                weeklyUsedPercent: nil,
                weeklyResetDescription: nil,
                planLabel: planLabel,
                errorMessage: nil,
                updatedAt: Date())
        }

        return ProviderResult(errorMessage: "Copilot: missing quota data", updatedAt: Date())
    } catch {
        return ProviderResult(errorMessage: "Copilot: \(error.localizedDescription)", updatedAt: Date())
    }
}

private func computeCopilotWeeklyPace(used: Int, entitlement: Int, resetDate: String?) -> Double? {
    guard entitlement > 0, used >= 0, let reset = parseCopilotResetDate(resetDate) else { return nil }

    let now = Date()
    let daysRemaining = Calendar.current.dateComponents([.day], from: now, to: reset).day ?? 0
    guard daysRemaining > 0 else { return nil }

    let daysInPeriod = max(1, Calendar.current.dateComponents([.day], from: beginningOfMonth(for: now), to: reset).day ?? 30)
    let daysElapsed = daysInPeriod - daysRemaining
    guard daysElapsed > 0 else { return nil }

    let weeklyBurnRate = Double(used) / Double(daysElapsed) * 7.0
    let weeklyAllowance = Double(entitlement) / Double(daysInPeriod) * 7.0
    guard weeklyAllowance > 0 else { return nil }

    return (weeklyBurnRate / weeklyAllowance) * 100.0
}

private func computeCopilotUsedCount(_ snapshot: CopilotUserResponse.QuotaSnapshot) -> Int {
    max(0, snapshot.entitlement - max(0, snapshot.remaining)) + max(0, snapshot.overageCount)
}

private func computeCopilotUsedPercent(_ snapshot: CopilotUserResponse.QuotaSnapshot) -> Double {
    guard snapshot.entitlement > 0 else {
        return max(0, 100 - snapshot.percentRemaining)
    }

    return max(0, Double(computeCopilotUsedCount(snapshot)) / Double(snapshot.entitlement) * 100.0)
}

private func makeCopilotUsageDescription(
    snapshot: CopilotUserResponse.QuotaSnapshot,
    resetDescription: String?,
    overageNote: String?
) -> String? {
    var parts: [String] = []

    if snapshot.entitlement > 0 {
        parts.append("\(formatCopilotCount(computeCopilotUsedCount(snapshot)))/\(formatCopilotCount(snapshot.entitlement)) used")
    }

    if let resetDescription {
        parts.append(resetDescription)
    }

    if let overageNote {
        parts.append(overageNote)
    }

    return parts.isEmpty ? nil : parts.joined(separator: " • ")
}

private func beginningOfMonth(for date: Date) -> Date {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: components) ?? date
}

private func parseCopilotResetDate(_ isoString: String?) -> Date? {
    guard let isoString, !isoString.isEmpty else { return nil }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: isoString) { return date }

    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: isoString) { return date }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    if let date = formatter.date(from: isoString) { return date }

    return nil
}

private func makeCopilotResetDescription(_ isoString: String?) -> String? {
    guard let date = parseCopilotResetDate(isoString) else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return "resets \(formatter.string(from: date))"
}

private func formatDuration(seconds: Int) -> String {
    let safe = max(0, seconds)
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

private func formatCopilotCount(_ value: Int) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
}

private struct CopilotUserResponse: Decodable {
    let quotaSnapshots: QuotaSnapshots
    let copilotPlan: String
    let quotaResetDateUtc: String?

    enum CodingKeys: String, CodingKey {
        case quotaSnapshots = "quota_snapshots"
        case copilotPlan = "copilot_plan"
        case quotaResetDateUtc = "quota_reset_date_utc"
    }

    struct QuotaSnapshots: Decodable {
        let premiumInteractions: QuotaSnapshot?
        let chat: QuotaSnapshot?

        enum CodingKeys: String, CodingKey {
            case premiumInteractions = "premium_interactions"
            case chat
        }
    }

    struct QuotaSnapshot: Decodable {
        let percentRemaining: Double
        let remaining: Int
        let entitlement: Int
        let unlimited: Bool
        let overageCount: Int

        enum CodingKeys: String, CodingKey {
            case percentRemaining = "percent_remaining"
            case remaining
            case entitlement
            case unlimited
            case overageCount = "overage_count"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            percentRemaining = try container.decodeIfPresent(Double.self, forKey: .percentRemaining) ?? 0
            remaining = try container.decodeIfPresent(Int.self, forKey: .remaining) ?? 0
            entitlement = try container.decodeIfPresent(Int.self, forKey: .entitlement) ?? 0
            unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited) ?? false
            overageCount = try container.decodeIfPresent(Int.self, forKey: .overageCount) ?? 0
        }
    }
}
