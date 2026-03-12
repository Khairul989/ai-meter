import Foundation
import Combine
import AppKit

@MainActor
class HistoryServiceBase<History: Codable, DataPoint>: ObservableObject {
    @Published var history: History

    private var flushTimer: AnyCancellable?
    var isDirty = false
    private var terminationObserver: Any?

    static var retentionInterval: TimeInterval { 7 * 86400 }
    private static var flushInterval: TimeInterval { 300 }

    /// Subclasses must provide the file URL for persistence
    var historyFileURL: URL {
        fatalError("Subclasses must override historyFileURL")
    }

    /// Subclasses must provide access to the data points array for pruning and persistence
    var dataPoints: [DataPoint] {
        get { fatalError("Subclasses must override dataPoints getter") }
        set { fatalError("Subclasses must override dataPoints setter") }
    }

    /// Subclasses must provide the timestamp of a data point for pruning
    func timestamp(of point: DataPoint) -> Date {
        fatalError("Subclasses must override timestamp(of:)")
    }

    init(emptyHistory: History) {
        self.history = emptyHistory
        loadHistory()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.flushToDisk() }
        }
    }

    deinit {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func markDirty() {
        isDirty = true
        startFlushTimerIfNeeded()
    }

    func flushToDisk() {
        guard isDirty else { return }
        dataPoints = pruned(dataPoints)
        guard let data = try? JSONEncoder.appEncoder.encode(history) else { return }
        try? data.write(to: historyFileURL, options: .atomic)
        isDirty = false
        flushTimer?.cancel()
        flushTimer = nil
    }

    private func loadHistory() {
        let url = historyFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            history = try JSONDecoder.appDecoder.decode(History.self, from: data)
            dataPoints = pruned(dataPoints)
        } catch {
            let backup = url.deletingPathExtension().appendingPathExtension("bak.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
        }
    }

    private func startFlushTimerIfNeeded() {
        guard flushTimer == nil else { return }
        flushTimer = Timer.publish(every: Self.flushInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.flushToDisk() }
    }

    func pruned(_ points: [DataPoint]) -> [DataPoint] {
        let cutoff = Date().addingTimeInterval(-Self.retentionInterval)
        return points.filter { timestamp(of: $0) >= cutoff }
    }
}
