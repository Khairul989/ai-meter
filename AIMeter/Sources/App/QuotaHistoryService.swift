import Foundation

@MainActor
final class QuotaHistoryService: HistoryServiceBase<QuotaHistory, QuotaDataPoint> {
    private static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aimeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    override var historyFileURL: URL { Self.fileURL }

    override var dataPoints: [QuotaDataPoint] {
        get { history.dataPoints }
        set { history.dataPoints = newValue }
    }

    override func timestamp(of point: QuotaDataPoint) -> Date {
        point.timestamp
    }

    init() {
        super.init(emptyHistory: QuotaHistory())
    }

    func recordDataPoint(session: Double, weekly: Double) {
        let point = QuotaDataPoint(session: session, weekly: weekly)
        history.dataPoints.append(point)
        markDirty()
    }

    func downsampledPoints(for range: QuotaTimeRange) -> [QuotaDataPoint] {
        let cutoff = Date().addingTimeInterval(-range.interval)
        let filtered = history.dataPoints.filter { $0.timestamp >= cutoff }
        guard filtered.count > range.targetPointCount else { return filtered }

        let bucketCount = range.targetPointCount
        let bucketDuration = range.interval / Double(bucketCount)

        var buckets = [[QuotaDataPoint]](repeating: [], count: bucketCount)
        for point in filtered {
            let offset = point.timestamp.timeIntervalSince(cutoff)
            var index = Int(offset / bucketDuration)
            if index < 0 { index = 0 }
            if index >= bucketCount { index = bucketCount - 1 }
            buckets[index].append(point)
        }

        return buckets.compactMap { bucket -> QuotaDataPoint? in
            guard !bucket.isEmpty else { return nil }
            let avgSession = bucket.map(\.session).reduce(0, +) / Double(bucket.count)
            let avgWeekly = bucket.map(\.weekly).reduce(0, +) / Double(bucket.count)
            let avgTime = bucket.map { $0.timestamp.timeIntervalSince1970 }.reduce(0, +) / Double(bucket.count)
            return QuotaDataPoint(
                timestamp: Date(timeIntervalSince1970: avgTime),
                session: avgSession,
                weekly: avgWeekly
            )
        }
    }
}
