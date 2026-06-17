import Foundation

func fetchZAI(apiKey: String) async -> ProviderResult {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
        return ProviderResult(errorMessage: "z.ai: API key not set. Add it in Settings.", updatedAt: Date())
    }

    do {
        let payload = try await fetchZAIQuota(apiKey: key)
        guard payload.success != false, payload.code == 200 else {
            return ProviderResult(errorMessage: "z.ai: \(payload.msg)", updatedAt: Date())
        }
        guard let data = payload.data else {
            return ProviderResult(errorMessage: "z.ai: missing data", updatedAt: Date())
        }

        let limits = data.limits ?? []
        let normalized = limits.map(normalizeZAILimit)
        let tokenLimits = normalized
            .filter { $0.type == .tokens }
            .sorted { ($0.windowMinutes ?? Int.max) < ($1.windowMinutes ?? Int.max) }
        let timeLimit = normalized.first { $0.type == .time }

        let primary: ZAINormalizedLimit?
        let weekly: ZAINormalizedLimit?
        if tokenLimits.count >= 2 {
            primary = tokenLimits.first
            weekly = tokenLimits.last
        } else if tokenLimits.count == 1 {
            primary = tokenLimits.first
            weekly = nil
        } else {
            primary = timeLimit
            weekly = nil
        }

        return ProviderResult(
            usedPercent: primary?.percent ?? 0,
            resetDescription: primary?.resetDescription,
            weeklyUsedPercent: weekly?.percent,
            weeklyResetDescription: weekly?.resetDescription,
            planLabel: data.planLabel,
            errorMessage: nil,
            updatedAt: Date())
    } catch let error as ZAIFetchError {
        return ProviderResult(errorMessage: error.message, updatedAt: Date())
    } catch {
        return ProviderResult(errorMessage: "z.ai: \(error.localizedDescription)", updatedAt: Date())
    }
}

private enum ZAIFetchError: Error {
    case http(Int)
    case emptyResponse

    var message: String {
        switch self {
        case let .http(code): return "z.ai: HTTP \(code)"
        case .emptyResponse: return "z.ai: empty response"
        }
    }
}

private let zaiQuotaURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!

private func fetchZAIQuota(apiKey: String) async throws -> ZAIResponse {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 90
    let session = URLSession(configuration: configuration)

    var request = URLRequest(url: zaiQuotaURL)
    request.httpMethod = "GET"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
    request.setValue("application/json", forHTTPHeaderField: "accept")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    guard http.statusCode == 200 else {
        throw ZAIFetchError.http(http.statusCode)
    }
    guard !data.isEmpty else {
        throw ZAIFetchError.emptyResponse
    }
    return try JSONDecoder().decode(ZAIResponse.self, from: data)
}

private struct ZAIResponse: Decodable {
    let code: Int
    let msg: String
    let data: ZAIData?
    let success: Bool?
}

private struct ZAIData: Decodable {
    let limits: [ZAILimit]?
    let planName: String?
    let plan: String?
    let planType: String?
    let packageName: String?
    let level: String?

    var planLabel: String? {
        planName ?? plan ?? planType ?? packageName ?? level
    }

    enum CodingKeys: String, CodingKey {
        case limits
        case planName
        case plan
        case planType = "plan_type"
        case packageName
        case level
    }
}

private struct ZAILimit: Decodable {
    let type: ZAILimitType
    let unit: Int?
    let number: Int?
    let usage: Double?
    let currentValue: Double?
    let remaining: Double?
    let percentage: Double?
    let nextResetTime: Double?
}

private enum ZAILimitType: String, Decodable {
    case time = "TIME_LIMIT"
    case tokens = "TOKENS_LIMIT"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = (try? container.decode(String.self)) ?? ""
        self = ZAILimitType(rawValue: value) ?? .unknown
    }
}

private struct ZAINormalizedLimit {
    let type: ZAILimitType
    let windowMinutes: Int?
    let percent: Double
    let resetDescription: String?
}

private func normalizeZAILimit(_ limit: ZAILimit) -> ZAINormalizedLimit {
    let windowMinutes = zaiWindowMinutes(unit: limit.unit, number: limit.number)
    let percent = zaiUsedPercent(
        usage: limit.usage ?? 0,
        currentValue: limit.currentValue,
        remaining: limit.remaining,
        percentage: limit.percentage)

    return ZAINormalizedLimit(
        type: limit.type,
        windowMinutes: windowMinutes,
        percent: percent,
        resetDescription: zaiResetDescription(for: limit))
}

private func zaiWindowMinutes(unit: Int?, number: Int?) -> Int? {
    guard let unit, let number else { return nil }
    switch unit {
    case 1: return number * 1_440
    case 3: return number * 60
    case 5: return number
    case 6: return number * 10_080
    default: return nil
    }
}

private func zaiUsedPercent(
    usage: Double,
    currentValue: Double?,
    remaining: Double?,
    percentage: Double?
) -> Double {
    if usage > 0 {
        let usedRaw: Double
        if let remaining, let currentValue {
            usedRaw = max(usage - remaining, currentValue)
        } else if let currentValue {
            usedRaw = currentValue
        } else if let remaining {
            usedRaw = usage - remaining
        } else {
            usedRaw = 0
        }
        return clamp((clamp(usedRaw, min: 0, max: usage) / usage) * 100, min: 0, max: 100)
    }

    return clamp(percentage ?? 0, min: 0, max: 100)
}

private func zaiResetDescription(for limit: ZAILimit) -> String? {
    if limit.type == .time, limit.unit == 5, limit.number == 1 {
        return "Monthly"
    }

    guard let nextResetTime = limit.nextResetTime else {
        return nil
    }
    let date = Date(timeIntervalSince1970: nextResetTime / 1_000)
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return "resets \(formatter.localizedString(for: date, relativeTo: Date()))"
}

private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
    Swift.min(Swift.max(value, minimum), maximum)
}
