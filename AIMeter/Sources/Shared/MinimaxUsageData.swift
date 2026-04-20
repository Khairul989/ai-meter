import Foundation

struct MinimaxModelQuota: Codable, Equatable, Identifiable {
    var id: String { modelName }
    let modelName: String
    let intervalPercent: Int
    let weeklyPercent: Int
    let intervalUsed: Int
    let intervalTotal: Int
    let weeklyUsed: Int
    let weeklyTotal: Int
    let resetsAt: Date?
    let weeklyResetsAt: Date?

    var displayName: String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown Model" }

        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                let raw = String(token)
                let lower = raw.lowercased()

                if lower == "minimax" {
                    return "MiniMax"
                }
                if raw.first?.isNumber == true {
                    return raw
                }
                if raw.count <= 2 {
                    return raw.uppercased()
                }
                return raw.prefix(1).uppercased() + raw.dropFirst()
            }
            .joined(separator: " ")
    }
}

struct MinimaxUsageData: Codable, Equatable {
    let models: [MinimaxModelQuota]
    let fetchedAt: Date

    var highestIntervalPercent: Int {
        models.map(\.intervalPercent).max() ?? 0
    }

    var highestWeeklyPercent: Int {
        models.map(\.weeklyPercent).max() ?? 0
    }

    var nextResetAt: Date? {
        guard let topModel = models.max(by: { $0.intervalPercent < $1.intervalPercent }),
              let resetsAt = topModel.resetsAt else { return nil }
        return resetsAt
    }

    static let empty = MinimaxUsageData(models: [], fetchedAt: .distantPast)
}
