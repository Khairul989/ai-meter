import CryptoKit
import Foundation

enum ClaudeAnalyticsRange: String, CaseIterable {
    case sevenDay = "7D"
    case fourteenDay = "14D"
    case thirtyDay = "30D"
    case allTime = "All"

    func cutoffDate(relativeTo now: Date) -> Date? {
        switch self {
        case .sevenDay:
            return Calendar.current.date(byAdding: .day, value: -6, to: now)
        case .fourteenDay:
            return Calendar.current.date(byAdding: .day, value: -13, to: now)
        case .thirtyDay:
            return Calendar.current.date(byAdding: .day, value: -29, to: now)
        case .allTime:
            return nil
        }
    }
}

struct ClaudeAnalyticsBucket: Identifiable {
    let id: String
    let name: String
    let sessions: Int
    let assistantTurns: Int
    let userPrompts: Int
    let toolUseTurns: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreateTokens: Int

    var visibleTokens: Int { inputTokens + outputTokens }
}

struct ClaudeSessionRecord: Identifiable {
    let id: String
    let createdAt: Date
    let updatedAt: Date
    let cwd: String
    let gitBranch: String
    let version: String
    let entrypoint: String
    let title: String
    let firstPrompt: String
    let primaryModel: String
    let assistantTurns: Int
    let userPrompts: Int
    let toolUseTurns: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreateTokens: Int
    let webSearchRequests: Int
    let webFetchRequests: Int

