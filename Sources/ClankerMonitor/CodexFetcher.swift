import Foundation

func fetchCodex() async -> ProviderResult {
    let credentials: CodexCredentials
    do {
        credentials = try loadCodexCredentials()
    } catch {
        return ProviderResult(
            errorMessage: "auth.json not found or invalid. Run 'codex' to log in.",
            updatedAt: Date())
    }

    do {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return ProviderResult(errorMessage: "Codex: bad URL", updatedAt: Date())
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("ClankerMonitor", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = credentials.accountID, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return ProviderResult(errorMessage: "Codex: invalid response", updatedAt: Date())
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            return ProviderResult(
                errorMessage: "Codex token expired. Run 'codex' to re-authenticate.",
                updatedAt: Date())
        }

        guard (200...299).contains(http.statusCode) else {
            return ProviderResult(errorMessage: "Codex: HTTP \(http.statusCode)", updatedAt: Date())
        }

        let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        guard let window = decoded.rateLimit?.primaryWindow ?? decoded.rateLimit?.secondaryWindow else {
            return ProviderResult(errorMessage: "Codex: usage window missing", updatedAt: Date())
        }

        return ProviderResult(
            usedPercent: Double(window.usedPercent),
            resetDescription: "resets at \(formatResetTime(unixSeconds: window.resetAt))",
            planLabel: decoded.planType,
            errorMessage: nil,
            updatedAt: Date())
    } catch {
        return ProviderResult(
            errorMessage: "Codex: \(error.localizedDescription)",
            updatedAt: Date())
    }
}

private struct CodexCredentials {
    let token: String
    let accountID: String?
}

private func loadCodexCredentials() throws -> CodexCredentials {
    let path = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")
    let data = try Data(contentsOf: path)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw URLError(.cannotParseResponse)
    }

    if let apiKey = root["OPENAI_API_KEY"] as? String,
       !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
        return CodexCredentials(token: apiKey, accountID: nil)
    }

    guard let tokens = root["tokens"] as? [String: Any],
          let accessToken = tokens["access_token"] as? String,
          !accessToken.isEmpty
    else {
        throw URLError(.userAuthenticationRequired)
    }

    return CodexCredentials(token: accessToken, accountID: tokens["account_id"] as? String)
}

private struct CodexUsageResponse: Decodable {
    let planType: String?
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }

    struct RateLimit: Decodable {
        let primaryWindow: WindowSnapshot?
        let secondaryWindow: WindowSnapshot?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct WindowSnapshot: Decodable {
        let usedPercent: Int
        let resetAt: Int

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
        }
    }
}

private func formatResetTime(unixSeconds: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mma"
    formatter.amSymbol = "am"
    formatter.pmSymbol = "pm"
    return formatter.string(from: date).lowercased()
}
