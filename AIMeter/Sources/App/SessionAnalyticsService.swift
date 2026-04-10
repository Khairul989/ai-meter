import Combine
import Foundation
import SwiftUI

@MainActor
final class SessionAnalyticsService: ObservableObject {
    @Published var result: AnalyticsResult?
    @Published var isLoading: Bool = false
    @Published var filter: AnalyticsFilter = AnalyticsFilter()
    @Published var availableProjects: [String] = []

    private var loadGeneration: Int = 0

    func load() {
        let filter = self.filter
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true

        Task.detached(priority: .userInitiated) { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let data = try Self.runBinary(filter: filter)
                let decoded = try Self.decode(data: data)
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                print("[Analytics] parsed in \(String(format: "%.2f", elapsed))s — \(decoded.grandTotals.projectCount) projects")
                await MainActor.run { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    self.result = decoded
                    self.availableProjects = decoded.availableProjects
                    self.isLoading = false
                }
            } catch {
                print("[Analytics] error: \(error)")
                await MainActor.run { [weak self] in
                    guard let self, self.loadGeneration == generation else { return }
                    self.isLoading = false
                }
            }
        }
    }

    /// Pre-warm the PyInstaller binary so subsequent calls skip cold-start extraction.
    static func warmUp() {
        Task.detached(priority: .background) {
            guard let binaryPath = binaryPath() else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["--json"]
            // Run with very recent date to minimize work, just enough to trigger extraction
            let tomorrow = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400)).prefix(10)
            process.environment = ProcessInfo.processInfo.environment.merging([
                "SINCE_DATE": String(tomorrow),
                "UNTIL_DATE": String(tomorrow),
            ]) { $1 }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }
}

private extension SessionAnalyticsService {

    nonisolated static func binaryPath() -> String? {
        // Try subdirectory first (folder reference), then flat (XcodeGen may flatten)
        if let p = Bundle.main.path(forResource: "token_analyzer", ofType: nil, inDirectory: "bin") { return p }
        if let p = Bundle.main.path(forResource: "token_analyzer", ofType: nil) { return p }
        // Explicit paths as last resort
        let candidates = [
            Bundle.main.bundlePath + "/Contents/Resources/bin/token_analyzer",
            Bundle.main.bundlePath + "/Contents/Resources/token_analyzer",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    nonisolated static func runBinary(filter: AnalyticsFilter) throws -> Data {
        guard let binaryPath = binaryPath() else {
            print("[Analytics] binaryNotFound — bundle: \(Bundle.main.bundlePath)")
            throw AnalyticsError.binaryNotFound
        }
        print("[Analytics] using binary at: \(binaryPath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--json"]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current

        var env = ProcessInfo.processInfo.environment
        if let since = filter.since {
            env["SINCE_DATE"] = dateFormatter.string(from: since)
        }
        if let until = filter.until {
            env["UNTIL_DATE"] = dateFormatter.string(from: until)
        }
        if !filter.projectNames.isEmpty {
            env["PROJECT_FILTER"] = filter.projectNames.joined(separator: ",")
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "unknown"
            throw AnalyticsError.processFailed(errStr)
        }
        return data
    }

    nonisolated static func decode(data: Data) throws -> AnalyticsResult {
        let decoder = JSONDecoder()
        return try decoder.decode(AnalyticsResult.self, from: data)
    }
}

enum AnalyticsError: Error {
    case binaryNotFound
    case processFailed(String)
}
