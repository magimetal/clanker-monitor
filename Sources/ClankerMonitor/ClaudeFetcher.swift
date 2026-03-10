import Foundation
import Security

func fetchClaude() async -> ProviderResult {
    let credentials: ClaudeCredentials
    do {
        credentials = try loadClaudeCredentials()
    } catch {
        return ProviderResult(errorMessage: "Claude: credentials not found. Run 'claude login'.", updatedAt: Date())
    }

    do {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            return ProviderResult(errorMessage: "Claude: bad URL", updatedAt: Date())
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return ProviderResult(errorMessage: "Claude: invalid response", updatedAt: Date())
        }

        if http.statusCode == 401 {
            return ProviderResult(errorMessage: "Claude token expired. Run 'claude login'.", updatedAt: Date())
        }

        guard (200...299).contains(http.statusCode) else {
            return ProviderResult(errorMessage: "Claude: HTTP \(http.statusCode)", updatedAt: Date())
        }

        let usage = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        let window = usage.fiveHour ?? usage.sevenDay
        guard let window else {
            return ProviderResult(errorMessage: "Claude: missing usage window", updatedAt: Date())
        }

        let utilizationRaw = window.utilization ?? 0
        // Runtime-safe handling: if utilization is 0...1 treat it as fraction; otherwise treat as percent.
        // This keeps compatibility with either API representation without requiring a token probe at build time.
        let usedPercent = utilizationRaw <= 1.0 ? utilizationRaw * 100 : utilizationRaw

        return ProviderResult(
            usedPercent: max(0, min(100, usedPercent)),
            resetDescription: makeClaudeResetLabel(window.resetsAt),
            planLabel: mapClaudePlan(rateLimitTier: credentials.rateLimitTier, subscriptionType: credentials.subscriptionType),
            errorMessage: nil,
            updatedAt: Date())
    } catch {
        return ProviderResult(errorMessage: "Claude: \(error.localizedDescription)", updatedAt: Date())
    }
}

private struct ClaudeCredentials {
    let accessToken: String
    let rateLimitTier: String?
    let subscriptionType: String?
}

private func loadClaudeCredentials() throws -> ClaudeCredentials {
    if let keychainData = try loadClaudeCredentialDataFromKeychain(),
       let credentials = parseClaudeCredentials(from: keychainData)
    {
        return credentials
    }

    let path = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/.credentials.json")
    let data = try Data(contentsOf: path)
    if let credentials = parseClaudeCredentials(from: data) {
        return credentials
    }

    throw URLError(.userAuthenticationRequired)
}

private func parseClaudeCredentials(from data: Data) -> ClaudeCredentials? {

    if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
        if let oauth = root["claudeAiOauth"] as? [String: Any],
           let accessToken = oauth["accessToken"] as? String,
           !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return ClaudeCredentials(
                accessToken: accessToken,
                rateLimitTier: oauth["rateLimitTier"] as? String,
                subscriptionType: oauth["subscriptionType"] as? String)
        }

        if let accessToken = root["access_token"] as? String,
           !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return ClaudeCredentials(accessToken: accessToken, rateLimitTier: nil, subscriptionType: nil)
        }
    }

    return nil
}

private func loadClaudeCredentialDataFromKeychain() throws -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecSuccess {
        return result as? Data
    }

    if status == errSecItemNotFound {
        return nil
    }

    throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
}

private struct ClaudeUsageResponse: Decodable {
    let fiveHour: ClaudeUsageWindow?
    let sevenDay: ClaudeUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeUsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private func mapClaudePlan(rateLimitTier: String?, subscriptionType: String?) -> String {
    switch subscriptionType?.lowercased() {
    case "max": return "Claude Max"
    case "pro": return "Claude Pro"
    case "free": return "Claude Free"
    default: break
    }

    switch rateLimitTier?.lowercased() {
    case "max": return "Claude Max"
    case "pro": return "Claude Pro"
    default: return "Claude"
    }
}

private func makeClaudeResetLabel(_ isoDate: String?) -> String? {
    guard let isoDate else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let parsed = iso.date(from: isoDate) ?? {
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: isoDate)
    }()
    guard let parsed else { return nil }
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mma"
    formatter.amSymbol = "am"
    formatter.pmSymbol = "pm"
    return "resets at \(formatter.string(from: parsed).lowercased())"
}
