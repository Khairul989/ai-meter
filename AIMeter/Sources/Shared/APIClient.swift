import Foundation

enum APIClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let isoFormatter = ISO8601DateFormatter()

    /// Fetch usage data from the API
    static func fetchUsage(token: String) async throws -> UsageData {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 5

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseResponse(data)
    }

    /// Parse the raw API response into our UsageData model (testable)
    static func parseResponse(_ data: Data) throws -> UsageData {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let fiveHour = parseRateLimit(json["five_hour"] as? [String: Any] ?? [:])
        let sevenDay = parseRateLimit(json["seven_day"] as? [String: Any] ?? [:])

        let sevenDaySonnet: RateLimit?
        if let sonnetDict = json["seven_day_sonnet"] as? [String: Any],
           sonnetDict["utilization"] != nil {
            sevenDaySonnet = parseRateLimit(sonnetDict)
        } else {
            sevenDaySonnet = nil
        }

        let extraCredits: ExtraCredits?
        if let extraDict = json["extra_usage"] as? [String: Any],
           extraDict["is_enabled"] as? Bool == true {
            extraCredits = ExtraCredits(
                utilization: percentFromFloat(extraDict["utilization"]),
                used: extraDict["used_credits"] as? Double ?? 0,
                limit: extraDict["monthly_limit"] as? Double ?? 0
            )
        } else {
            extraCredits = nil
        }

        return UsageData(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            sevenDaySonnet: sevenDaySonnet,
            extraCredits: extraCredits,
            fetchedAt: Date()
        )
    }

    private static func parseRateLimit(_ dict: [String: Any]) -> RateLimit {
        let resetsAt: Date?
        if let resetStr = dict["resets_at"] as? String {
            resetsAt = isoFormatter.date(from: resetStr)
        } else {
            resetsAt = nil
        }
        return RateLimit(
            utilization: percentFromFloat(dict["utilization"]),
            resetsAt: resetsAt
        )
    }

    /// API returns utilization as 0-100 percentage, convert to Int
    private static func percentFromFloat(_ value: Any?) -> Int {
        guard let floatVal = value as? Double else { return 0 }
        return Int(floatVal)
    }
}
