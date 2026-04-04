import XCTest
import AppKit
@testable import AIMeter

@MainActor
final class KimiHistoryServiceTests: XCTestCase {
    private let historyURL = AppConstants.Paths.kimiHistoryFile
    private var originalHistoryBackupURL: URL?
    private var originalCorruptBackupURL: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        try FileManager.default.createDirectory(
            at: AppConstants.Paths.configDir,
            withIntermediateDirectories: true
        )
        try backupIfPresent(historyURL, assignTo: \.originalHistoryBackupURL)
        try backupIfPresent(corruptBackupURL, assignTo: \.originalCorruptBackupURL)
        try? FileManager.default.removeItem(at: historyURL)
        try? FileManager.default.removeItem(at: corruptBackupURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: historyURL)
        try? FileManager.default.removeItem(at: corruptBackupURL)

        if let originalHistoryBackupURL {
            try FileManager.default.moveItem(at: originalHistoryBackupURL, to: historyURL)
        }

        if let originalCorruptBackupURL {
            try FileManager.default.moveItem(at: originalCorruptBackupURL, to: corruptBackupURL)
        }

        originalHistoryBackupURL = nil
        originalCorruptBackupURL = nil
        try super.tearDownWithError()
    }

    func testLoadHistoryDecodesAppEncodedDataAndPrunesExpiredPoints() throws {
        let recentDate = Date().addingTimeInterval(-3600)
        let expiredDate = Date().addingTimeInterval(-(8 * 24 * 60 * 60))
        let payload = """
        {
          "dataPoints": [
            {
              "id": "\(UUID())",
              "timestamp": "\(ISO8601DateFormatter().string(from: expiredDate))",
              "utilization": 12
            },
            {
              "id": "\(UUID())",
              "timestamp": "\(ISO8601DateFormatter().string(from: recentDate))",
              "utilization": 63
            }
          ]
        }
        """.data(using: .utf8)!

        try payload.write(to: historyURL, options: .atomic)

        let service = KimiHistoryService()

        XCTAssertEqual(service.history.dataPoints.count, 1)
        XCTAssertEqual(service.history.dataPoints.first?.utilization, 63)
    }

    func testWillTerminateNotificationFlushesPendingHistoryImmediately() throws {
        var service: KimiHistoryService? = KimiHistoryService()
        service?.history.dataPoints = []
        service?.recordDataPoint(utilization: 47)

        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)

        let data = try Data(contentsOf: historyURL)
        let decoded = try JSONDecoder.appDecoder.decode(KimiHistory.self, from: data)

        XCTAssertEqual(decoded.dataPoints.count, 1)
        XCTAssertEqual(decoded.dataPoints.first?.utilization, 47)

        service = nil
    }

    private var corruptBackupURL: URL {
        historyURL.deletingPathExtension().appendingPathExtension("bak.json")
    }

    private func backupIfPresent(
        _ url: URL,
        assignTo keyPath: ReferenceWritableKeyPath<KimiHistoryServiceTests, URL?>
    ) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension.isEmpty ? "tmp" : url.pathExtension)
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.moveItem(at: url, to: backupURL)
        self[keyPath: keyPath] = backupURL
    }
}
