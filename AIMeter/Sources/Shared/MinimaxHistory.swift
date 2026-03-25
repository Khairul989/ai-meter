import Foundation

struct MinimaxHistoryDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let intervalPercent: Int

    init(intervalPercent: Int) {
        self.id = UUID()
        self.timestamp = Date()
        self.intervalPercent = intervalPercent
    }
}

struct MinimaxHistory: Codable {
    var dataPoints: [MinimaxHistoryDataPoint] = []
}