    var visibleTokens: Int { inputTokens + outputTokens }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        let prompt = firstPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty {
            return "Untitled session"
        }
        return String(prompt.prefix(96))
    }

    var workspaceName: String {
        if cwd == "/" { return "Root" }
        if cwd == NSHomeDirectory() { return "~" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    var workspacePath: String {
        let home = NSHomeDirectory()
        if cwd.hasPrefix(home) {
            return "~" + String(cwd.dropFirst(home.count))
        }
        return cwd
    }

    var primaryModelDisplayName: String {
        ClaudeSessionStatsService.displayModelName(primaryModel)
    }

    var branchDisplayName: String {
        gitBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No branch" : gitBranch
    }

    var versionDisplayName: String {
        version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : version
    }
}

struct ClaudeAnalyticsDailyPoint: Identifiable {
    let date: Date
    let assistantTurns: Int
    let userPrompts: Int
    let toolUseTurns: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreateTokens: Int

    var id: Date { date }
    var visibleTokens: Int { inputTokens + outputTokens }
}

private struct ClaudeStatsSnapshot {
    let sessions: [ClaudeSessionAggregate]
    let daily: [String: ClaudeEventSlice]
    let dailyModels: [String: [String: ClaudeModelSlice]]
    let loadedAt: Date
}

private struct ClaudeSourceManifest {
    let sessionLogFiles: [URL]
    let sessionIndexFiles: [URL]
    let signature: String
}

private struct ClaudeSessionCache: Codable {
    let signature: String
    let sessions: [ClaudeSessionAggregate]
    let loadedAt: Date
}

private struct ClaudeIndexedSessionMetadata {
    let summary: String
    let firstPrompt: String
    let createdAt: Date?
    let updatedAt: Date?
    let gitBranch: String
    let projectPath: String
}

private struct ClaudeEventSlice: Codable {
    var assistantTurns = 0
    var userPrompts = 0
    var toolUseTurns = 0
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheCreateTokens = 0
    var webSearchRequests = 0
    var webFetchRequests = 0

    var visibleTokens: Int { inputTokens + outputTokens }

    mutating func merge(_ other: ClaudeEventSlice) {
        assistantTurns += other.assistantTurns
        userPrompts += other.userPrompts
        toolUseTurns += other.toolUseTurns
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheCreateTokens += other.cacheCreateTokens
        webSearchRequests += other.webSearchRequests
        webFetchRequests += other.webFetchRequests
    }
}

private struct ClaudeModelSlice: Codable {
    var assistantTurns = 0
    var toolUseTurns = 0
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheCreateTokens = 0

    var visibleTokens: Int { inputTokens + outputTokens }

    mutating func merge(_ other: ClaudeModelSlice) {
        assistantTurns += other.assistantTurns
        toolUseTurns += other.toolUseTurns
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheCreateTokens += other.cacheCreateTokens
    }
}

private struct ClaudeSessionAggregate: Codable {
    let id: String
    var cwd: String = ""
    var gitBranch: String = ""
    var version: String = ""
    var entrypoint: String = ""
    var summary: String = ""
    var firstPrompt: String = ""
    var createdAt: Date?
    var updatedAt: Date?
    var perDay: [String: ClaudeEventSlice] = [:]
    var modelsByDay: [String: [String: ClaudeModelSlice]] = [:]

    mutating func applyIndex(_ metadata: ClaudeIndexedSessionMetadata) {
        if summary.isEmpty {
            summary = metadata.summary
        }
        if firstPrompt.isEmpty {
            firstPrompt = metadata.firstPrompt
        }
        if cwd.isEmpty {
            cwd = metadata.projectPath
        }
        if gitBranch.isEmpty {
            gitBranch = metadata.gitBranch
        }
        if createdAt == nil {
            createdAt = metadata.createdAt
        }
        if updatedAt == nil {
            updatedAt = metadata.updatedAt
        }
    }

    func sliced(cutoffKey: String?) -> ClaudeSessionRecord? {
        let dayKeys = perDay.keys.filter { cutoffKey == nil || $0 >= cutoffKey! }
        guard !dayKeys.isEmpty else { return nil }

        var combined = ClaudeEventSlice()
        var modelTotals: [String: ClaudeModelSlice] = [:]

        for dayKey in dayKeys.sorted() {
            if let slice = perDay[dayKey] {
                combined.merge(slice)
            }
            if let dayModels = modelsByDay[dayKey] {
                for (model, slice) in dayModels {
                    var existing = modelTotals[model] ?? ClaudeModelSlice()
                    existing.merge(slice)
                    modelTotals[model] = existing
                }
            }
        }

        let primaryModel = modelTotals.max { lhs, rhs in
            if lhs.value.visibleTokens == rhs.value.visibleTokens {
                return lhs.value.assistantTurns < rhs.value.assistantTurns
            }
            return lhs.value.visibleTokens < rhs.value.visibleTokens
        }?.key ?? "claude-unknown"

        let sortedKeys = dayKeys.sorted()
        let createdAt = self.createdAt ?? ClaudeSessionStatsService.dateFromDayKey(sortedKeys.first ?? "") ?? .distantPast
        let updatedAt = self.updatedAt ?? ClaudeSessionStatsService.dateFromDayKey(sortedKeys.last ?? "") ?? createdAt

        return ClaudeSessionRecord(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            cwd: cwd.isEmpty ? "/" : cwd,
            gitBranch: gitBranch,
            version: version,
            entrypoint: entrypoint,
            title: summary,
            firstPrompt: firstPrompt,
            primaryModel: primaryModel,
            assistantTurns: combined.assistantTurns,
            userPrompts: combined.userPrompts,
            toolUseTurns: combined.toolUseTurns,
            inputTokens: combined.inputTokens,
            outputTokens: combined.outputTokens,
            cacheReadTokens: combined.cacheReadTokens,
            cacheCreateTokens: combined.cacheCreateTokens,
            webSearchRequests: combined.webSearchRequests,
            webFetchRequests: combined.webFetchRequests
        )
    }
}

@MainActor
final class ClaudeSessionStatsService: ObservableObject {
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var selectedRange: ClaudeAnalyticsRange = .fourteenDay
    @Published private(set) var lastLoadedAt: Date?
    @Published private(set) var hasLoaded = false

    private var allSessions: [ClaudeSessionAggregate] = []
    private var allDaily: [String: ClaudeEventSlice] = [:]
    private var allDailyModels: [String: [String: ClaudeModelSlice]] = [:]

    var sessions: [ClaudeSessionRecord] {
        let cutoffKey = cutoffDayKey
        return allSessions
            .compactMap { $0.sliced(cutoffKey: cutoffKey) }
            .sorted { lhs, rhs in
                if lhs.visibleTokens == rhs.visibleTokens {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.visibleTokens > rhs.visibleTokens
            }
    }

    var totalVisibleTokens: Int { sessions.reduce(0) { $0 + $1.visibleTokens } }
    var totalInputTokens: Int { sessions.reduce(0) { $0 + $1.inputTokens } }
    var totalOutputTokens: Int { sessions.reduce(0) { $0 + $1.outputTokens } }
    var totalCacheReadTokens: Int { sessions.reduce(0) { $0 + $1.cacheReadTokens } }
    var totalCacheCreateTokens: Int { sessions.reduce(0) { $0 + $1.cacheCreateTokens } }
    var totalAssistantTurns: Int { sessions.reduce(0) { $0 + $1.assistantTurns } }
    var totalUserPrompts: Int { sessions.reduce(0) { $0 + $1.userPrompts } }
    var totalToolUseTurns: Int { sessions.reduce(0) { $0 + $1.toolUseTurns } }
    var totalSessions: Int { sessions.count }

    var activeDays: Int {
        dailyPoints.filter { $0.assistantTurns > 0 || $0.userPrompts > 0 || $0.visibleTokens > 0 }.count
    }

    var cacheReadRatio: Int {
        guard totalVisibleTokens > 0 else { return 0 }
        return Int((Double(totalCacheReadTokens) / Double(totalVisibleTokens) * 100).rounded())
    }

    var toolUseRatio: Int {
        guard totalAssistantTurns > 0 else { return 0 }
        return Int((Double(totalToolUseTurns) / Double(totalAssistantTurns) * 100).rounded())
    }

    var averageAssistantTurnsPerSession: Int {
        guard totalSessions > 0 else { return 0 }
        return totalAssistantTurns / totalSessions
    }

    var topModel: ClaudeAnalyticsBucket? { models.first }
    var topWorkspace: ClaudeAnalyticsBucket? { workspaces.first }
    var topBranch: ClaudeAnalyticsBucket? { branches.first }
    var latestSession: ClaudeSessionRecord? { sessions.max(by: { $0.updatedAt < $1.updatedAt }) }

    var models: [ClaudeAnalyticsBucket] {
        guard !filteredDailyModels.isEmpty else { return [] }

        var grouped: [String: ClaudeAnalyticsBucket] = [:]
        var sessionSets: [String: Set<String>] = [:]

        for session in sessions {
            sessionSets[session.primaryModelDisplayName, default: []].insert(session.id)
        }

        for (_, dayModels) in filteredDailyModels {
            for (modelId, slice) in dayModels {
                let name = Self.displayModelName(modelId)
                let current = grouped[name] ?? ClaudeAnalyticsBucket(
                    id: name,
                    name: name,
                    sessions: 0,
                    assistantTurns: 0,
                    userPrompts: 0,
                    toolUseTurns: 0,
                    inputTokens: 0,
                    outputTokens: 0,
                    cacheReadTokens: 0,
                    cacheCreateTokens: 0
                )
                grouped[name] = ClaudeAnalyticsBucket(
                    id: name,
                    name: name,
                    sessions: current.sessions,
                    assistantTurns: current.assistantTurns + slice.assistantTurns,
                    userPrompts: current.userPrompts,
                    toolUseTurns: current.toolUseTurns + slice.toolUseTurns,
                    inputTokens: current.inputTokens + slice.inputTokens,
                    outputTokens: current.outputTokens + slice.outputTokens,
                    cacheReadTokens: current.cacheReadTokens + slice.cacheReadTokens,
                    cacheCreateTokens: current.cacheCreateTokens + slice.cacheCreateTokens
                )
            }
        }

        return grouped.values.map { bucket in
            ClaudeAnalyticsBucket(
                id: bucket.id,
                name: bucket.name,
                sessions: sessionSets[bucket.name]?.count ?? 0,
                assistantTurns: bucket.assistantTurns,
                userPrompts: bucket.userPrompts,
                toolUseTurns: bucket.toolUseTurns,
                inputTokens: bucket.inputTokens,
                outputTokens: bucket.outputTokens,
                cacheReadTokens: bucket.cacheReadTokens,
                cacheCreateTokens: bucket.cacheCreateTokens
            )
        }
        .sorted { lhs, rhs in
            if lhs.visibleTokens == rhs.visibleTokens {
                return lhs.assistantTurns > rhs.assistantTurns
            }
            return lhs.visibleTokens > rhs.visibleTokens
        }
    }

    var workspaces: [ClaudeAnalyticsBucket] {
        groupedSessionBuckets(for: sessions, key: \.workspacePath, name: \.workspaceName)
    }

    var branches: [ClaudeAnalyticsBucket] {
        groupedSessionBuckets(for: sessions, key: \.branchDisplayName, name: \.branchDisplayName)
    }

    var versions: [ClaudeAnalyticsBucket] {
        groupedSessionBuckets(for: sessions, key: \.versionDisplayName, name: \.versionDisplayName)
    }

    var topSessions: [ClaudeSessionRecord] {
        sessions
            .filter { $0.visibleTokens > 0 || $0.assistantTurns > 0 }
            .prefix(8)
            .map { $0 }
    }

    var dailyPoints: [ClaudeAnalyticsDailyPoint] {
        let calendar = Calendar.current
        let daily = filteredDaily
        guard !daily.isEmpty else { return [] }

        let startDate: Date
        if let cutoff = selectedRange.cutoffDate(relativeTo: Date()) {
            startDate = calendar.startOfDay(for: cutoff)
        } else {
            startDate = daily.keys.compactMap(Self.dateFromDayKey).min() ?? calendar.startOfDay(for: Date())
        }
        let endDate = calendar.startOfDay(for: Date())

        var cursor = startDate
        var result: [ClaudeAnalyticsDailyPoint] = []

        while cursor <= endDate {
            let key = Self.dayKey(for: cursor)
            let slice = daily[key] ?? ClaudeEventSlice()
            result.append(
                ClaudeAnalyticsDailyPoint(
                    date: cursor,
                    assistantTurns: slice.assistantTurns,
                    userPrompts: slice.userPrompts,
                    toolUseTurns: slice.toolUseTurns,
                    inputTokens: slice.inputTokens,
                    outputTokens: slice.outputTokens,
                    cacheReadTokens: slice.cacheReadTokens,
                    cacheCreateTokens: slice.cacheCreateTokens
                )
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return result
    }

    func load(force: Bool = false) async {
        if isLoading { return }
        if hasLoaded && !force { return }

        isLoading = true
        if force {
            loadError = nil
        }

        do {
            let snapshot = try await Task.detached(priority: .utility) {
                try Self.readSnapshot()
            }.value

            allSessions = snapshot.sessions
            allDaily = snapshot.daily
            allDailyModels = snapshot.dailyModels
            lastLoadedAt = snapshot.loadedAt
            hasLoaded = true
            loadError = nil
        } catch {
            if !hasLoaded {
                allSessions = []
                allDaily = [:]
                allDailyModels = [:]
            }
            loadError = error.localizedDescription
        }

        isLoading = false
    }

    func loadIfNeeded(maxAge: TimeInterval = 300) async {
        if let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < maxAge, hasLoaded {
            return
        }
        await load(force: true)
    }

    private var cutoffDayKey: String? {
        guard let cutoff = selectedRange.cutoffDate(relativeTo: Date()) else { return nil }
        return Self.dayKey(for: cutoff)
    }

    private var filteredDaily: [String: ClaudeEventSlice] {
        guard let cutoffKey = cutoffDayKey else { return allDaily }
        return allDaily.filter { $0.key >= cutoffKey }
    }

    private var filteredDailyModels: [String: [String: ClaudeModelSlice]] {
        guard let cutoffKey = cutoffDayKey else { return allDailyModels }
        return allDailyModels.filter { $0.key >= cutoffKey }
    }

    private func groupedSessionBuckets(
        for sessions: [ClaudeSessionRecord],
        key: KeyPath<ClaudeSessionRecord, String>,
        name: KeyPath<ClaudeSessionRecord, String>
    ) -> [ClaudeAnalyticsBucket] {
        let grouped = Dictionary(grouping: sessions) { $0[keyPath: key] }
        return grouped.map { _, records in
            ClaudeAnalyticsBucket(
                id: records[0][keyPath: key],
                name: records[0][keyPath: name],
                sessions: records.count,
                assistantTurns: records.reduce(0) { $0 + $1.assistantTurns },
                userPrompts: records.reduce(0) { $0 + $1.userPrompts },
                toolUseTurns: records.reduce(0) { $0 + $1.toolUseTurns },
                inputTokens: records.reduce(0) { $0 + $1.inputTokens },
                outputTokens: records.reduce(0) { $0 + $1.outputTokens },
                cacheReadTokens: records.reduce(0) { $0 + $1.cacheReadTokens },
                cacheCreateTokens: records.reduce(0) { $0 + $1.cacheCreateTokens }
            )
        }
        .sorted { lhs, rhs in
            if lhs.visibleTokens == rhs.visibleTokens {
                return lhs.sessions > rhs.sessions
            }
            return lhs.visibleTokens > rhs.visibleTokens
        }
    }

    nonisolated private static func readSnapshot() throws -> ClaudeStatsSnapshot {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw NSError(domain: "ClaudeSessionStatsService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not find ~/.claude/projects."
            ])
        }

        let manifest = try sourceManifest(in: root)
        if let cached = readCachedSnapshot(matching: manifest.signature) {
            return cached
        }

        let indexedSessions = readSessionIndexMetadata(from: manifest.sessionIndexFiles)
        let snapshot = try readProjectLogs(files: manifest.sessionLogFiles, indexedSessions: indexedSessions)
        let normalized = normalizedSnapshot(
            sessions: Array(snapshot.sessions.values),
            loadedAt: Date()
        )
        writeCachedSnapshot(
            ClaudeSessionCache(
                signature: manifest.signature,
                sessions: normalized.sessions,
                loadedAt: normalized.loadedAt
            )
        )
        return normalized
    }

    nonisolated private static func sourceManifest(in root: URL) throws -> ClaudeSourceManifest {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        let projectDirectories = entries
            .filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var sessionLogFiles: [URL] = []
        var sessionIndexFiles: [URL] = []
        var signatureParts: [String] = []

        for projectDirectory in projectDirectories {
            let projectEntries = try? FileManager.default.contentsOfDirectory(
                at: projectDirectory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )

            for entry in projectEntries ?? [] {
                let values = try? entry.resourceValues(forKeys: resourceKeys)
                let isDirectory = values?.isDirectory ?? false
                if isDirectory { continue }

                let relativePath = entry.path.replacingOccurrences(of: root.path + "/", with: "")
                let size = values?.fileSize ?? 0
                let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0

                if entry.lastPathComponent == "sessions-index.json" {
                    sessionIndexFiles.append(entry)
                    signatureParts.append("I|\(relativePath)|\(size)|\(modifiedAt)")
                    continue
                }

                guard entry.pathExtension == "jsonl",
                      !entry.lastPathComponent.hasSuffix(".jsonl.stopoffset")
                else { continue }

                sessionLogFiles.append(entry)
                signatureParts.append("L|\(relativePath)|\(size)|\(modifiedAt)")
            }
        }

        let signatureData = Data(signatureParts.sorted().joined(separator: "\n").utf8)
        let signature = SHA256.hash(data: signatureData).map { String(format: "%02x", $0) }.joined()

        return ClaudeSourceManifest(
            sessionLogFiles: sessionLogFiles.sorted { $0.path < $1.path },
            sessionIndexFiles: sessionIndexFiles.sorted { $0.path < $1.path },
            signature: signature
        )
    }

    nonisolated private static func readSessionIndexMetadata(from files: [URL]) -> [String: ClaudeIndexedSessionMetadata] {
        var result: [String: ClaudeIndexedSessionMetadata] = [:]
        for url in files {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["entries"] as? [[String: Any]]
            else {
                continue
            }

            for entry in entries {
                guard let sessionId = entry["sessionId"] as? String else { continue }
                let summary = entry["summary"] as? String ?? ""
                let firstPrompt = entry["firstPrompt"] as? String ?? ""
                let createdAt = isoDate(entry["created"] as? String)
                let updatedAt = isoDate(entry["modified"] as? String)
                let gitBranch = entry["gitBranch"] as? String ?? ""
                let projectPath = entry["projectPath"] as? String ?? ""
                result[sessionId] = ClaudeIndexedSessionMetadata(
                    summary: summary,
                    firstPrompt: firstPrompt,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    gitBranch: gitBranch,
                    projectPath: projectPath
                )
            }
        }
        return result
    }

    nonisolated private static func readProjectLogs(
        files: [URL],
        indexedSessions: [String: ClaudeIndexedSessionMetadata]
    ) throws -> (
        sessions: [String: ClaudeSessionAggregate],
        daily: [String: ClaudeEventSlice],
        dailyModels: [String: [String: ClaudeModelSlice]]
    ) {
        var sessions: [String: ClaudeSessionAggregate] = [:]
        var daily: [String: ClaudeEventSlice] = [:]
        var dailyModels: [String: [String: ClaudeModelSlice]] = [:]

        for url in files {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 100_000_000 {
                continue
            }

            let sessionFallbackID = url.deletingPathExtension().lastPathComponent
            guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { continue }

            for line in text.split(whereSeparator: \.isNewline) {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = obj["type"] as? String
                else { continue }

                let sessionId = obj["sessionId"] as? String ?? sessionFallbackID
                guard !sessionId.isEmpty else { continue }

                var aggregate = sessions[sessionId] ?? ClaudeSessionAggregate(id: sessionId)
                if let metadata = indexedSessions[sessionId] {
                    aggregate.applyIndex(metadata)
                }

                if let cwd = obj["cwd"] as? String, !cwd.isEmpty {
                    aggregate.cwd = cwd
                }
                if let gitBranch = obj["gitBranch"] as? String, !gitBranch.isEmpty {
                    aggregate.gitBranch = gitBranch
                }
                if let version = obj["version"] as? String, !version.isEmpty {
                    aggregate.version = version
                }
                if let entrypoint = obj["entrypoint"] as? String, !entrypoint.isEmpty {
                    aggregate.entrypoint = entrypoint
                }

                guard let timestamp = isoDate(obj["timestamp"] as? String) else {
                    sessions[sessionId] = aggregate
                    continue
                }
                let dayKey = dayKey(for: timestamp)

                if aggregate.createdAt == nil || timestamp < aggregate.createdAt! {
                    aggregate.createdAt = timestamp
                }
                if aggregate.updatedAt == nil || timestamp > aggregate.updatedAt! {
                    aggregate.updatedAt = timestamp
                }

                switch type {
                case "assistant":
                    guard let message = obj["message"] as? [String: Any],
                          let model = message["model"] as? String,
                          isClaudeModel(model)
                    else {
                        sessions[sessionId] = aggregate
                        continue
                    }

                    let usage = message["usage"] as? [String: Any] ?? [:]
                    let input = intValue(usage["input_tokens"])
                    let output = intValue(usage["output_tokens"])
                    let cacheRead = intValue(usage["cache_read_input_tokens"])
                    let cacheCreate = intValue(usage["cache_creation_input_tokens"])
                    let stopReason = message["stop_reason"] as? String ?? ""
                    let serverToolUse = usage["server_tool_use"] as? [String: Any] ?? [:]
                    let webSearch = intValue(serverToolUse["web_search_requests"])
                    let webFetch = intValue(serverToolUse["web_fetch_requests"])

                    var eventSlice = aggregate.perDay[dayKey] ?? ClaudeEventSlice()
                    eventSlice.assistantTurns += 1
                    eventSlice.inputTokens += input
                    eventSlice.outputTokens += output
                    eventSlice.cacheReadTokens += cacheRead
                    eventSlice.cacheCreateTokens += cacheCreate
                    eventSlice.webSearchRequests += webSearch
                    eventSlice.webFetchRequests += webFetch
                    if stopReason == "tool_use" {
                        eventSlice.toolUseTurns += 1
                    }
                    aggregate.perDay[dayKey] = eventSlice

                    var daySlice = daily[dayKey] ?? ClaudeEventSlice()
                    daySlice.assistantTurns += 1
                    daySlice.inputTokens += input
                    daySlice.outputTokens += output
                    daySlice.cacheReadTokens += cacheRead
                    daySlice.cacheCreateTokens += cacheCreate
                    daySlice.webSearchRequests += webSearch
                    daySlice.webFetchRequests += webFetch
                    if stopReason == "tool_use" {
                        daySlice.toolUseTurns += 1
                    }
                    daily[dayKey] = daySlice

                    let canonicalModel = ClaudeCodeStatsService.canonicalModelID(model)
                    var sessionDayModels = aggregate.modelsByDay[dayKey] ?? [:]
                    var modelSlice = sessionDayModels[canonicalModel] ?? ClaudeModelSlice()
                    modelSlice.assistantTurns += 1
                    modelSlice.inputTokens += input
                    modelSlice.outputTokens += output
                    modelSlice.cacheReadTokens += cacheRead
                    modelSlice.cacheCreateTokens += cacheCreate
                    if stopReason == "tool_use" {
                        modelSlice.toolUseTurns += 1
                    }
                    sessionDayModels[canonicalModel] = modelSlice
                    aggregate.modelsByDay[dayKey] = sessionDayModels

                    var globalDayModels = dailyModels[dayKey] ?? [:]
                    var globalSlice = globalDayModels[canonicalModel] ?? ClaudeModelSlice()
                    globalSlice.assistantTurns += 1
                    globalSlice.inputTokens += input
                    globalSlice.outputTokens += output
                    globalSlice.cacheReadTokens += cacheRead
                    globalSlice.cacheCreateTokens += cacheCreate
                    if stopReason == "tool_use" {
                        globalSlice.toolUseTurns += 1
                    }
                    globalDayModels[canonicalModel] = globalSlice
                    dailyModels[dayKey] = globalDayModels

                case "user":
                    var eventSlice = aggregate.perDay[dayKey] ?? ClaudeEventSlice()
                    eventSlice.userPrompts += 1
                    aggregate.perDay[dayKey] = eventSlice

                    var daySlice = daily[dayKey] ?? ClaudeEventSlice()
                    daySlice.userPrompts += 1
                    daily[dayKey] = daySlice

                    if aggregate.firstPrompt.isEmpty,
                       let prompt = extractUserPrompt(from: obj),
                       !prompt.isEmpty {
                        aggregate.firstPrompt = prompt
                    }

                default:
                    break
                }

                sessions[sessionId] = aggregate
            }
        }

        return (sessions, daily, dailyModels)
    }

    nonisolated private static func normalizedSnapshot(
        sessions: [ClaudeSessionAggregate],
        loadedAt: Date
    ) -> ClaudeStatsSnapshot {
        var daily: [String: ClaudeEventSlice] = [:]
        var dailyModels: [String: [String: ClaudeModelSlice]] = [:]

        for session in sessions {
            for (dayKey, slice) in session.perDay {
                var combined = daily[dayKey] ?? ClaudeEventSlice()
                combined.merge(slice)
                daily[dayKey] = combined
            }

            for (dayKey, modelMap) in session.modelsByDay {
                var combinedModels = dailyModels[dayKey] ?? [:]
                for (modelId, slice) in modelMap {
                    var combined = combinedModels[modelId] ?? ClaudeModelSlice()
                    combined.merge(slice)
                    combinedModels[modelId] = combined
                }
                dailyModels[dayKey] = combinedModels
            }
        }

        return ClaudeStatsSnapshot(
            sessions: sessions,
            daily: daily,
            dailyModels: dailyModels,
            loadedAt: loadedAt
        )
    }

    nonisolated private static func readCachedSnapshot(matching signature: String) -> ClaudeStatsSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL()),
              let cache = try? JSONDecoder().decode(ClaudeSessionCache.self, from: data),
              cache.signature == signature
        else {
            return nil
        }

        return normalizedSnapshot(sessions: cache.sessions, loadedAt: cache.loadedAt)
    }

    nonisolated private static func writeCachedSnapshot(_ cache: ClaudeSessionCache) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(cache) else { return }
        let url = cacheURL()
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    nonisolated private static func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("AIMeter", isDirectory: true)
            .appendingPathComponent("ClaudeAnalytics", isDirectory: true)
            .appendingPathComponent("session-stats-cache.json")
    }

    nonisolated private static func extractUserPrompt(from obj: [String: Any]) -> String? {
        if let content = obj["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }

        if let message = obj["message"] as? [String: Any] {
            if let content = message["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }

            if let parts = message["content"] as? [[String: Any]] {
                for part in parts {
                    if let text = part["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return text
                    }
                }
            }
        }

        return nil
    }

    nonisolated private static func isClaudeModel(_ model: String) -> Bool {
        model.lowercased().hasPrefix("claude-")
    }

    nonisolated private static func isoDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter.withFractionalSeconds.date(from: value)
            ?? ISO8601DateFormatter.internetDateTime.date(from: value)
    }

    nonisolated fileprivate static func dayKey(for date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    nonisolated fileprivate static func dateFromDayKey(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }

    nonisolated fileprivate static func displayModelName(_ modelId: String) -> String {
        let canonical = ClaudeCodeStatsService.canonicalModelID(modelId).replacingOccurrences(of: "claude-", with: "")
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

    nonisolated private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value) ?? 0
        default:
            return 0
        }
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
