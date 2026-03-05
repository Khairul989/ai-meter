import Foundation

struct ModelTokenUsage: Identifiable, Equatable {
    let id: String
    let displayName: String
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }

    /// Color index: 0=orange (opus), 1=blue (sonnet), 2=green (haiku)
    var colorIndex: Int {
        let lower = displayName.lowercased()
        if lower.contains("opus") { return 0 }
        if lower.contains("sonnet") { return 1 }
        if lower.contains("haiku") { return 2 }
        return 3
    }
}

enum ModelTimeRange: String, CaseIterable {
    case today = "Today"
    case sevenDay = "7D"
    case thirtyDay = "30D"
    case allTime = "All"
}

struct DailyTrendPoint: Identifiable {
    let id: String // date string
    let date: Date
    let messages: Int
    let tokens: Int
}

enum TrendRange: String, CaseIterable {
    case sevenDay = "7D"
    case fourteenDay = "14D"
    case thirtyDay = "30D"
}

/// Latest Claude models to show (others are legacy/deprecated)
private let latestModels: Set<String> = [
    "claude-opus-4-6",
    "claude-sonnet-4-6",
    "claude-haiku-4-5-20251001"
]

@MainActor
final class ClaudeCodeStatsService: ObservableObject {
    @Published var models: [ModelTokenUsage] = []
    @Published var totalTokens: Int = 0
    @Published var isLoading = true
    @Published var selectedRange: ModelTimeRange = .today {
        didSet { applyRange() }
    }

    // Trend data
    @Published var trendPoints: [DailyTrendPoint] = []
    @Published var trendRange: TrendRange = .fourteenDay {
        didSet { applyTrend() }
    }

    private var timer: Timer?
    // Cached daily entries: [date_string: [modelId: (in, out)]]
    private var dailyCache: [String: [String: (input: Int, output: Int)]] = [:]
    // Cached daily message counts: [date_string: messageCount]
    private var dailyMessageCache: [String: Int] = [:]
    // All-time from stats-cache.json
    private var allTimeModels: [String: (input: Int, output: Int)] = [:]
    // Track last parse time for incremental updates
    private var lastParseDate: Date?
    private var isParsing = false

