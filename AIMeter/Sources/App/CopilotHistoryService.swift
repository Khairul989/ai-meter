import Foundation

@MainActor
final class CopilotHistoryService: HistoryServiceBase<CopilotHistory, CopilotHistoryDataPoint> {
    private static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aimeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("copilot-history.json")
    }()

    override var historyFileURL: URL { Self.fileURL }

    override var dataPoints: [CopilotHistoryDataPoint] {
        get { history.dataPoints }
        set { history.dataPoints = newValue }
    }

    override func timestamp(of point: CopilotHistoryDataPoint) -> Date {
        point.timestamp
    }

    init() {
        super.init(emptyHistory: CopilotHistory())
    }

    func recordSnapshot(_ data: CopilotUsageData) {
        let point = CopilotHistoryDataPoint(from: data)
        history.dataPoints.append(point)
        markDirty()
    }

    func downsampledPoints(for range: QuotaTimeRange) -> [CopilotHistoryDataPoint] {
        let cutoff = Date().addingTimeInterval(-range.interval)
        let filtered = history.dataPoints.filter { $0.timestamp >= cutoff }
        guard filtered.count > range.targetPointCount else { return filtered }

        let bucketCount = range.targetPointCount
        let bucketDuration = range.interval / Double(bucketCount)

        var buckets = [[CopilotHistoryDataPoint]](repeating: [], count: bucketCount)
        for point in filtered {
            let offset = point.timestamp.timeIntervalSince(cutoff)
            var index = Int(offset / bucketDuration)
            if index < 0 { index = 0 }
            if index >= bucketCount { index = bucketCount - 1 }
            buckets[index].append(point)
        }

        return buckets.compactMap { bucket -> CopilotHistoryDataPoint? in
            guard !bucket.isEmpty else { return nil }
            let avgTime = bucket.map { $0.timestamp.timeIntervalSince1970 }.reduce(0, +) / Double(bucket.count)

            func avgNilableInt(_ keyPath: KeyPath<CopilotHistoryDataPoint, Int?>) -> Int? {
                let nonNil = bucket.compactMap { $0[keyPath: keyPath] }
                guard !nonNil.isEmpty else { return nil }
                return Int((Double(nonNil.reduce(0, +)) / Double(nonNil.count)).rounded())
            }

            // Build a synthetic CopilotUsageData from bucket averages to reuse the initializer
            // We use a custom init directly instead to avoid reconstructing CopilotUsageData
            return CopilotHistoryDataPoint(
                timestamp: Date(timeIntervalSince1970: avgTime),
                chatUtilization: avgNilableInt(\.chatUtilization),
                chatRemaining: avgNilableInt(\.chatRemaining),
                completionsUtilization: avgNilableInt(\.completionsUtilization),
                completionsRemaining: avgNilableInt(\.completionsRemaining),
                premiumUtilization: avgNilableInt(\.premiumUtilization),
                premiumRemaining: avgNilableInt(\.premiumRemaining)
            )
        }
    }
}
