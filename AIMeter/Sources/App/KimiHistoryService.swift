import Foundation
import os
import AppKit

@MainActor
final class KimiHistoryService: ObservableObject {
    @Published var history: KimiHistory = KimiHistory()

    private static let historyFileURL: URL = AppConstants.Paths.kimiHistoryFile
    private static let logger = Logger(subsystem: "com.khairul.aimeter", category: "KimiHistoryService")
    private var saveTask: Task<Void, Never>?
    private var terminationObserver: Any?

    init() {
        try? FileManager.default.createDirectory(
            at: AppConstants.Paths.configDir,
            withIntermediateDirectories: true
        )
        loadHistory()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.flushToDisk() }
        }
    }

    deinit {
        saveTask?.cancel()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    func recordDataPoint(utilization: Int) {
        let point = KimiHistoryDataPoint(utilization: utilization)
        history.dataPoints.append(point)

        // Keep only last 7 days of data
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        history.dataPoints.removeAll { $0.timestamp < cutoff }

        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            await self.saveHistory()
        }
    }

    private func loadHistory() {
        let url = Self.historyFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            history = try JSONDecoder.appDecoder.decode(KimiHistory.self, from: data)
            pruneExpiredPoints()
        } catch {
            Self.logger.warning("History file corrupted (\(url.lastPathComponent)), moving to backup: \(error.localizedDescription)")
            let backup = url.deletingPathExtension().appendingPathExtension("bak.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
        }
    }

    private func saveHistory() {
        pruneExpiredPoints()
        guard let data = try? JSONEncoder.appEncoder.encode(history) else { return }
        try? data.write(to: Self.historyFileURL, options: .atomic)
    }

    private func flushToDisk() {
        saveTask?.cancel()
        saveTask = nil
        saveHistory()
    }

    private func pruneExpiredPoints() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        history.dataPoints.removeAll { $0.timestamp < cutoff }
    }
}