    private static var statsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/stats-cache.json")
    }

    private static var projectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    private static var dailyCacheFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aimeter/daily-token-cache.json")
    }

    func start(interval: TimeInterval = 60) {
        load()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func load() {
        loadAllTime()
        loadDiskCache()
        applyRange()

        guard !isParsing else { return }
        isParsing = true
        let since = lastParseDate
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.parseJSONLFiles(since: since)
            await MainActor.run {
                guard let self else { return }
                // Merge token data
                for (date, models) in result.tokens {
                    var dayEntry = self.dailyCache[date] ?? [:]
                    if since != nil {
                        for (model, tokens) in models {
                            let existing = dayEntry[model] ?? (0, 0)
                            dayEntry[model] = (existing.input + tokens.input, existing.output + tokens.output)
                        }
                    } else {
                        dayEntry = models
                    }
                    self.dailyCache[date] = dayEntry
                }
                // Merge message counts
                for (date, count) in result.messages {
                    if since != nil {
                        self.dailyMessageCache[date, default: 0] += count
                    } else {
                        self.dailyMessageCache[date] = count
                    }
                }
                self.lastParseDate = Date()
                self.isLoading = false
                self.isParsing = false
                self.applyRange()
                self.applyTrend()
                self.saveDiskCache()
            }
        }
    }

    // MARK: - Disk cache for instant startup

    private func loadDiskCache() {
        guard dailyCache.isEmpty,
              let data = try? Data(contentsOf: Self.dailyCacheFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = json["daily"] as? [String: [String: [String: Int]]] else {
            return
        }

        var result: [String: [String: (input: Int, output: Int)]] = [:]
        for (date, models) in daily {
            var dayEntry: [String: (input: Int, output: Int)] = [:]
            for (model, tokens) in models {
                let input = tokens["i"] ?? 0
                let output = tokens["o"] ?? 0
                if input + output > 0 { dayEntry[model] = (input, output) }
            }
            if !dayEntry.isEmpty { result[date] = dayEntry }
        }
        dailyCache = result

        // Load message counts
        if let msgs = json["messages"] as? [String: Int] {
            dailyMessageCache = msgs
        }

        if !result.isEmpty { isLoading = false }
    }

    private func saveDiskCache() {
        var daily: [String: [String: [String: Int]]] = [:]
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        let cutoffKey = formatter.string(from: cutoffDate)
        for (date, models) in dailyCache where date >= cutoffKey {
            var dayEntry: [String: [String: Int]] = [:]
            for (model, tokens) in models {
                dayEntry[model] = ["i": tokens.input, "o": tokens.output]
            }
            daily[date] = dayEntry
        }

        // Filter message cache too
        var msgs: [String: Int] = [:]
        for (date, count) in dailyMessageCache where date >= cutoffKey {
            msgs[date] = count
        }

        let json: [String: Any] = ["daily": daily, "messages": msgs]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }

        let dir = Self.dailyCacheFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: Self.dailyCacheFile, options: .atomic)
    }

    // MARK: - All-time from stats-cache.json

    private func loadAllTime() {
        guard let data = try? Data(contentsOf: Self.statsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelUsage = json["modelUsage"] as? [String: [String: Any]] else {
            return
        }

        var result: [String: (input: Int, output: Int)] = [:]
        for (modelId, stats) in modelUsage {
            guard latestModels.contains(modelId) else { continue }
            let input = stats["inputTokens"] as? Int ?? 0
            let output = stats["outputTokens"] as? Int ?? 0
            guard input + output > 0 else { continue }
            result[modelId] = (input, output)
        }
        allTimeModels = result
    }

    // MARK: - JSONL parsing (background)

    struct ParseResult: Sendable {
        let tokens: [String: [String: (input: Int, output: Int)]]
        let messages: [String: Int]
    }

    /// Parse JSONL files. If `since` is provided, only parse files modified after that date (incremental).
    private nonisolated static func parseJSONLFiles(since: Date? = nil) -> ParseResult {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return ParseResult(tokens: [:], messages: [:]) }

        let cutoff = since ?? Date().addingTimeInterval(-31 * 86400)

        var daily: [String: [String: (input: Int, output: Int)]] = [:]
        var dailyMessages: [String: Int] = [:]
        let assistantMarker = Data("\"type\":\"assistant\"".utf8)

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }

            if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modDate < cutoff {
                continue
            }

            guard let fileData = try? Data(contentsOf: url) else { continue }

            fileData.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                let length = buffer.count
                var lineStart = 0

                for i in 0..<length {
                    guard base[i] == UInt8(ascii: "\n") || i == length - 1 else { continue }
                    let lineEnd = (i == length - 1 && base[i] != UInt8(ascii: "\n")) ? i + 1 : i
                    let lineData = Data(bytes: base + lineStart, count: lineEnd - lineStart)
                    lineStart = i + 1

                    guard lineData.count > 50,
                          lineData.range(of: assistantMarker) != nil else { continue }

                    guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                          obj["type"] as? String == "assistant",
                          let msg = obj["message"] as? [String: Any],
                          let model = msg["model"] as? String,
                          latestModels.contains(model),
                          let usage = msg["usage"] as? [String: Any] else { continue }

                    let input = usage["input_tokens"] as? Int ?? 0
                    let output = usage["output_tokens"] as? Int ?? 0
                    guard input + output > 0 else { continue }

                    let timestamp = obj["timestamp"] as? String ?? ""
                    let dateKey = String(timestamp.prefix(10))
                    guard dateKey.count == 10 else { continue }

                    var dayEntry = daily[dateKey] ?? [:]
                    let existing = dayEntry[model] ?? (0, 0)
                    dayEntry[model] = (existing.input + input, existing.output + output)
                    daily[dateKey] = dayEntry

                    dailyMessages[dateKey, default: 0] += 1
                }
            }
        }

        return ParseResult(tokens: daily, messages: dailyMessages)
    }

    // MARK: - Apply range filter

    private func applyRange() {
        let aggregated: [String: (input: Int, output: Int)]

        if selectedRange == .allTime {
            aggregated = allTimeModels
        } else {
            let days: Int
            switch selectedRange {
            case .today: days = 0
            case .sevenDay: days = 6
            case .thirtyDay: days = 29
            case .allTime: days = 0
            }

            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current

            var merged: [String: (input: Int, output: Int)] = [:]
            for dayOffset in 0...days {
                let date = cal.date(byAdding: .day, value: -dayOffset, to: today)!
                let key = formatter.string(from: date)
                guard let dayData = dailyCache[key] else { continue }
                for (model, tokens) in dayData {
                    let existing = merged[model] ?? (0, 0)
                    merged[model] = (existing.input + tokens.input, existing.output + tokens.output)
                }
            }
            aggregated = merged
        }

        var parsed: [ModelTokenUsage] = []
        for (modelId, tokens) in aggregated {
            guard tokens.input + tokens.output > 0 else { continue }
            parsed.append(ModelTokenUsage(
                id: modelId,
                displayName: Self.shortName(modelId),
                inputTokens: tokens.input,
                outputTokens: tokens.output
            ))
        }

        models = parsed.sorted { $0.totalTokens > $1.totalTokens }
        totalTokens = models.reduce(0) { $0 + $1.totalTokens }
    }

    // MARK: - Trend

    private func applyTrend() {
        let days: Int
        switch trendRange {
        case .sevenDay: days = 6
        case .fourteenDay: days = 13
        case .thirtyDay: days = 29
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        var points: [DailyTrendPoint] = []
        for dayOffset in (0...days).reversed() {
            let date = cal.date(byAdding: .day, value: -dayOffset, to: today)!
            let key = formatter.string(from: date)
            let msgs = dailyMessageCache[key] ?? 0
            let tokens: Int
            if let dayData = dailyCache[key] {
                tokens = dayData.values.reduce(0) { $0 + $1.input + $1.output }
            } else {
                tokens = 0
            }
            points.append(DailyTrendPoint(id: key, date: date, messages: msgs, tokens: tokens))
        }
        trendPoints = points
    }

    /// "claude-sonnet-4-6" → "sonnet-4-6", "claude-haiku-4-5-20251001" → "haiku-4-5"
    static func shortName(_ modelId: String) -> String {
        var name = modelId.replacingOccurrences(of: "claude-", with: "")
        // Remove date suffixes: "-20251001"
        if let range = name.range(of: #"-\d{8}$"#, options: .regularExpression) {
            name = String(name[name.startIndex..<range.lowerBound])
        }
        return name
    }
}
