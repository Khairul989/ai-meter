import Foundation
import SwiftUI

// MARK: - Filter

struct AnalyticsFilter {
    var since: Date? = nil
    var until: Date? = nil
    var projectNames: Set<String> = []  // empty = all
}

// MARK: - Top-level result

struct AnalyticsResult {
    let grandTotals: GrandTotals
    let byModel: [ModelAnalytics]
    let byProject: [ProjectAnalytics]
    let dailyUsage: [DailyAnalytics]
    let sessionEfficiency: SessionEfficiency
    let cacheHitRatio: CacheAnalytics
    let tokensPerPrompt: PromptAnalytics
    let subagentOverhead: SubagentAnalytics
    let topSessions: [SessionSummary]
    let toolUsage: [ToolUsageEntry]
    let availableProjects: [String]
}

// MARK: - Grand Totals

struct GrandTotals {
    let projectCount: Int
    let sessionCount: Int
    let inputTokens: Int
    let cacheCreateTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let estimatedCostUSD: Double
    let costByModel: [ModelCostBreakdown]
}

struct ModelCostBreakdown: Identifiable {
    let id: String  // raw model name
    let displayName: String
    let totalTokens: Int
    let costUSD: Double
}

// MARK: - By Model

struct ModelAnalytics: Identifiable {
    let id: String  // raw model name
    let displayName: String
    let inputTokens: Int
    let cacheCreateTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let estimatedCostUSD: Double
    var totalTokens: Int { inputTokens + cacheCreateTokens + cacheReadTokens + outputTokens }
}

// MARK: - By Project

struct ProjectAnalytics: Identifiable {
    let id: String  // directory name
    let displayName: String
    let sessionCount: Int
    let totalTokens: Int
    let percentOfAll: Double
    let estimatedCostUSD: Double
    let subagentCount: Int
    let subagentTokens: Int
}

// MARK: - Daily

struct DailyAnalytics: Identifiable {
    let id: String  // date string yyyy-MM-dd
    let date: Date
    let sessions: Int
    let inputTokens: Int
    let cacheCreateTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let estimatedCostUSD: Double
    var totalTokens: Int { inputTokens + cacheCreateTokens + cacheReadTokens + outputTokens }
}

// MARK: - Efficiency

struct SessionEfficiency {
    let medianTokensPerMinute: Double
    let avgTokensPerMinute: Double
    let mostEfficient: SessionSummary?   // lowest tok/min among >1M sessions
    let leastEfficient: SessionSummary?  // highest tok/min
    let top10Longest: [SessionSummary]
}

// MARK: - Cache

struct CacheAnalytics {
    let overallHitRatio: Double  // 0.0-1.0
    let qualityLabel: String     // "Excellent"/"Good"/"Poor"
    let qualityColor: Color
    let perProject: [ProjectCacheEntry]
}

struct ProjectCacheEntry: Identifiable {
    let id: String
    let projectName: String
    let hitRatio: Double
    let cacheRead: Int
    let cacheCreate: Int
    let freshInput: Int
    let totalInput: Int
}

// MARK: - Prompts

struct PromptAnalytics {
    let medianTokensPerPrompt: Double
    let avgTokensPerPrompt: Double
    let minTokensPerPrompt: Int
    let maxTokensPerPrompt: Int
    let top10ExpensiveSessions: [SessionSummary]  // filtered to >=1M tokens
}

// MARK: - Subagents

struct SubagentAnalytics {
    let overallSharePercent: Double
    let grandSubTokens: Int
    let grandCombinedTokens: Int
    let perProject: [ProjectSubagentEntry]
}

struct ProjectSubagentEntry: Identifiable {
    let id: String
    let projectName: String
    let mainTokens: Int
    let subTokens: Int
    let combinedTokens: Int
    let overheadPercent: Double
}

// MARK: - Sessions

