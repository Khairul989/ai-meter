import Foundation
import SQLite3

enum CodexAnalyticsRange: String, CaseIterable {
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

struct CodexSessionRecord: Identifiable {
    let id: String
    let createdAt: Date
    let updatedAt: Date
    let cwd: String
    let title: String
    let source: String
    let modelProvider: String
    let model: String
    let reasoningEffort: String
    let tokensUsed: Int
    let promptCount: Int
    let archived: Bool

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled session" : trimmed
    }

    var workspaceName: String {
        if cwd == NSHomeDirectory() {
            return "~"
        }
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

    var modelDisplayName: String {
        let raw = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return modelProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Default Model" : modelProvider.uppercased()
        }

        return raw
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { part in
                if part.uppercased() == "GPT" || part.lowercased() == "codex" {
                    return part.uppercased()
                }
                if part.first?.isNumber == true {
                    return String(part)
                }
                return part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    var effortDisplayName: String {
        let trimmed = reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Standard"
        }
        return trimmed.capitalized
    }
}

struct CodexAnalyticsDailyPoint: Identifiable {
    let date: Date
    let sessions: Int
    let prompts: Int
    let tokens: Int

    var id: Date { date }
}

struct CodexAnalyticsBucket: Identifiable {
    let id: String
    let name: String
    let sessions: Int
    let prompts: Int
    let tokens: Int
}

private struct CodexHistoryLine: Decodable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

private struct CodexSessionSnapshot {
    let sessions: [CodexSessionRecord]
    let loadedAt: Date
}

@MainActor
final class CodexSessionStatsService: ObservableObject {
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var selectedRange: CodexAnalyticsRange = .fourteenDay
    @Published private(set) var lastLoadedAt: Date?
    @Published private(set) var hasLoaded = false

    private var allSessions: [CodexSessionRecord] = []
    private let fileManager = FileManager.default

