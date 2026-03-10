import Foundation

func fetchOpenCode(cookieHeader: String) async -> ProviderResult {
    let cookie = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cookie.isEmpty else {
        return ProviderResult(errorMessage: "OpenCode: Paste session cookie in Settings.", updatedAt: Date())
    }

    do {
        let workspaceID = try await fetchOpenCodeWorkspaceID(cookie: cookie)
        let payload = try await fetchOpenCodeSubscription(cookie: cookie, workspaceID: workspaceID)

        if payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "null" {
            return ProviderResult(
                errorMessage: "OpenCode: No subscription usage data for this workspace.",
                updatedAt: Date())
        }

        guard let usage = parseOpenCodeUsage(payload) else {
            return ProviderResult(errorMessage: "OpenCode: Could not parse usage data.", updatedAt: Date())
        }

        return ProviderResult(
            usedPercent: usage.rollingUsagePercent,
            resetDescription: "resets in \(formatDuration(seconds: usage.rollingResetInSec))",
            planLabel: "OpenCode",
            errorMessage: nil,
            updatedAt: Date())
    } catch let error as OpenCodeFetchError {
        return ProviderResult(errorMessage: error.message, updatedAt: Date())
    } catch {
        return ProviderResult(errorMessage: "OpenCode: \(error.localizedDescription)", updatedAt: Date())
    }
}

private enum OpenCodeFetchError: Error {
    case invalidCookie
    case parseWorkspaceID
    case http(Int)

    var message: String {
        switch self {
        case .invalidCookie:
            return "OpenCode cookie invalid or expired."
        case .parseWorkspaceID:
            return "OpenCode: Could not parse workspace ID."
        case let .http(code):
            return "OpenCode: HTTP \(code)"
        }
    }
}

private let openCodeServerURL = URL(string: "https://opencode.ai/_server")!
private let openCodeWorkspacesServerID = "def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f"
private let openCodeSubscriptionServerID = "7abeebee372f304e050aaaf92be863f4a86490e382f8c79db68fd94040d691b4"

private func fetchOpenCodeWorkspaceID(cookie: String) async throws -> String {
    let getText = try await fetchOpenCodeServerText(
        method: "GET",
        serverID: openCodeWorkspacesServerID,
        args: nil,
        cookie: cookie,
        referer: "https://opencode.ai")

    if looksOpenCodeSignedOut(getText) {
        throw OpenCodeFetchError.invalidCookie
    }

    if let id = parseWorkspaceID(from: getText) {
        return id
    }

    let postText = try await fetchOpenCodeServerText(
        method: "POST",
        serverID: openCodeWorkspacesServerID,
        args: [],
        cookie: cookie,
        referer: "https://opencode.ai")

    if looksOpenCodeSignedOut(postText) {
        throw OpenCodeFetchError.invalidCookie
    }

    guard let id = parseWorkspaceID(from: postText) else {
        throw OpenCodeFetchError.parseWorkspaceID
    }
    return id
}

private func fetchOpenCodeSubscription(cookie: String, workspaceID: String) async throws -> String {
    let referer = "https://opencode.ai/workspace/\(workspaceID)/billing"

    let getText = try await fetchOpenCodeServerText(
        method: "GET",
        serverID: openCodeSubscriptionServerID,
        args: [workspaceID],
        cookie: cookie,
        referer: referer)

    if looksOpenCodeSignedOut(getText) {
        throw OpenCodeFetchError.invalidCookie
    }

    if parseOpenCodeUsage(getText) != nil || getText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "null" {
        return getText
    }

    let postText = try await fetchOpenCodeServerText(
        method: "POST",
        serverID: openCodeSubscriptionServerID,
        args: [workspaceID],
        cookie: cookie,
        referer: referer)

    if looksOpenCodeSignedOut(postText) {
        throw OpenCodeFetchError.invalidCookie
    }

    return postText
}