struct SessionSummary: Identifiable {
    let id: String  // sessionId
    let projectName: String
    let timestampStart: Date?
    let firstPromptPreview: String
    let totalTokens: Int
    let estimatedCostUSD: Double
    let durationMinutes: Double
    let tokensPerMinute: Double
    let promptCount: Int
    let subagentCount: Int
}

// MARK: - Tools

struct ToolUsageEntry: Identifiable {
    let id: String  // tool name
    let callCount: Int
}

// MARK: - Decodable conformances

extension GrandTotals: Decodable {}
extension ModelCostBreakdown: Decodable {}
extension ModelAnalytics: Decodable {}
extension ProjectAnalytics: Decodable {}
extension ProjectCacheEntry: Decodable {}
extension PromptAnalytics: Decodable {}
extension ProjectSubagentEntry: Decodable {}
extension SubagentAnalytics: Decodable {}
extension ToolUsageEntry: Decodable {}

extension DailyAnalytics: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let dateStr = try c.decode(String.self, forKey: .date)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone.current
        guard let d = fmt.date(from: dateStr) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "Invalid date: \(dateStr)")
        }
        date = d
        sessions = try c.decode(Int.self, forKey: .sessions)
        inputTokens = try c.decode(Int.self, forKey: .inputTokens)
        cacheCreateTokens = try c.decode(Int.self, forKey: .cacheCreateTokens)
        cacheReadTokens = try c.decode(Int.self, forKey: .cacheReadTokens)
        outputTokens = try c.decode(Int.self, forKey: .outputTokens)
        estimatedCostUSD = try c.decode(Double.self, forKey: .estimatedCostUSD)
    }

    enum CodingKeys: String, CodingKey {
        case id, date, sessions, inputTokens, cacheCreateTokens, cacheReadTokens, outputTokens, estimatedCostUSD
    }
}

extension SessionSummary: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectName = try c.decode(String.self, forKey: .projectName)
        firstPromptPreview = try c.decode(String.self, forKey: .firstPromptPreview)
        totalTokens = try c.decode(Int.self, forKey: .totalTokens)
        estimatedCostUSD = try c.decode(Double.self, forKey: .estimatedCostUSD)
        durationMinutes = try c.decode(Double.self, forKey: .durationMinutes)
        tokensPerMinute = try c.decode(Double.self, forKey: .tokensPerMinute)
        promptCount = try c.decode(Int.self, forKey: .promptCount)
        subagentCount = try c.decode(Int.self, forKey: .subagentCount)
        if let tsStr = try c.decodeIfPresent(String.self, forKey: .timestampStart) {
            let fmt = ISO8601DateFormatter()
            timestampStart = fmt.date(from: tsStr)
        } else {
            timestampStart = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, projectName, timestampStart, firstPromptPreview
        case totalTokens, estimatedCostUSD, durationMinutes, tokensPerMinute
        case promptCount, subagentCount
    }
}

extension SessionEfficiency: Decodable {}

extension CacheAnalytics: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overallHitRatio = try c.decode(Double.self, forKey: .overallHitRatio)
        qualityLabel = try c.decode(String.self, forKey: .qualityLabel)
        let colorStr = try c.decode(String.self, forKey: .qualityColor)
        switch colorStr {
        case "green":  qualityColor = .green
        case "yellow": qualityColor = .yellow
        case "red":    qualityColor = .red
        default:       qualityColor = .gray
        }
        perProject = try c.decode([ProjectCacheEntry].self, forKey: .perProject)
    }

    enum CodingKeys: String, CodingKey {
        case overallHitRatio, qualityLabel, qualityColor, perProject
    }
}

