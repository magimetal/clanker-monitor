import Foundation
import Security

func fetchClaude() async -> ProviderResult {
    let credentials: ClaudeCredentials
    do {
        credentials = await refreshClaudeTokenIfNeeded(try loadClaudeCredentials())
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

private enum ClaudeCredentialSource: Equatable {
    case keychain
    case file(URL)
}

private struct ClaudeCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Int64?
    let scopes: [Any]?
    let rateLimitTier: String?
    let subscriptionType: String?
    let source: ClaudeCredentialSource
    let rawData: Data
}

private struct ClaudeAuthSnapshot: Equatable {
    let source: ClaudeCredentialSource
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Int64?
    let rawData: Data
}

private struct ClaudeRefreshResponse {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Int64?
}

private let claudeOAuthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
private let claudeOAuthPrimaryTokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
private let claudeOAuthFallbackTokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!

private func loadClaudeCredentials() throws -> ClaudeCredentials {
    if let keychainData = try loadClaudeCredentialDataFromKeychain(),
       let credentials = parseClaudeCredentials(from: keychainData, source: .keychain)
    {
        return credentials
    }

    let path = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/.credentials.json")
    let data = try Data(contentsOf: path)
    if let credentials = parseClaudeCredentials(from: data, source: .file(path)) {
        return credentials
    }

    throw URLError(.userAuthenticationRequired)
}

private func parseClaudeCredentials(from data: Data, source: ClaudeCredentialSource) -> ClaudeCredentials? {
    if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
        if let oauth = root["claudeAiOauth"] as? [String: Any],
           let accessToken = oauth["accessToken"] as? String,
           !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return ClaudeCredentials(
                accessToken: accessToken,
                refreshToken: oauth["refreshToken"] as? String,
                expiresAt: int64Value(oauth["expiresAt"]),
                scopes: oauth["scopes"] as? [Any],
                rateLimitTier: oauth["rateLimitTier"] as? String,
                subscriptionType: oauth["subscriptionType"] as? String,
                source: source,
                rawData: data)
        }

        if let accessToken = root["access_token"] as? String,
           !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return ClaudeCredentials(
                accessToken: accessToken,
                refreshToken: nil,
                expiresAt: nil,
                scopes: nil,
                rateLimitTier: nil,
                subscriptionType: nil,
                source: source,
                rawData: data)
        }
    }

    return nil
}

private func refreshClaudeTokenIfNeeded(_ credentials: ClaudeCredentials) async -> ClaudeCredentials {
    guard let refreshToken = credentials.refreshToken,
          !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          isClaudeTokenRefreshNeeded(expiresAt: credentials.expiresAt)
    else {
        return credentials
    }

    let originalSnapshot = makeClaudeAuthSnapshot(credentials)

    do {
        let refresh = try await postClaudeRefresh(refreshToken: refreshToken)
        guard let currentSnapshot = try reloadClaudeCredentialsSnapshot(from: credentials.source),
              currentSnapshot == originalSnapshot
        else {
            return (try? loadClaudeCredentials(from: credentials.source)) ?? credentials
        }

        switch credentials.source {
        case .keychain:
            return ClaudeCredentials(
                accessToken: refresh.accessToken,
                refreshToken: refresh.refreshToken ?? credentials.refreshToken,
                expiresAt: refresh.expiresAt ?? credentials.expiresAt,
                scopes: credentials.scopes,
                rateLimitTier: credentials.rateLimitTier,
                subscriptionType: credentials.subscriptionType,
                source: credentials.source,
                rawData: credentials.rawData)
        case let .file(path):
            guard let originalJSON = (try? JSONSerialization.jsonObject(with: credentials.rawData)) as? [String: Any] else {
                return credentials
            }
            return try writeClaudeCredentialsFile(credentials: credentials, refresh: refresh, originalJSON: originalJSON, path: path)
        }
    } catch {
        return credentials
    }
}

private func isClaudeTokenRefreshNeeded(expiresAt: Int64?, now: Date = Date()) -> Bool {
    guard let expiresAt else { return true }
    return expiresAt / 1000 <= Int64(now.timeIntervalSince1970) + 300
}

private func postClaudeRefresh(refreshToken: String) async throws -> ClaudeRefreshResponse {
    do {
        return try await postClaudeRefresh(to: claudeOAuthPrimaryTokenURL, refreshToken: refreshToken)
    } catch let error as ClaudeRefreshError {
        if shouldTryClaudeRefreshFallback(statusCode: error.statusCode, error: nil) {
            return try await postClaudeRefresh(to: claudeOAuthFallbackTokenURL, refreshToken: refreshToken)
        }
        throw error
    } catch {
        if shouldTryClaudeRefreshFallback(statusCode: nil, error: error) {
            return try await postClaudeRefresh(to: claudeOAuthFallbackTokenURL, refreshToken: refreshToken)
        }
        throw error
    }
}

