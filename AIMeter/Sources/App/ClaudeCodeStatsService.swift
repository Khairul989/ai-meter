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

@MainActor
final class ClaudeCodeStatsService: PollingServiceBase {
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

    private static var dailyCacheFile: URL {
        AppConstants.Paths.tokenCacheFile
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private static let utcDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    override func start(interval: TimeInterval = 60) {
        load()
        super.start(interval: interval)
    }

    override func tick() async {
        load()
    }

    func load() {
        loadDiskCache()
        loadAllTime()
        mergeRecentModelsIntoAllTime()
        applyRange()
        applyTrend()

        guard !isParsing else { return }
        isParsing = true
        let since = lastParseDate
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.parseJSONLFiles(since: since)
            await MainActor.run { [weak self] in
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
                self.mergeRecentModelsIntoAllTime()
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
        let formatter = Self.utcDayFormatter

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
            guard Self.isClaudeModel(modelId) else { continue }
            let input = stats["inputTokens"] as? Int ?? 0
            let output = stats["outputTokens"] as? Int ?? 0
            guard input + output > 0 else { continue }
            let canonicalModelId = Self.canonicalModelID(modelId)
            let existing = result[canonicalModelId] ?? (0, 0)
            result[canonicalModelId] = (
                existing.input + input,
                existing.output + output
            )
        }
        allTimeModels = result
    }

    /// `stats-cache.json` can lag behind newly launched model IDs.
    /// When that happens, keep recent parsed usage for unseen models so "All"
    /// still shows them instead of dropping the family entirely.
    private func mergeRecentModelsIntoAllTime() {
        guard !dailyCache.isEmpty else { return }

        var merged = allTimeModels
        var missingRecentModels: [String: (input: Int, output: Int)] = [:]

        for dayModels in dailyCache.values {
            for (modelId, tokens) in dayModels {
                guard Self.isClaudeModel(modelId) else { continue }
                let canonicalModelId = Self.canonicalModelID(modelId)
                guard merged[canonicalModelId] == nil else { continue }
                let existing = missingRecentModels[canonicalModelId] ?? (0, 0)
                missingRecentModels[canonicalModelId] = (
                    existing.input + tokens.input,
                    existing.output + tokens.output
                )
            }
        }

        for (modelId, tokens) in missingRecentModels where tokens.input + tokens.output > 0 {
            merged[modelId] = tokens
        }

        allTimeModels = merged
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

        // Use local timezone formatter so date keys match applyTrend()/applyRange()
        let localDayFmt = DateFormatter()
        localDayFmt.dateFormat = "yyyy-MM-dd"
        localDayFmt.timeZone = .current

        let isoParser = ISO8601DateFormatter()

        var daily: [String: [String: (input: Int, output: Int)]] = [:]
        var dailyMessages: [String: Int] = [:]
        let assistantMarker = Data("\"type\":\"assistant\"".utf8)

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }

            if let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modDate < cutoff {
                continue
            }

            guard let fileData = try? Data(contentsOf: url),
                  fileData.count < 100_000_000 else { continue } // Skip files > 100MB

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
                          Self.isClaudeModel(model),
                          let usage = msg["usage"] as? [String: Any] else { continue }

                    let input = usage["input_tokens"] as? Int ?? 0
                    let output = usage["output_tokens"] as? Int ?? 0
                    guard input + output > 0 else { continue }

                    let timestamp = obj["timestamp"] as? String ?? ""
                    // Parse ISO8601 timestamp and format in local timezone to match applyTrend()
                    let dateKey: String
                    if let ts = isoParser.date(from: timestamp) {
                        dateKey = localDayFmt.string(from: ts)
                    } else {
                        let fallback = String(timestamp.prefix(10))
                        guard fallback.count == 10 else { lineStart = i + 1; continue }
                        dateKey = fallback
                    }

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
            let formatter = Self.dayFormatter

            var merged: [String: (input: Int, output: Int)] = [:]
            for dayOffset in 0...days {
                let date = cal.date(byAdding: .day, value: -dayOffset, to: today)!
                let key = formatter.string(from: date)
                guard let dayData = dailyCache[key] else { continue }
                for (model, tokens) in dayData {
                    let canonicalModelId = Self.canonicalModelID(model)
                    let existing = merged[canonicalModelId] ?? (0, 0)
                    merged[canonicalModelId] = (
                        existing.input + tokens.input,
                        existing.output + tokens.output
                    )
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
        let formatter = Self.dayFormatter

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

    /// "claude-sonnet-4-6" → "Sonnet 4.6", "claude-haiku-4-5-20251001" → "Haiku 4.5"
    static func shortName(_ modelId: String) -> String {
        let canonical = canonicalModelID(modelId).replacingOccurrences(of: "claude-", with: "")
        let parts = canonical.split(separator: "-").map(String.init)
        guard let family = parts.first, !family.isEmpty else { return canonical }

        var index = 1
        var versionParts: [String] = []
        while index < parts.count, parts[index].allSatisfy(\.isNumber) {
            versionParts.append(parts[index])
            index += 1
        }

        let familyLabel = family.prefix(1).uppercased() + family.dropFirst()
        let versionLabel = versionParts.isEmpty ? nil : versionParts.joined(separator: ".")
        let suffixLabel = parts[index...]
            .map { $0.replacingOccurrences(of: "_", with: " ") }
            .map { part in
                part.split(separator: " ").map { word in
                    word.prefix(1).uppercased() + word.dropFirst()
                }.joined(separator: " ")
            }
            .joined(separator: " ")

        return [familyLabel, versionLabel, suffixLabel.isEmpty ? nil : suffixLabel]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Accept any Claude model emitted by Claude Code instead of pinning known IDs.
    nonisolated static func isClaudeModel(_ modelId: String) -> Bool {
        modelId.lowercased().hasPrefix("claude-")
    }

    /// Normalize raw model IDs into stable keys so dated snapshots aggregate together.
    /// Examples:
    /// - "claude-haiku-4-5-20251001" -> "claude-haiku-4-5"
    /// - "claude-3-7-sonnet-20250219" -> "claude-sonnet-3-7"
    nonisolated static func canonicalModelID(_ modelId: String) -> String {
        var normalized = modelId.lowercased()
        if normalized.hasPrefix("claude-") {
            normalized.removeFirst("claude-".count)
        }

        if let range = normalized.range(of: #"-\d{8}$"#, options: .regularExpression) {
            normalized = String(normalized[..<range.lowerBound])
        }

        if let match = normalized.range(
            of: #"^(\d+(?:-\d+)*)-(opus|sonnet|haiku)(-.+)?$"#,
            options: .regularExpression
        ) {
            let body = String(normalized[match])
            let pattern = try? NSRegularExpression(
                pattern: #"^(\d+(?:-\d+)*)-(opus|sonnet|haiku)(-.+)?$"#
            )
            let fullRange = NSRange(body.startIndex..<body.endIndex, in: body)
            if let regex = pattern,
               let result = regex.firstMatch(in: body, options: [], range: fullRange),
               let versionRange = Range(result.range(at: 1), in: body),
               let familyRange = Range(result.range(at: 2), in: body) {
                let version = body[versionRange]
                let family = body[familyRange]
                let suffix: String
                if let suffixRange = Range(result.range(at: 3), in: body) {
                    suffix = String(body[suffixRange])
                } else {
                    suffix = ""
                }
                normalized = "\(family)-\(version)\(suffix)"
            }
        }

        return "claude-\(normalized)"
    }
}
