import Foundation

enum CopilotAPIError: Error {
    case rateLimited(retryAfter: TimeInterval)
    case fetchFailed
}

enum CopilotAPIClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    private static let endpoint = URL(string: "https://api.github.com/copilot_internal/user")!
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fetch Copilot usage data from the GitHub API
    static func fetchUsage(token: String) async throws -> CopilotUsageData {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 5

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            let retryAfter = (http.value(forHTTPHeaderField: "retry-after"))
                .flatMap { TimeInterval($0) } ?? 60
            throw CopilotAPIError.rateLimited(retryAfter: retryAfter)
        }

        return try parseResponse(data)
    }

    /// Parse the raw API response into CopilotUsageData (testable)
    static func parseResponse(_ data: Data) throws -> CopilotUsageData {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let plan = json["copilot_plan"] as? String ?? ""

        let resetDate: Date?
        if let resetStr = json["quota_reset_date_utc"] as? String {
            resetDate = isoFormatter.date(from: resetStr)
        } else {
            resetDate = nil
        }

        let snapshots = json["quota_snapshots"] as? [String: Any] ?? [:]
        let chat = parseQuota(snapshots["chat"] as? [String: Any] ?? [:])
        let completions = parseQuota(snapshots["completions"] as? [String: Any] ?? [:])
        let premiumInteractions = parseQuota(snapshots["premium_interactions"] as? [String: Any] ?? [:])

        return CopilotUsageData(
            plan: plan,
            chat: chat,
            completions: completions,
            premiumInteractions: premiumInteractions,
            resetDate: resetDate,
            fetchedAt: Date()
        )
    }

    private static func parseQuota(_ dict: [String: Any]) -> CopilotQuota {
        let unlimited = dict["unlimited"] as? Bool ?? false
        let remaining = dict["remaining"] as? Int ?? 0
        let entitlement = dict["entitlement"] as? Int ?? 0

        // percent_remaining is how much is LEFT — convert to usage percentage
        // When unlimited, show 0 (not meaningful to calculate usage)
        let utilization: Int
        if unlimited {
            utilization = 0
        } else {
            let percentRemaining = dict["percent_remaining"] as? Double ?? 100.0
            utilization = Int((100.0 - percentRemaining).rounded())
        }

        return CopilotQuota(
            utilization: utilization,
            remaining: remaining,
            entitlement: entitlement,
            unlimited: unlimited
        )
    }
}
