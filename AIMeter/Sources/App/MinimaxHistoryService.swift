import Foundation

@MainActor
final class MinimaxHistoryService: HistoryServiceBase<MinimaxHistory, MinimaxHistoryDataPoint> {
    private static let fileURL: URL = {
        try? FileManager.default.createDirectory(at: AppConstants.Paths.configDir, withIntermediateDirectories: true)
        return AppConstants.Paths.minimaxHistoryFile
    }()

    override var historyFileURL: URL { Self.fileURL }

    override var dataPoints: [MinimaxHistoryDataPoint] {
        get { history.dataPoints }
        set { history.dataPoints = newValue }
    }

    override func timestamp(of point: MinimaxHistoryDataPoint) -> Date {
        point.timestamp
    }

    init() {
        super.init(emptyHistory: MinimaxHistory())
    }

    func recordDataPoint(intervalPercent: Int) {
        let point = MinimaxHistoryDataPoint(intervalPercent: intervalPercent)
        history.dataPoints.append(point)
        markDirty()
    }
}
