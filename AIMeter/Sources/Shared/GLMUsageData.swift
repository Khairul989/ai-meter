import Foundation

struct GLMUsageData: Codable, Equatable {
    let tokensPercent: Int   // TOKENS_LIMIT.percentage
    let tier: String         // data.level e.g. "pro"
    let fetchedAt: Date

    static let empty = GLMUsageData(
        tokensPercent: 0,
        tier: "",
        fetchedAt: .distantPast
    )
}
