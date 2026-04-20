import Foundation

enum APIError: Error, Equatable {
    case noCredentials
    case fetchFailed
    case sessionExpired
    case cloudflareBlocked
    case rateLimited(retryAfter: TimeInterval)
}

enum APIClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fetch usage data from claude.ai web API
    static func fetchUsage(sessionKey: String, orgId: String) async throws -> UsageData {
        let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        ClaudeHeaderBuilder.applyHeaders(to: &request, sessionKey: sessionKey, orgId: orgId)

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299:
                break
            case 401:
                throw APIError.sessionExpired
            case 403:
                // Check if Cloudflare blocked
                if let body = String(data: data, encoding: .utf8),
                   body.contains("<!DOCTYPE html>") || body.contains("<html") {
                    throw APIError.cloudflareBlocked
                }
                throw APIError.sessionExpired
            case 429:
                let retryAfter = (http.value(forHTTPHeaderField: "retry-after"))
                    .flatMap { TimeInterval($0) } ?? 60
                throw APIError.rateLimited(retryAfter: retryAfter)
            default:
                throw APIError.fetchFailed
            }
        }

        return try parseResponse(data)
    }

    /// Fetch extra usage (overage spend limit) — optional, failures are non-fatal
    static func fetchExtraUsage(sessionKey: String, orgId: String) async -> (credits: ExtraCredits?, planName: String?) {
        let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/overage_spend_limit")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        ClaudeHeaderBuilder.applyHeaders(to: &request, sessionKey: sessionKey, orgId: orgId)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return (nil, nil)
        }

        return parseExtraUsage(data)
    }

    // MARK: - Parsing

    static func parseResponse(_ data: Data) throws -> UsageData {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // Check for error response
        if let error = json["error"] as? [String: Any],
           let type = error["type"] as? String,
           type == "permission_error" {
            throw APIError.sessionExpired
        }

        let fiveHour = parseRateLimit(json["five_hour"] as? [String: Any] ?? [:])
            ?? RateLimit(utilization: 0, resetsAt: nil)
        let sevenDay = parseRateLimit(json["seven_day"] as? [String: Any])

        let sevenDaySonnet: RateLimit?
        if let dict = json["seven_day_sonnet"] as? [String: Any], dict["utilization"] != nil {
            sevenDaySonnet = parseRateLimit(dict)
        } else {
            sevenDaySonnet = nil
        }

        let sevenDayDesign: RateLimit?
        if let dict = json["seven_day_omelette"] as? [String: Any], dict["utilization"] != nil {
            sevenDayDesign = parseRateLimit(dict)
        } else {
            sevenDayDesign = nil
        }

        // Parse extra_usage inline if present and enabled; fallback path will fill this if absent
        let extraCredits: ExtraCredits?
        if let extraDict = json["extra_usage"] as? [String: Any],
           let isEnabled = extraDict["is_enabled"] as? Bool,
           isEnabled,
           let monthlyLimit = extraDict["monthly_limit"] as? Double,
           let usedCredits = extraDict["used_credits"] as? Double {
            let utilization = extraDict["utilization"] as? Double ?? 0
            // API returns cents — convert to dollars
            extraCredits = ExtraCredits(utilization: Int(utilization), used: usedCredits / 100, limit: monthlyLimit / 100)
        } else {
            extraCredits = nil
        }

        return UsageData(
            fiveHour: fiveHour,
            sevenDay: sevenDay ?? RateLimit(utilization: 0, resetsAt: nil),
            sevenDaySonnet: sevenDaySonnet,
            sevenDayDesign: sevenDayDesign,
            extraCredits: extraCredits,
            planName: nil,
            fetchedAt: Date()
        )
    }

    private static func parseRateLimit(_ dict: [String: Any]?) -> RateLimit? {
        guard let dict else { return nil }
        let utilization = dict["utilization"] as? Double ?? 0
        // Skip if zero utilization with no reset time (not started)
        if utilization == 0 && dict["resets_at"] == nil { return nil }

        let resetsAt: Date?
        if let resetStr = dict["resets_at"] as? String {
            resetsAt = isoFormatter.date(from: resetStr)
        } else {
            resetsAt = nil
        }
        return RateLimit(utilization: Int(utilization), resetsAt: resetsAt)
    }

    static func parseExtraUsage(_ data: Data) -> (credits: ExtraCredits?, planName: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }

        let rawPlanName = json["seat_tier"] as? String
        let planName = rawPlanName.flatMap { SessionAuthManager.parsePlanName(rateLimitTier: $0) } ?? rawPlanName

        guard let limitCents = json["spend_limit_amount_cents"] as? Int, limitCents > 0 else {
            return (nil, planName)
        }
        let balanceCents = json["balance_cents"] as? Int ?? 0
        // Convert cents to dollars to match the inline extra_usage unit
        let limit = Double(limitCents) / 100
        let used = Double(balanceCents) / 100
        let utilization = limit > 0 ? Int((used / limit) * 100) : 0

        return (ExtraCredits(utilization: utilization, used: used, limit: limit), planName)
    }
}