private func postClaudeRefresh(to url: URL, refreshToken: String) async throws -> ClaudeRefreshResponse {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = claudeFormURLEncodedBody([
        URLQueryItem(name: "grant_type", value: "refresh_token"),
        URLQueryItem(name: "refresh_token", value: refreshToken),
        URLQueryItem(name: "client_id", value: claudeOAuthClientID),
    ])

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw ClaudeRefreshError.invalidResponse
    }

    guard (200...299).contains(http.statusCode) else {
        throw ClaudeRefreshError.httpStatus(http.statusCode)
    }

    guard let parsed = parseClaudeRefreshResponse(from: data) else {
        throw ClaudeRefreshError.invalidResponse
    }
    return parsed
}

private func shouldTryClaudeRefreshFallback(statusCode: Int?, error: Error?) -> Bool {
    if error is URLError { return true }
    guard let statusCode else { return false }
    return statusCode == 404 || statusCode == 405 || (500...599).contains(statusCode)
}

private func makeClaudeAuthSnapshot(_ credentials: ClaudeCredentials) -> ClaudeAuthSnapshot {
    ClaudeAuthSnapshot(
        source: credentials.source,
        accessToken: credentials.accessToken,
        refreshToken: credentials.refreshToken,
        expiresAt: credentials.expiresAt,
        rawData: credentials.rawData)
}

private func reloadClaudeCredentialsSnapshot(from source: ClaudeCredentialSource) throws -> ClaudeAuthSnapshot? {
    try loadClaudeCredentials(from: source).map(makeClaudeAuthSnapshot)
}

private func loadClaudeCredentials(from source: ClaudeCredentialSource) throws -> ClaudeCredentials? {
    switch source {
    case .keychain:
        guard let data = try loadClaudeCredentialDataFromKeychain() else { return nil }
        return parseClaudeCredentials(from: data, source: source)
    case let .file(path):
        let data = try Data(contentsOf: path)
        return parseClaudeCredentials(from: data, source: source)
    }
}

private func writeClaudeCredentialsFile(
    credentials: ClaudeCredentials,
    refresh: ClaudeRefreshResponse,
    originalJSON: [String: Any],
    path: URL
) throws -> ClaudeCredentials {
    var root = originalJSON
    var oauth = (root["claudeAiOauth"] as? [String: Any]) ?? [:]
    let refreshedToken = refresh.refreshToken ?? credentials.refreshToken
    let refreshedExpiresAt = refresh.expiresAt ?? credentials.expiresAt

    oauth["accessToken"] = refresh.accessToken
    oauth["refreshToken"] = refreshedToken
    oauth["expiresAt"] = refreshedExpiresAt
    oauth["scopes"] = credentials.scopes ?? []

    if let rateLimitTier = credentials.rateLimitTier {
        oauth["rateLimitTier"] = rateLimitTier
    }
    if let subscriptionType = credentials.subscriptionType {
        oauth["subscriptionType"] = subscriptionType
    }

    root["claudeAiOauth"] = oauth
    let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    try atomicWriteWithPermissions(data: data, to: path)

    return ClaudeCredentials(
        accessToken: refresh.accessToken,
        refreshToken: refreshedToken,
        expiresAt: refreshedExpiresAt,
        scopes: credentials.scopes,
        rateLimitTier: credentials.rateLimitTier,
        subscriptionType: credentials.subscriptionType,
        source: credentials.source,
        rawData: data)
}

private func atomicWriteWithPermissions(data: Data, to path: URL) throws {
    let directory = path.deletingLastPathComponent()
    let temporaryURL = directory.appendingPathComponent(".\(path.lastPathComponent).\(UUID().uuidString).tmp")
    let fileManager = FileManager.default

    do {
        try data.write(to: temporaryURL, options: .withoutOverwriting)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)

        if fileManager.fileExists(atPath: path.path) {
            _ = try fileManager.replaceItemAt(path, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: path)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    } catch {
        try? fileManager.removeItem(at: temporaryURL)
        throw error
    }
}

private func parseClaudeRefreshResponse(from data: Data) -> ClaudeRefreshResponse? {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    guard let accessToken = (root["access_token"] as? String) ?? (root["accessToken"] as? String),
          !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return nil
    }

    let refreshToken = (root["refresh_token"] as? String) ?? (root["refreshToken"] as? String)
    let expiresAt = int64Value(root["expires_at"])
        ?? int64Value(root["expiresAt"])
        ?? int64Value(root["expires_in"]).map { Int64(Date().timeIntervalSince1970 * 1000) + ($0 * 1000) }

    return ClaudeRefreshResponse(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
}

private func claudeFormURLEncodedBody(_ queryItems: [URLQueryItem]) -> Data? {
    var components = URLComponents()
    components.queryItems = queryItems
    return components.percentEncodedQuery?.data(using: .utf8)
}

private func int64Value(_ value: Any?) -> Int64? {
    switch value {
    case let value as Int64:
        return value
    case let value as Int:
        return Int64(value)
    case let value as Double:
        return Int64(value)
    case let value as String:
        return Int64(value)
    default:
        return nil
    }
}

private enum ClaudeRefreshError: Error {
    case httpStatus(Int)
    case invalidResponse

    var statusCode: Int? {
        if case let .httpStatus(statusCode) = self { return statusCode }
        return nil
    }
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
