import Foundation

struct CodexUsageData: Codable, Equatable {
    let planType: String
    let primaryPercent: Int
    let secondaryPercent: Int
    let codeReviewPercent: Int
    let primaryResetAt: Date?
    let secondaryResetAt: Date?
    let fetchedAt: Date

    /// Highest usage % across primary and secondary windows
    var highestUtilization: Int {
        return max(primaryPercent, secondaryPercent)
    }

    static let empty = CodexUsageData(
        planType: "",
        primaryPercent: 0,
        secondaryPercent: 0,
        codeReviewPercent: 0,
        primaryResetAt: nil,
        secondaryResetAt: nil,
        fetchedAt: .distantPast
    )
}