    var sessions: [CodexSessionRecord] {
        let filtered = filteredSessions(now: Date())
        return filtered.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.tokensUsed > rhs.tokensUsed
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var totalTokens: Int {
        sessions.reduce(0) { $0 + $1.tokensUsed }
    }

    var totalPrompts: Int {
        sessions.reduce(0) { $0 + $1.promptCount }
    }

    var totalSessions: Int {
        sessions.count
    }

    var activeDays: Int {
        Set(sessions.map { Calendar.current.startOfDay(for: $0.createdAt) }).count
    }

    var averageTokensPerSession: Int {
        guard totalSessions > 0 else { return 0 }
        return totalTokens / totalSessions
    }

    var averagePromptsPerSession: Int {
        guard totalSessions > 0 else { return 0 }
        return totalPrompts / totalSessions
    }

    var models: [CodexAnalyticsBucket] {
        groupedBuckets(for: sessions, id: { $0.modelDisplayName }, name: { $0.modelDisplayName })
    }

    var workspaces: [CodexAnalyticsBucket] {
        groupedBuckets(for: sessions, id: { $0.workspacePath }, name: { $0.workspaceName })
    }

    var efforts: [CodexAnalyticsBucket] {
        groupedBuckets(for: sessions, id: { $0.effortDisplayName }, name: { $0.effortDisplayName })
    }

    var topSessions: [CodexSessionRecord] {
        sessions
            .filter { $0.tokensUsed > 0 || $0.promptCount > 0 }
            .sorted { lhs, rhs in
                if lhs.tokensUsed == rhs.tokensUsed {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.tokensUsed > rhs.tokensUsed
            }
            .prefix(8)
            .map { $0 }
    }

    var latestSession: CodexSessionRecord? {
        sessions.max(by: { $0.createdAt < $1.createdAt })
    }

    var topModel: CodexAnalyticsBucket? {
        models.first
    }

    var topWorkspace: CodexAnalyticsBucket? {
        workspaces.first
    }

    var dailyPoints: [CodexAnalyticsDailyPoint] {
        let filtered = sessions
        guard !filtered.isEmpty else { return [] }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.createdAt) }

        let startDate: Date
        if let cutoff = selectedRange.cutoffDate(relativeTo: Date()) {
            startDate = calendar.startOfDay(for: cutoff)
        } else {
            startDate = grouped.keys.min() ?? calendar.startOfDay(for: Date())
        }
        let endDate = calendar.startOfDay(for: Date())

        var cursor = startDate
        var result: [CodexAnalyticsDailyPoint] = []

        while cursor <= endDate {
            let entries = grouped[cursor] ?? []
            result.append(
                CodexAnalyticsDailyPoint(
                    date: cursor,
                    sessions: entries.count,
                    prompts: entries.reduce(0) { $0 + $1.promptCount },
                    tokens: entries.reduce(0) { $0 + $1.tokensUsed }
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
            lastLoadedAt = snapshot.loadedAt
            hasLoaded = true
            loadError = nil
        } catch {
            if !hasLoaded {
                allSessions = []
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

    private func filteredSessions(now: Date) -> [CodexSessionRecord] {
        guard let cutoff = selectedRange.cutoffDate(relativeTo: now) else {
            return allSessions
        }
        return allSessions.filter { $0.createdAt >= cutoff }
    }

    private func groupedBuckets(
        for sessions: [CodexSessionRecord],
        id: (CodexSessionRecord) -> String,
        name: (CodexSessionRecord) -> String
    ) -> [CodexAnalyticsBucket] {
        let grouped = Dictionary(grouping: sessions) { id($0) }

        return grouped.map { key, records in
            CodexAnalyticsBucket(
                id: key,
                name: name(records[0]),
                sessions: records.count,
                prompts: records.reduce(0) { $0 + $1.promptCount },
                tokens: records.reduce(0) { $0 + $1.tokensUsed }
            )
        }
        .sorted { lhs, rhs in
            if lhs.tokens == rhs.tokens {
                return lhs.sessions > rhs.sessions
            }
            return lhs.tokens > rhs.tokens
        }
    }

    nonisolated private static func readSnapshot() throws -> CodexSessionSnapshot {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        let dbURL = try resolveStateDatabaseURL(in: codexDir)
        let historyURL = codexDir.appendingPathComponent("history.jsonl")

        let promptCounts = readPromptCounts(from: historyURL)
        let sessions = try readSessions(from: dbURL, promptCounts: promptCounts)

        return CodexSessionSnapshot(sessions: sessions, loadedAt: Date())
    }

    nonisolated private static func resolveStateDatabaseURL(in codexDir: URL) throws -> URL {
        let candidate = codexDir.appendingPathComponent("state_5.sqlite")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: codexDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let dbs = urls.filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }

        guard let latest = dbs.max(by: { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }) else {
            throw NSError(domain: "CodexSessionStatsService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not find a Codex state database in ~/.codex."
            ])
        }

        return latest
    }

    nonisolated private static func readPromptCounts(from historyURL: URL) -> [String: Int] {
        guard let data = try? Data(contentsOf: historyURL), !data.isEmpty else {
            return [:]
        }

        let decoder = JSONDecoder()
        let text = String(decoding: data, as: UTF8.self)
        var counts: [String: Int] = [:]

        for line in text.split(whereSeparator: \.isNewline) {
            guard let jsonData = line.data(using: .utf8),
                  let item = try? decoder.decode(CodexHistoryLine.self, from: jsonData)
            else { continue }
            counts[item.sessionId, default: 0] += 1
        }

        return counts
    }

    nonisolated private static func readSessions(from dbURL: URL, promptCounts: [String: Int]) throws -> [CodexSessionRecord] {
        var db: OpaquePointer?
        let uri = "file:\(dbURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? dbURL.path)?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            defer { if db != nil { sqlite3_close(db) } }
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            throw NSError(domain: "CodexSessionStatsService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read Codex session database: \(message)"
            ])
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT
            id,
            COALESCE(cwd, ''),
            COALESCE(title, ''),
            COALESCE(source, ''),
            COALESCE(model_provider, ''),
            COALESCE(model, ''),
            COALESCE(reasoning_effort, ''),
            tokens_used,
            archived,
            COALESCE(created_at_ms, created_at * 1000),
            COALESCE(updated_at_ms, updated_at * 1000)
        FROM threads
        WHERE source = 'cli'
        ORDER BY COALESCE(created_at_ms, created_at * 1000) DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "CodexSessionStatsService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to prepare Codex session query: \(message)"
            ])
        }
        defer { sqlite3_finalize(statement) }

        var sessions: [CodexSessionRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = stringColumn(statement, index: 0)
            let cwd = stringColumn(statement, index: 1)
            let title = stringColumn(statement, index: 2)
            let source = stringColumn(statement, index: 3)
            let provider = stringColumn(statement, index: 4)
            let model = stringColumn(statement, index: 5)
            let effort = stringColumn(statement, index: 6)
            let tokens = Int(sqlite3_column_int64(statement, 7))
            let archived = sqlite3_column_int(statement, 8) != 0
            let createdAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 9)) / 1000.0)
            let updatedAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 10)) / 1000.0)

            sessions.append(
                CodexSessionRecord(
                    id: id,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    cwd: cwd,
                    title: title,
                    source: source,
                    modelProvider: provider,
                    model: model,
                    reasoningEffort: effort,
                    tokensUsed: tokens,
                    promptCount: promptCounts[id, default: 0],
                    archived: archived
                )
            )
        }

        return sessions
    }

    nonisolated private static func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }
}