private func fetchOpenCodeServerText(
    method: String,
    serverID: String,
    args: [Any]?,
    cookie: String,
    referer: String
) async throws -> String {
    let url: URL
    if method == "GET" {
        var components = URLComponents(url: openCodeServerURL, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "id", value: serverID)]
        if let args, !args.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: args),
           let argsString = String(data: data, encoding: .utf8)
        {
            queryItems.append(URLQueryItem(name: "args", value: argsString))
        }
        components?.queryItems = queryItems
        url = components?.url ?? openCodeServerURL
    } else {
        url = openCodeServerURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 15
    request.setValue(cookie, forHTTPHeaderField: "Cookie")
    request.setValue(serverID, forHTTPHeaderField: "X-Server-Id")
    request.setValue("server-fn:\(UUID().uuidString)", forHTTPHeaderField: "X-Server-Instance")
    request.setValue(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
        forHTTPHeaderField: "User-Agent")
    request.setValue("https://opencode.ai", forHTTPHeaderField: "Origin")
    request.setValue(referer, forHTTPHeaderField: "Referer")
    request.setValue("text/javascript, application/json;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")

    if method != "GET", let args {
        request.httpBody = try JSONSerialization.data(withJSONObject: args)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }

    if http.statusCode == 401 || http.statusCode == 403 {
        throw OpenCodeFetchError.invalidCookie
    }
    guard (200...299).contains(http.statusCode) else {
        throw OpenCodeFetchError.http(http.statusCode)
    }
    guard let text = String(data: data, encoding: .utf8) else {
        throw URLError(.cannotDecodeRawData)
    }
    return text
}

private func parseWorkspaceID(from text: String) -> String? {
    let pattern = #"id\s*:\s*\"(wrk_[^\"]+)\""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let idRange = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[idRange])
}

private func looksOpenCodeSignedOut(_ text: String) -> Bool {
    let lower = text.lowercased()
    return lower.contains("login") || lower.contains("sign in")
}

private struct OpenCodeUsageParsed {
    let rollingUsagePercent: Double
    let rollingResetInSec: Int
}

private func parseOpenCodeUsage(_ text: String) -> OpenCodeUsageParsed? {
    if let data = text.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) {
        if object is NSNull {
            return nil
        }
        if let parsed = parseOpenCodeUsageFromJSON(object) {
            return parsed
        }
    }

    guard let percent = extractOpenCodeDouble(
        pattern: #"rollingUsage[^}]*?usagePercent\s*:\s*([0-9]+(?:\.[0-9]+)?)"#,
        text: text)
    else {
        return nil
    }

    let reset = extractOpenCodeInt(
        pattern: #"rollingUsage[^}]*?(?:resetInSec|resetInSeconds|resetSeconds)\s*:\s*([0-9]+)"#,
        text: text) ?? 0

    return OpenCodeUsageParsed(rollingUsagePercent: percent, rollingResetInSec: reset)
}

private func parseOpenCodeUsageFromJSON(_ object: Any) -> OpenCodeUsageParsed? {
    if let dict = object as? [String: Any],
       let rolling = findRollingDict(in: dict)
    {
        let percent = numberFromAny(rolling["usagePercent"]) ?? numberFromAny(rolling["utilization"])
        if let percent {
            let reset = intFromAny(rolling["resetInSec"]) ?? 0
            let normalized = percent <= 1.0 ? percent * 100 : percent
            return OpenCodeUsageParsed(rollingUsagePercent: normalized, rollingResetInSec: reset)
        }
    }
    return nil
}

private func findRollingDict(in dict: [String: Any]) -> [String: Any]? {
    if let rolling = dict["rollingUsage"] as? [String: Any] {
        return rolling
    }
    for value in dict.values {
        if let nested = value as? [String: Any],
           let found = findRollingDict(in: nested)
        {
            return found
        }
    }
    return nil
}

private func extractOpenCodeDouble(pattern: String, text: String) -> Double? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let valueRange = Range(match.range(at: 1), in: text)
    else { return nil }
    return Double(text[valueRange])
}

private func extractOpenCodeInt(pattern: String, text: String) -> Int? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let valueRange = Range(match.range(at: 1), in: text)
    else { return nil }
    return Int(text[valueRange])
}

private func numberFromAny(_ value: Any?) -> Double? {
    switch value {
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
}

private func intFromAny(_ value: Any?) -> Int? {
    switch value {
    case let n as NSNumber: return n.intValue
    case let s as String: return Int(s)
    default: return nil
    }
}

private func formatDuration(seconds: Int) -> String {
    let safe = max(0, seconds)
    let hours = safe / 3600
    let minutes = (safe % 3600) / 60
    return "\(hours)h \(minutes)m"
}
