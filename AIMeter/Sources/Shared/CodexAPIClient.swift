import Foundation

enum CodexAPIError: Error {
    case rateLimited(retryAfter: TimeInterval)
    case unauthorized
    case fetchFailed
}

enum CodexAPIClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// Fetch Codex usage data from the ChatGPT API
    static func fetchUsage(token: String) async throws -> CodexUsageData {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 {
                let retryAfter = (http.value(forHTTPHeaderField: "retry-after"))
                    .flatMap { TimeInterval($0) } ?? 60
                throw CodexAPIError.rateLimited(retryAfter: retryAfter)
            }
            if http.statusCode == 401 {
                throw CodexAPIError.unauthorized
            }
        }

        return try parseResponse(data)
    }

    /// Parse the raw API response into CodexUsageData (testable)
    static func parseResponse(_ data: Data) throws -> CodexUsageData {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let planType = json["plan_type"] as? String ?? ""

        // Parse primary window
        let rateLimit = json["rate_limit"] as? [String: Any] ?? [:]
        let primaryWindow = rateLimit["primary_window"] as? [String: Any] ?? [:]
        let primaryPercent = primaryWindow["used_percent"] as? Int ?? 0
        let primaryResetAt = unixEpochToDate(primaryWindow["reset_at"])

        // Secondary window may be null/missing
        let secondaryWindow = rateLimit["secondary_window"] as? [String: Any]
        let secondaryPercent = secondaryWindow?["used_percent"] as? Int ?? 0
        let secondaryResetAt = unixEpochToDate(secondaryWindow?["reset_at"])

        // code_review_rate_limit may be missing entirely
        let codeReviewRateLimit = json["code_review_rate_limit"] as? [String: Any]
        let codeReviewPrimaryWindow = codeReviewRateLimit?["primary_window"] as? [String: Any]
        let codeReviewPercent = codeReviewPrimaryWindow?["used_percent"] as? Int ?? 0

        return CodexUsageData(
            planType: planType,
            primaryPercent: primaryPercent,
            secondaryPercent: secondaryPercent,
            codeReviewPercent: codeReviewPercent,
            primaryResetAt: primaryResetAt,
            secondaryResetAt: secondaryResetAt,
            fetchedAt: Date()
        )
    }

    /// Convert a Unix epoch timestamp (Double or Int) to Date, returning nil if absent
    private static func unixEpochToDate(_ value: Any?) -> Date? {
        if let ts = value as? Double {
            return Date(timeIntervalSince1970: ts)
        }
        if let ts = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(ts))
        }
        return nil
    }
}
