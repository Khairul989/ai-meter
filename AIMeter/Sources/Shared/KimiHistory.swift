import Foundation

struct KimiHistoryDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let utilization: Int

    init(utilization: Int) {
        self.id = UUID()
        self.timestamp = Date()
        self.utilization = utilization
    }
}

struct KimiHistory: Codable {
    var dataPoints: [KimiHistoryDataPoint] = []
}