extension AnalyticsResult: Decodable {
    enum CodingKeys: String, CodingKey {
        case grandTotals, byModel, byProject, dailyUsage
        case sessionEfficiency, cacheHitRatio, tokensPerPrompt
        case subagentOverhead, topSessions, toolUsage, availableProjects
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grandTotals = try c.decode(GrandTotals.self, forKey: .grandTotals)
        byModel = try c.decode([ModelAnalytics].self, forKey: .byModel)
        byProject = try c.decode([ProjectAnalytics].self, forKey: .byProject)
        dailyUsage = try c.decode([DailyAnalytics].self, forKey: .dailyUsage)
        sessionEfficiency = try c.decode(SessionEfficiency.self, forKey: .sessionEfficiency)
        cacheHitRatio = try c.decode(CacheAnalytics.self, forKey: .cacheHitRatio)
        tokensPerPrompt = try c.decode(PromptAnalytics.self, forKey: .tokensPerPrompt)
        subagentOverhead = try c.decode(SubagentAnalytics.self, forKey: .subagentOverhead)
        topSessions = try c.decode([SessionSummary].self, forKey: .topSessions)
        toolUsage = try c.decode([ToolUsageEntry].self, forKey: .toolUsage)
        availableProjects = try c.decode([String].self, forKey: .availableProjects)
    }
}

// MARK: - Pricing

enum ModelPricing {
    struct Rate {
        let inputPer1M: Double
        let outputPer1M: Double
        let cacheCreatePer1M: Double
        let cacheReadPer1M: Double
    }

    static let table: [String: Rate] = [
        "claude-opus-4-6":           Rate(inputPer1M: 15.0, outputPer1M: 75.0, cacheCreatePer1M: 18.75, cacheReadPer1M: 1.50),
        "claude-sonnet-4-6":         Rate(inputPer1M: 3.0, outputPer1M: 15.0, cacheCreatePer1M: 3.75, cacheReadPer1M: 0.30),
        "claude-haiku-4-5-20251001": Rate(inputPer1M: 0.80, outputPer1M: 4.0, cacheCreatePer1M: 1.00, cacheReadPer1M: 0.08),
    ]

    static let defaultRate = Rate(inputPer1M: 3.0, outputPer1M: 15.0, cacheCreatePer1M: 3.75, cacheReadPer1M: 0.30)

    /// Look up pricing for a model, with prefix-match fallback for date-suffixed names
    static func rate(for model: String) -> Rate {
        if let rate = table[model] {
            return rate
        }
        let modelBase = model.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
        for (key, rate) in table {
            let keyBase = key.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
            if modelBase == keyBase {
                return rate
            }
        }
        return defaultRate
    }

    /// Calculate cost in USD
    static func cost(model: String, input: Int, output: Int, cacheCreate: Int, cacheRead: Int) -> Double {
        let rate = rate(for: model)
        return (Double(input) * rate.inputPer1M
              + Double(output) * rate.outputPer1M
              + Double(cacheCreate) * rate.cacheCreatePer1M
              + Double(cacheRead) * rate.cacheReadPer1M) / 1_000_000
    }

    /// Normalize raw model ID to display name: "claude-opus-4-6" -> "Opus 4.6"
    static func displayName(for model: String) -> String {
        let stripped = model.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
        let patterns: [(String, String)] = [
            (#"claude-opus-(\d+)-(\d+)"#, "Opus $1.$2"),
            (#"claude-sonnet-(\d+)-(\d+)"#, "Sonnet $1.$2"),
            (#"claude-haiku-(\d+)-(\d+)"#, "Haiku $1.$2"),
        ]
        for (pattern, template) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) {
                return regex.replacementString(for: match, in: stripped, offset: 0, template: template)
            }
        }
        return model
    }

    /// Human-readable token count: 3.29B, 776M, 448K, 123
    static func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.2fB", Double(n) / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    /// Format dollar cost
    static func formatCost(_ cost: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = cost >= 100 ? 0 : 2
        formatter.minimumFractionDigits = cost >= 100 ? 0 : 2
        return formatter.string(from: NSNumber(value: cost)) ?? String(format: "$%.2f", cost)
    }
}
