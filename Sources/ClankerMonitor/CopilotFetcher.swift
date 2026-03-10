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
        request.setValue("token \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return ProviderResult(errorMessage: "Copilot: invalid response", updatedAt: Date())
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            return ProviderResult(errorMessage: "Copilot token invalid or expired.", updatedAt: Date())
        }

        guard (200...299).contains(http.statusCode) else {
            return ProviderResult(errorMessage: "Copilot: HTTP \(http.statusCode)", updatedAt: Date())
        }

        let usage = try JSONDecoder().decode(CopilotUserResponse.self, from: data)
        let remaining = usage.quotaSnapshots.premiumInteractions?.percentRemaining
            ?? usage.quotaSnapshots.chat?.percentRemaining

        guard let remaining else {
            return ProviderResult(errorMessage: "Copilot: missing quota data", updatedAt: Date())
        }

        return ProviderResult(
            usedPercent: max(0, 100 - remaining),
            resetDescription: nil,
            planLabel: "Copilot \(usage.copilotPlan.capitalized)",
            errorMessage: nil,
            updatedAt: Date())
    } catch {
        return ProviderResult(errorMessage: "Copilot: \(error.localizedDescription)", updatedAt: Date())
    }
}

private struct CopilotUserResponse: Decodable {
    let quotaSnapshots: QuotaSnapshots
    let copilotPlan: String

    enum CodingKeys: String, CodingKey {
        case quotaSnapshots = "quota_snapshots"
        case copilotPlan = "copilot_plan"
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

        enum CodingKeys: String, CodingKey {
            case percentRemaining = "percent_remaining"
        }
    }
}
