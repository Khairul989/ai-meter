import Foundation

struct CopilotUsageData: Codable, Equatable {
    let plan: String
    let chat: CopilotQuota
    let completions: CopilotQuota
    let premiumInteractions: CopilotQuota
    let resetDate: Date?
    let fetchedAt: Date

    /// Highest usage % across non-unlimited quotas only
    var highestUtilization: Int {
        let limited = [chat, completions, premiumInteractions].filter { !$0.unlimited }
        return limited.map(\.utilization).max() ?? 0
    }

    static let empty = CopilotUsageData(
        plan: "",
        chat: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: false),
        completions: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: false),
        premiumInteractions: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: false),
        resetDate: nil,
        fetchedAt: .distantPast
    )
}

struct CopilotQuota: Codable, Equatable {
    let utilization: Int   // 0-100 usage percentage (0 when unlimited)
    let remaining: Int
    let entitlement: Int
    let unlimited: Bool
}
