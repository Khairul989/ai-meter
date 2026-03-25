import Foundation

// MARK: - Usage Data Models for GetUsages endpoint

struct KimiUsageData: Codable, Equatable {
    let scope: String
    let detail: KimiUsageDetail
    let limits: [KimiLimitWindow]
    let fetchedAt: Date

    static let empty = KimiUsageData(
        scope: "FEATURE_CODING",
        detail: KimiUsageDetail(limit: 0, used: 0, remaining: 0, resetTime: nil),
        limits: [],
        fetchedAt: .distantPast
    )

    /// Total usage percentage (0-100)
    var utilizationPercent: Int {
        guard detail.limit > 0 else { return 0 }
        return Int((Double(detail.used) / Double(detail.limit)) * 100)
    }

    /// True if usage is at or over limit
    var isOverLimit: Bool {
        detail.remaining <= 0
    }

    /// Formatted reset time string
    var resetTimeFormatted: String? {
        guard let resetTime = detail.resetTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: resetTime)
    }
}

struct KimiUsageDetail: Codable, Equatable {
    let limit: Int
    let used: Int
    let remaining: Int
    let resetTime: Date?

    enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remaining
        case resetTime = "resetTime"
    }
}

struct KimiLimitWindow: Codable, Equatable {
    let window: KimiWindowConfig
    let detail: KimiUsageDetail
}

struct KimiWindowConfig: Codable, Equatable {
    let duration: Int
    let timeUnit: String
}

// MARK: - Date Helpers

extension String {
    func toISO8601Date() -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: self)
    }
}
