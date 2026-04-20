import Combine
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import OSLog

private final class ClaudeCompatDiagnostics {
    static let shared = ClaudeCompatDiagnostics()

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let logger = Logger(subsystem: AppConstants.bundleId, category: "ClaudeCompatProxy")
    private let queue = DispatchQueue(label: "com.khairul.aimeter.claude-compat-proxy.log")
    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private lazy var fileURL: URL = {
        let logsDir = AppConstants.Paths.configDir.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("claude-compat-proxy.log")
    }()

    private lazy var failedRequestURL: URL = {
        let logsDir = AppConstants.Paths.configDir.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("claude-compat-proxy-last-failed-request.json")
    }()

    func debug(_ message: String, requestID: String? = nil, metadata: [String: Any?] = [:]) {
        log(.debug, message, requestID: requestID, metadata: metadata)
    }

    func info(_ message: String, requestID: String? = nil, metadata: [String: Any?] = [:]) {
        log(.info, message, requestID: requestID, metadata: metadata)
    }

    func warning(_ message: String, requestID: String? = nil, metadata: [String: Any?] = [:]) {
        log(.warning, message, requestID: requestID, metadata: metadata)
    }

    func error(_ message: String, requestID: String? = nil, metadata: [String: Any?] = [:]) {
        log(.error, message, requestID: requestID, metadata: metadata)
    }

    func saveFailedRequestBody(_ body: Data) {
        queue.async { [failedRequestURL] in
            try? body.write(to: failedRequestURL, options: .atomic)
        }
    }

    private func log(_ level: Level, _ message: String, requestID: String?, metadata: [String: Any?]) {
        let cleanedMetadata = metadata
            .compactMapValues { value -> String? in
                guard let value else { return nil }
                let string = String(describing: value)
                return string.isEmpty ? nil : string
            }
        let metadataString = cleanedMetadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let prefix = requestID.map { "[\($0)] " } ?? ""
        let line = "\(iso8601.string(from: Date())) [\(level.rawValue)] \(prefix)\(message)\(metadataString.isEmpty ? "" : " | \(metadataString)")"

        switch level {
        case .debug:
            logger.debug("\(line, privacy: .public)")
        case .info:
            logger.info("\(line, privacy: .public)")
        case .warning:
            logger.warning("\(line, privacy: .public)")
        case .error:
            logger.error("\(line, privacy: .public)")
        }

        queue.async { [fileURL] in
            let data = Data((line + "\n").utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    return
                }
            }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

private struct ClaudeCompatAccountContext {
    let accountId: String
    let chatGPTAccountId: String
    let accessToken: String
}

private struct ClaudeCompatProxyResponse {
    let statusCode: Int
    let reasonPhrase: String
    let headers: [(String, String)]
    let body: Data
}

private struct ClaudeCompatSSEStream {
    let statusCode: Int
    let reasonPhrase: String
    let headers: [(String, String)]
    let relay: (@escaping (Data) -> Void) async throws -> Void
}

private enum ClaudeCompatInboundResult {
    case response(ClaudeCompatProxyResponse)
    case stream(ClaudeCompatSSEStream)
}

private enum ClaudeCompatProxyError: Error {
    case invalidPath
    case invalidJSON
    case invalidResponse
    case missingActiveAccount
    case modelNotAllowed(String)
}

private struct ClaudeCompatUpstreamError: Error {
    let statusCode: Int
    let message: String
    let retryAfter: String?
}

private struct ClaudeCompatUpstreamStreamError: Error {
    enum Kind {
        case rateLimit
        case failed
    }

    let kind: Kind
    let message: String
    let retryAfterSeconds: Int?
}

private struct ClaudeCompatEarlyFinish: Error {
    let stopReason: String
    let usage: ClaudeCompatCodexUsage?
}

private struct ClaudeCompatIDTokenClaims: Decodable {
    let chatGPTAccountID: String?

    enum CodingKeys: String, CodingKey {
        case chatGPTAccountID = "chatgpt_account_id"
    }
}

private struct ClaudeCompatModelPolicy {
    private static let allowed: Set<String> = [
        "gpt-5.2",
        "gpt-5.3-codex",
        "gpt-5.4",
        "gpt-5.4-mini"
    ]

    private static let aliases: [String: String] = [
        "haiku": "gpt-5.4-mini",
        "claude-haiku-4-5": "gpt-5.4-mini",
        "claude-haiku-4-5-20251001": "gpt-5.4-mini",
        "sonnet": "gpt-5.4",
        "claude-sonnet-4-6": "gpt-5.4",
        "claude-sonnet-4-7": "gpt-5.4",
        "opus": "gpt-5.4",
        "claude-opus-4-6": "gpt-5.4",
        "claude-opus-4-7": "gpt-5.4"
    ]

    static func resolve(_ model: String) -> String {
        aliases[model] ?? model
    }

    static func validate(_ model: String) throws {
        guard allowed.contains(model) else {
            throw ClaudeCompatProxyError.modelNotAllowed(model)
        }
    }
}

private enum URIPathParser {
    static func path(from uri: String) -> String {
        guard let questionMarkIndex = uri.firstIndex(of: "?") else {
            return uri
        }
        return String(uri[..<questionMarkIndex])
    }
}

private struct ClaudeCompatAnthropicRequest: Decodable {
    let model: String
    let messages: [Message]
    let system: SystemPrompt?
    let tools: [Tool]?
    let toolChoice: ToolChoice?
    let stream: Bool?
    let outputConfig: OutputConfig?

    struct Message: Decodable {
        let role: String
        let content: Content
    }

    enum Content: Decodable {
        case string(String)
        case blocks([Block])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
                return
            }
            self = .blocks(try container.decode([Block].self))
        }

        var blocks: [Block] {
            switch self {
            case .string(let text):
                return [Block(type: "text", text: text, source: nil, id: nil, name: nil, input: nil, toolUseId: nil, content: nil, isError: nil)]
            case .blocks(let blocks):
                return blocks
            }
        }
    }

    struct Block: Decodable {
        let type: String
        let text: String?
        let source: ImageSource?
        let id: String?
        let name: String?
        let input: JSONValue?
        let toolUseId: String?
        let content: ToolResultContent?
        let isError: Bool?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case source
            case id
            case name
            case input
            case toolUseId = "tool_use_id"
            case content
            case isError = "is_error"
        }
    }

    struct ImageSource: Decodable {
        let type: String
        let mediaType: String?
        let data: String?
        let url: String?

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
            case url
        }
    }

    enum SystemPrompt: Decodable {
        case string(String)
        case blocks([TextBlock])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
                return
            }
            self = .blocks(try container.decode([TextBlock].self))
        }

        var text: String? {
            switch self {
            case .string(let value):
                return value
            case .blocks(let blocks):
                let joined = blocks
                    .filter { $0.type == "text" }
                    .compactMap(\.text)
                    .filter { !$0.hasPrefix("x-anthropic-billing-header:") }
                    .joined(separator: "\n\n")
                return joined.isEmpty ? nil : joined
            }
        }
    }

    struct TextBlock: Decodable {
        let type: String
        let text: String?
    }

    struct Tool: Decodable {
        let name: String
        let description: String?
        let inputSchema: JSONValue

        enum CodingKeys: String, CodingKey {
            case name
            case description
            case inputSchema = "input_schema"
        }
    }

    struct ToolChoice: Decodable {
        let type: String
        let name: String?
    }

    struct OutputConfig: Decodable {
        let effort: String?
        let format: OutputFormat?
    }

    struct OutputFormat: Decodable {
        let type: String
        let schema: JSONValue?
        let name: String?
        let strict: Bool?
    }

    enum ToolResultContent: Decodable {
        case string(String)
        case blocks([Block])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
                return
            }
            self = .blocks(try container.decode([Block].self))
        }
    }
}

private struct ClaudeCompatResponsesRequest: Encodable {
    struct InputItem: Encodable {
        let type: String
        let role: String?
        let content: [ContentPart]?
        let callId: String?
        let name: String?
        let arguments: String?
        let output: String?

        enum CodingKeys: String, CodingKey {
            case type
            case role
            case content
            case callId = "call_id"
            case name
            case arguments
            case output
        }
    }

    struct ContentPart: Encodable {
        let type: String
        let text: String?
        let imageURL: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }
    }

    struct Tool: Encodable {
        let type: String
        let name: String
        let description: String?
        let parameters: JSONValue
    }

    struct FunctionToolChoice: Encodable {
        let type: String
        let name: String
    }

    struct Reasoning: Encodable {
        let effort: String?
    }

    struct JSONSchemaFormat: Encodable {
        let type: String
        let name: String
        let schema: JSONValue
        let strict: Bool
    }

    struct TextConfig: Encodable {
        let verbosity: String
        let format: JSONSchemaFormat?
    }

    let model: String
    let instructions: String?
    let input: [InputItem]
    let tools: [Tool]?
    let toolChoice: JSONValue?
    let parallelToolCalls: Bool
    let store: Bool
    let stream: Bool
    let include: [String]
    let promptCacheKey: String?
    let reasoning: Reasoning?
    let text: TextConfig?

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case store
        case stream
        case include
        case promptCacheKey = "prompt_cache_key"
        case reasoning
        case text
    }
}

private enum ClaudeCompatReducerEvent {
    case textStart(index: Int)
    case textDelta(index: Int, text: String)
    case textStop(index: Int)
    case toolStart(index: Int, id: String, name: String)
    case toolDelta(index: Int, partialJSON: String)
    case toolStop(index: Int)
    case finish(stopReason: String, usage: ClaudeCompatCodexUsage?)
}

private struct ClaudeCompatCodexUsage {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
}

private struct ClaudeCompatSSEEvent {
    let event: String
    let data: String
}

private enum ClaudeCompatAccumulatedBlock {
    case text(String)
    case tool(id: String, name: String, args: String)
}

private enum ClaudeCompatReducerBlockState {
    case text(index: Int, text: String)
    case tool(index: Int, id: String, name: String, args: String, emitted: Bool, bufferUntilDone: Bool)
}

private enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

@MainActor
final class ClaudeProxyRoutingManager: ObservableObject {
    enum ToggleState: Equatable {
        case off
        case starting
        case on
        case failed(String)

        var label: String {
            switch self {
            case .off: return "Off"
            case .starting: return "Starting"
            case .on: return "On"
            case .failed: return "Error"
            }
        }
    }

    @Published private(set) var toggleState: ToggleState = .off
    @Published private(set) var switcherStatus: ClaudeSwitcherStatus
    @Published private(set) var lastError: String?
    @Published private(set) var activeAccountEmail: String?

    private let store = ClaudeProxyStore()
    private let proxyService = ClaudeCompatProxyService.shared
    private let codexAuthManager: CodexAuthManager
    private var cancellables = Set<AnyCancellable>()

    var isEnabled: Bool {
        if case .on = toggleState { return true }
        if case .starting = toggleState { return true }
        return false
    }

    init(codexAuthManager: CodexAuthManager) {
        self.codexAuthManager = codexAuthManager
        self.switcherStatus = store.detectedSwitcherStatus()
        self.activeAccountEmail = codexAuthManager.activeAccount?.email
        bind()

        if store.isEnabled() {
            if codexAuthManager.accounts.isEmpty {
                try? store.deactivate()
            } else {
                try? store.activate(port: ClaudeProxyStore.defaultPort)
                proxyService.setAccounts(codexAuthManager.accounts, preferredAccountId: codexAuthManager.activeAccountId)
                proxyService.startIfNeeded()
                toggleState = .on
            }
        }
    }

    func setEnabled(_ enabled: Bool) async {
        if enabled {
            await enable()
        } else {
            disable()
        }
    }

    private func enable() async {
        guard !codexAuthManager.accounts.isEmpty else {
            lastError = "Add at least one ChatGPT account first."
            toggleState = .failed(lastError ?? "Missing ChatGPT account")
            return
        }

        lastError = nil
        toggleState = .starting

        proxyService.setAccounts(codexAuthManager.accounts, preferredAccountId: codexAuthManager.activeAccountId)
        proxyService.startIfNeeded()

        do {
            try store.activate(port: ClaudeProxyStore.defaultPort)
            toggleState = .on
        } catch {
            proxyService.stop()
            lastError = error.localizedDescription
            toggleState = .failed(error.localizedDescription)
        }
    }

    func disable() {
        do {
            try store.deactivate()
            toggleState = .off
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            toggleState = .failed(error.localizedDescription)
        }
    }

    private func bind() {
        codexAuthManager.$accounts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] accounts in
                guard let self else { return }
                activeAccountEmail = codexAuthManager.activeAccount?.email
                switcherStatus = store.detectedSwitcherStatus()

                if accounts.isEmpty {
                    if isEnabled {
                        disable()
                        lastError = "ChatGPT routing was disabled because no ChatGPT accounts remain."
                    } else {
                        proxyService.stop()
                        toggleState = .off
                    }
                    return
                }

                proxyService.setAccounts(accounts, preferredAccountId: codexAuthManager.activeAccountId)
                if isEnabled {
                    proxyService.startIfNeeded()
                    if case .starting = toggleState {
                        toggleState = .on
                    }
                }
            }
            .store(in: &cancellables)

        codexAuthManager.$activeAccountId
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                activeAccountEmail = codexAuthManager.activeAccount?.email
                proxyService.setAccounts(codexAuthManager.accounts, preferredAccountId: codexAuthManager.activeAccountId)
            }
            .store(in: &cancellables)

        proxyService.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if case .failed(let message) = status {
                    lastError = message
                    toggleState = .failed(message)
                } else if status.isRunning, isEnabled, case .starting = toggleState {
                    toggleState = .on
                }
            }
            .store(in: &cancellables)
    }
}

final class ClaudeCompatProxyService: ObservableObject {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case failed(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    static let shared = ClaudeCompatProxyService()

    @Published private(set) var status: Status = .stopped

    private let stateQueue = DispatchQueue(label: "com.khairul.aimeter.claude-compat-proxy")
    private let urlSession: URLSession
    private let host = "127.0.0.1"
    private let port = ClaudeProxyStore.defaultPort
    private let strippedInboundHeaders: Set<String> = [
        "authorization",
        "content-length",
        "connection",
        "host",
        "forwarded",
        "proxy-connection"
    ]
    private let lastRoutedAccountKey = "claudeCompatProxyLastRoutedAccountId"
    private let anthropicDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var accounts: [CodexAccount] = []
    private var preferredAccountId: String?
    private var accountStates: [String: CodexAccountState] = [:]

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?
    private var starting = false

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        self.urlSession = URLSession(configuration: configuration)
    }

    func setAccounts(_ accounts: [CodexAccount], preferredAccountId: String?) {
        stateQueue.async {
            self.accounts = accounts
            self.preferredAccountId = preferredAccountId
            let validIds = Set(accounts.map(\.id))
            self.accountStates = self.accountStates.filter { validIds.contains($0.key) }
            if accounts.isEmpty {
                self.stop()
            }
        }
    }

    func startIfNeeded() {
        stateQueue.async {
            guard !self.accounts.isEmpty else { return }
            guard self.serverChannel == nil, !self.starting else { return }
            self.starting = true
            self.publishStatus(.starting)

            do {
                let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
                let bootstrap = ServerBootstrap(group: group)
                    .serverChannelOption(ChannelOptions.backlog, value: 256)
                    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelInitializer { channel in
                        self.configure(channel: channel)
                    }
                    .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
                    .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

                let serverChannel = try bootstrap.bind(host: self.host, port: Int(self.port)).wait()
                self.eventLoopGroup = group
                self.serverChannel = serverChannel
                self.starting = false
                self.publishStatus(.running)
            } catch {
                self.starting = false
                try? self.eventLoopGroup?.syncShutdownGracefully()
                self.eventLoopGroup = nil
                self.serverChannel = nil
                self.publishStatus(.failed(error.localizedDescription))
            }
        }
    }

    func stop() {
        stateQueue.async {
            try? self.serverChannel?.close().wait()
            self.serverChannel = nil
            if let group = self.eventLoopGroup {
                try? group.syncShutdownGracefully()
            }
            self.eventLoopGroup = nil
            self.starting = false
            self.publishStatus(.stopped)
        }
    }

    fileprivate func handleRequest(
        requestID: String,
        method: String,
        uri: String,
        headers: [(String, String)],
        body: Data
    ) async throws -> ClaudeCompatInboundResult {
        let path = URIPathParser.path(from: uri)
        ClaudeCompatDiagnostics.shared.info(
            "Inbound request",
            requestID: requestID,
            metadata: [
                "method": method,
                "uri": uri,
                "path": path,
                "bodyBytes": body.count
            ]
        )

        if path == "/healthz" {
            let body = try JSONEncoder.appEncoder.encode(["ok": true])
            ClaudeCompatDiagnostics.shared.debug("Health check response", requestID: requestID, metadata: ["status": 200])
            return .response(
                ClaudeCompatProxyResponse(
                    statusCode: 200,
                    reasonPhrase: "OK",
                    headers: [("Content-Type", "application/json")],
                    body: body
                )
            )
        }

        guard method == "POST" else {
            throw ClaudeCompatProxyError.invalidPath
        }

        if path == "/v1/messages/count_tokens" {
            let request = try decodeAnthropicRequest(from: body, requestID: requestID)
            let inputTokens = approximateInputTokens(for: request)
            ClaudeCompatDiagnostics.shared.info(
                "Count tokens request",
                requestID: requestID,
                metadata: [
                    "model": request.model,
                    "messages": request.messages.count,
                    "tools": request.tools?.count ?? 0,
                    "input_tokens": inputTokens
                ]
            )
            let responseBody = try JSONEncoder.appEncoder.encode(["input_tokens": inputTokens])
            return .response(
                ClaudeCompatProxyResponse(
                    statusCode: 200,
                    reasonPhrase: "OK",
                    headers: [("Content-Type", "application/json")],
                    body: responseBody
                )
            )
        }

        guard path == "/v1/messages" else {
            throw ClaudeCompatProxyError.invalidPath
        }

        let request = try decodeAnthropicRequest(from: body, requestID: requestID)
        let sessionID = headers.first(where: { $0.0.lowercased() == "x-claude-code-session-id" })?.1
        let requestedModel = request.model.isEmpty ? "sonnet" : request.model
        let resolvedModel = ClaudeCompatModelPolicy.resolve(requestedModel)
        ClaudeCompatDiagnostics.shared.info(
            "Claude messages request",
            requestID: requestID,
            metadata: [
                "requestedModel": requestedModel,
                "resolvedModel": resolvedModel,
                "messages": request.messages.count,
                "tools": request.tools?.count ?? 0,
                "stream": request.stream ?? true,
                "sessionID": sessionID ?? "-"
            ]
        )
        try ClaudeCompatModelPolicy.validate(resolvedModel)
        let translated = try translateRequest(request, resolvedModel: resolvedModel, sessionID: sessionID)
        ClaudeCompatDiagnostics.shared.debug(
            "Translated request",
            requestID: requestID,
            metadata: [
                "upstreamModel": translated.model,
                "inputItems": translated.input.count,
                "hasInstructions": translated.instructions != nil,
                "tools": translated.tools?.count ?? 0,
                "toolChoice": translated.toolChoice.map(String.init(describing:)) ?? "nil"
            ]
        )

        if request.stream == false {
            let response = try await performNonStreamingMessageRequest(
                translated,
                requestID: requestID,
                requestedModel: requestedModel,
                sessionID: sessionID
            )
            return .response(response)
        }

        let opened = try await openStreamingRequest(translated, sessionID: sessionID, requestID: requestID)
        let messageID = "msg_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        ClaudeCompatDiagnostics.shared.info(
            "Opening SSE response",
            requestID: requestID,
            metadata: [
                "messageID": messageID,
                "accountID": opened.accountID
            ]
        )

        return .stream(
            ClaudeCompatSSEStream(
                statusCode: 200,
                reasonPhrase: "OK",
                headers: [
                    ("Content-Type", "text/event-stream"),
                    ("Cache-Control", "no-cache"),
                    ("Connection", "keep-alive")
                ],
                relay: { emit in
                    try await self.relayStreamingResponse(
                        opened.bytes,
                        requestID: requestID,
                        accountID: opened.accountID,
                        requestedModel: requestedModel,
                        messageID: messageID,
                        emit: emit
                    )
                }
            )
        )
    }

    private func decodeAnthropicRequest(from body: Data, requestID: String) throws -> ClaudeCompatAnthropicRequest {
        do {
            return try anthropicDecoder.decode(ClaudeCompatAnthropicRequest.self, from: body)
        } catch {
            ClaudeCompatDiagnostics.shared.saveFailedRequestBody(body)
            let details = anthropicDecodeFailureMetadata(for: body, error: error)
            ClaudeCompatDiagnostics.shared.error(
                "Failed to decode Anthropic request",
                requestID: requestID,
                metadata: details.merging([
                    "savedBody": AppConstants.Paths.configDir
                        .appendingPathComponent("logs/claude-compat-proxy-last-failed-request.json")
                        .path
                ]) { current, _ in current }
            )
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound, .typeMismatch, .valueNotFound, .dataCorrupted:
                    throw ClaudeCompatProxyError.invalidJSON
                @unknown default:
                    throw error
                }
            }
            throw error
        }
    }

    private func anthropicDecodeFailureMetadata(for body: Data, error: Error) -> [String: Any?] {
        var metadata: [String: Any?] = [
            "error": String(describing: error),
            "bodyBytes": body.count
        ]

        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, let context):
                metadata["decodeKind"] = "keyNotFound"
                metadata["codingPath"] = codingPathDescription(context.codingPath)
                metadata["missingKey"] = key.stringValue
                metadata["debugDescription"] = context.debugDescription
            case .typeMismatch(let type, let context):
                metadata["decodeKind"] = "typeMismatch"
                metadata["codingPath"] = codingPathDescription(context.codingPath)
                metadata["mismatchType"] = String(describing: type)
                metadata["debugDescription"] = context.debugDescription
            case .valueNotFound(let type, let context):
                metadata["decodeKind"] = "valueNotFound"
                metadata["codingPath"] = codingPathDescription(context.codingPath)
                metadata["missingType"] = String(describing: type)
                metadata["debugDescription"] = context.debugDescription
            case .dataCorrupted(let context):
                metadata["decodeKind"] = "dataCorrupted"
                metadata["codingPath"] = codingPathDescription(context.codingPath)
                metadata["debugDescription"] = context.debugDescription
            @unknown default:
                metadata["decodeKind"] = "unknown"
            }
        }

        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            metadata["topLevelJSON"] = "unreadable"
            return metadata
        }

        metadata["topLevelKeys"] = jsonObject.keys.sorted().joined(separator: ",")
        if let tools = jsonObject["tools"] as? [[String: Any]], let firstTool = tools.first {
            metadata["toolCount"] = tools.count
            metadata["firstToolKeys"] = firstTool.keys.sorted().joined(separator: ",")
        }
        if let messages = jsonObject["messages"] as? [[String: Any]], let firstMessage = messages.first {
            metadata["messageCount"] = messages.count
            metadata["firstMessageKeys"] = firstMessage.keys.sorted().joined(separator: ",")
            if let content = firstMessage["content"] as? [[String: Any]] {
                metadata["firstMessageBlockTypes"] = content.compactMap { $0["type"] as? String }.prefix(8).joined(separator: ",")
                if let firstBlock = content.first {
                    metadata["firstBlockKeys"] = firstBlock.keys.sorted().joined(separator: ",")
                }
            } else {
                metadata["firstMessageContentType"] = type(of: firstMessage["content"] as Any)
            }
        }
        if let system = jsonObject["system"] {
            metadata["systemType"] = type(of: system)
        }
        if let outputConfig = jsonObject["output_config"] as? [String: Any] {
            metadata["outputConfigKeys"] = outputConfig.keys.sorted().joined(separator: ",")
        }

        return metadata
    }

    private func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "<root>" }
        return codingPath.map(\.stringValue).joined(separator: ".")
    }

    private func performNonStreamingMessageRequest(
        _ request: ClaudeCompatResponsesRequest,
        requestID: String,
        requestedModel: String,
        sessionID: String?
    ) async throws -> ClaudeCompatProxyResponse {
        let opened = try await openStreamingRequest(request, sessionID: sessionID, requestID: requestID)
        let response = try await accumulateNonStreamingResponse(
            from: opened.bytes,
            requestID: requestID,
            accountID: opened.accountID,
            requestedModel: requestedModel
        )
        ClaudeCompatDiagnostics.shared.info(
            "Non-streaming response complete",
            requestID: requestID,
            metadata: [
                "accountID": opened.accountID,
                "contentBlocks": response.content.count,
                "stopReason": response.stopReason ?? "nil"
            ]
        )
        let body = try JSONEncoder.appEncoder.encode(response)
        return ClaudeCompatProxyResponse(
            statusCode: 200,
            reasonPhrase: "OK",
            headers: [("Content-Type", "application/json")],
            body: body
        )
    }

    private func openStreamingRequest(
        _ request: ClaudeCompatResponsesRequest,
        sessionID: String?,
        requestID: String
    ) async throws -> (bytes: URLSession.AsyncBytes, accountID: String) {
        var attempted = Set<String>()
        var lastError: ClaudeCompatUpstreamError?

        while let context = nextAccountContext(excluding: attempted) {
            attempted.insert(context.accountId)
            ClaudeCompatDiagnostics.shared.info(
                "Attempting upstream account",
                requestID: requestID,
                metadata: [
                    "accountID": context.accountId,
                    "chatgptAccountID": context.chatGPTAccountId,
                    "attemptedCount": attempted.count
                ]
            )
            do {
                let bytes = try await performStreamingUpstreamRequest(request, context: context, sessionID: sessionID, requestID: requestID)
                recordSelectedAccount(context.accountId)
                persistState(CodexAccountState(status: .ready, resetAt: nil, updatedAt: Date(), message: nil), for: context.accountId)
                ClaudeCompatDiagnostics.shared.info(
                    "Upstream account selected",
                    requestID: requestID,
                    metadata: ["accountID": context.accountId]
                )
                return (bytes, context.accountId)
            } catch let error as ClaudeCompatUpstreamError {
                lastError = error
                ClaudeCompatDiagnostics.shared.warning(
                    "Upstream account failed",
                    requestID: requestID,
                    metadata: [
                        "accountID": context.accountId,
                        "statusCode": error.statusCode,
                        "message": error.message,
                        "retryAfter": error.retryAfter ?? "-"
                    ]
                )
                if error.statusCode == 401 {
                    persistState(CodexAccountState(status: .unauthorized, resetAt: nil, updatedAt: Date(), message: error.message), for: context.accountId)
                    continue
                }
                if error.statusCode == 429 {
                    let retryAfter = TimeInterval(error.retryAfter ?? "") ?? 60
                    persistState(
                        CodexAccountRouting.rateLimitedState(
                            retryAfter: retryAfter,
                            message: error.message
                        ),
                        for: context.accountId
                    )
                    continue
                }
                persistState(CodexAccountState(status: .unavailable, resetAt: nil, updatedAt: Date(), message: error.message), for: context.accountId)
                throw error
            }
        }

        if let lastError {
            throw lastError
        }

        throw ClaudeCompatProxyError.missingActiveAccount
    }

    private func performStreamingUpstreamRequest(
        _ requestBody: ClaudeCompatResponsesRequest,
        context: ClaudeCompatAccountContext,
        sessionID: String?,
        requestID: String
    ) async throws -> URLSession.AsyncBytes {
        // Resolve the bearer token: prefer OAuth (real-time tier) over web-session (batch tier).
        // If OAuth throws (keychain error, network), fall back silently to web-session so the
        // proxy never hard-fails just because OAuth state is broken.
        let oauthService = CodexOAuthService.shared
        let bearerToken: String
        let usedOAuth: Bool
        do {
            if let oauthToken = try await oauthService.currentAccessToken(for: context.accountId) {
                bearerToken = oauthToken
                usedOAuth = true
            } else {
                bearerToken = context.accessToken
                usedOAuth = false
            }
        } catch {
            ClaudeCompatDiagnostics.shared.debug(
                "OAuth token resolution failed, falling back to web-session",
                requestID: requestID,
                metadata: ["accountID": context.accountId, "error": error.localizedDescription]
            )
            bearerToken = context.accessToken
            usedOAuth = false
        }

        ClaudeCompatDiagnostics.shared.debug(
            "Bearer token resolved",
            requestID: requestID,
            metadata: ["accountID": context.accountId, "bearerSource": usedOAuth ? "oauth" : "web_session"]
        )

        func buildRequest(bearer: String) throws -> URLRequest {
            var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/codex/responses")!)
            req.httpMethod = "POST"
            // NOTE: use a plain encoder, NOT `JSONEncoder.appEncoder`. The shared app encoder has
            // `keyEncodingStrategy = .convertToSnakeCase`, which would recursively mangle every key
            // inside tool JSON schemas (`additionalProperties` → `additional_properties`, etc.) and
            // cause the Codex backend to fall into a slow interpretive path on malformed schemas.
            // Our explicit CodingKeys already handle Swift-to-snake_case mapping at the top level.
            let upstreamEncoder = JSONEncoder()
            req.httpBody = try upstreamEncoder.encode(requestBody)
            req.timeoutInterval = 60
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            req.setValue(context.chatGPTAccountId, forHTTPHeaderField: "ChatGPT-Account-Id")
            req.setValue("responses=experimental", forHTTPHeaderField: "openai-beta")
            req.setValue("claude-codex-proxy", forHTTPHeaderField: "originator")
            if let sessionID {
                req.setValue(sessionID, forHTTPHeaderField: "session_id")
                req.setValue(sessionID, forHTTPHeaderField: "x-client-request-id")
                req.setValue("\(sessionID):0", forHTTPHeaderField: "x-codex-window-id")
            }
            return req
        }

        ClaudeCompatDiagnostics.shared.debug(
            "Sending upstream request",
            requestID: requestID,
            metadata: [
                "url": "https://chatgpt.com/backend-api/codex/responses",
                "accountID": context.accountId,
                "model": requestBody.model,
                "sessionID": sessionID ?? "-"
            ]
        )

        let request = try buildRequest(bearer: bearerToken)
        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeCompatProxyError.invalidResponse
        }

        ClaudeCompatDiagnostics.shared.info(
            "Received upstream response",
            requestID: requestID,
            metadata: [
                "statusCode": httpResponse.statusCode,
                "accountID": context.accountId
            ]
        )

        // OAuth 401 retry: on first 401 with an OAuth token, force-refresh once and retry.
        // If the retry also 401s, revoke local OAuth and let the caller's account rotation handle it.
        if httpResponse.statusCode == 401 && usedOAuth {
            ClaudeCompatDiagnostics.shared.debug(
                "OAuth 401 received, attempting force-refresh",
                requestID: requestID,
                metadata: ["accountID": context.accountId]
            )
            let freshToken: String?
            do {
                freshToken = try await oauthService.refreshAccessToken(for: context.accountId)
            } catch {
                ClaudeCompatDiagnostics.shared.debug(
                    "OAuth force-refresh threw, revoking local tokens",
                    requestID: requestID,
                    metadata: ["accountID": context.accountId, "error": error.localizedDescription]
                )
                await oauthService.revokeLocalTokens(for: context.accountId)
                let body = try await collect(bytes)
                let message = parseUpstreamErrorMessage(from: body) ?? HTTPURLResponse.localizedString(forStatusCode: 401)
                throw ClaudeCompatUpstreamError(statusCode: 401, message: message, retryAfter: nil)
            }

            guard let freshToken else {
                // hasOAuthTokens went false mid-request (race with revoke) — fall through to normal error
                let body = try await collect(bytes)
                let message = parseUpstreamErrorMessage(from: body) ?? HTTPURLResponse.localizedString(forStatusCode: 401)
                throw ClaudeCompatUpstreamError(statusCode: 401, message: message, retryAfter: nil)
            }

            let retryRequest = try buildRequest(bearer: freshToken)
            let (retryBytes, retryResponse) = try await urlSession.bytes(for: retryRequest)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw ClaudeCompatProxyError.invalidResponse
            }

            ClaudeCompatDiagnostics.shared.info(
                "Received upstream response (OAuth retry)",
                requestID: requestID,
                metadata: ["statusCode": retryHTTP.statusCode, "accountID": context.accountId]
            )

            if retryHTTP.statusCode == 401 {
                // Both attempts 401'd — OAuth credentials are fully revoked server-side
                await oauthService.revokeLocalTokens(for: context.accountId)
                let body = try await collect(retryBytes)
                let message = parseUpstreamErrorMessage(from: body) ?? HTTPURLResponse.localizedString(forStatusCode: 401)
                throw ClaudeCompatUpstreamError(statusCode: 401, message: message, retryAfter: nil)
            }

            guard (200 ..< 300).contains(retryHTTP.statusCode) else {
                let body = try await collect(retryBytes)
                let message = parseUpstreamErrorMessage(from: body) ?? HTTPURLResponse.localizedString(forStatusCode: retryHTTP.statusCode)
                throw ClaudeCompatUpstreamError(
                    statusCode: retryHTTP.statusCode,
                    message: message,
                    retryAfter: retryHTTP.value(forHTTPHeaderField: "retry-after")
                )
            }

            return retryBytes
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = try await collect(bytes)
            let message = parseUpstreamErrorMessage(from: body) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw ClaudeCompatUpstreamError(
                statusCode: httpResponse.statusCode,
                message: message,
                retryAfter: httpResponse.value(forHTTPHeaderField: "retry-after")
            )
        }

        return bytes
    }

    private func relayStreamingResponse<S: AsyncSequence>(
        _ bytes: S,
        requestID: String,
        accountID: String,
        requestedModel: String,
        messageID: String,
        emit: @escaping (Data) -> Void
    ) async throws where S.Element == UInt8 {
        var messageStarted = false
        var textBlockCount = 0
        var toolBlockCount = 0
        var deltaCount = 0

        func ensureMessageStart() {
            guard !messageStarted else { return }
            messageStarted = true

            let start = encodeSSE(
                event: "message_start",
                payload: [
                    "type": .string("message_start"),
                    "message": .object([
                        "id": .string(messageID),
                        "type": .string("message"),
                        "role": .string("assistant"),
                        "model": .string(requestedModel),
                        "content": .array([]),
                        "stop_reason": .null,
                        "stop_sequence": .null,
                        "usage": .object([
                            "input_tokens": .number(0),
                            "output_tokens": .number(0),
                            "cache_creation_input_tokens": .number(0),
                            "cache_read_input_tokens": .number(0)
                        ])
                    ])
                ]
            )
            emit(start)
            emit(encodeSSE(event: "ping", payload: ["type": .string("ping")]))
        }

        do {
            try await reduceUpstream(bytes, requestID: requestID) { event in
                switch event {
                case .textStart(let index):
                    textBlockCount += 1
                    ensureMessageStart()
                    emit(
                        encodeSSE(
                            event: "content_block_start",
                            payload: [
                                "type": .string("content_block_start"),
                                "index": .number(Double(index)),
                                "content_block": .object([
                                    "type": .string("text"),
                                    "text": .string("")
                                ])
                            ]
                        )
                    )
                case .textDelta(let index, let text):
                    deltaCount += 1
                    emit(
                        encodeSSE(
                            event: "content_block_delta",
                            payload: [
                                "type": .string("content_block_delta"),
                                "index": .number(Double(index)),
                                "delta": .object([
                                    "type": .string("text_delta"),
                                    "text": .string(text)
                                ])
                            ]
                        )
                    )
                case .textStop(let index):
                    emit(encodeSSE(event: "content_block_stop", payload: ["type": .string("content_block_stop"), "index": .number(Double(index))]))
                case .toolStart(let index, let id, let name):
                    toolBlockCount += 1
                    ensureMessageStart()
                    emit(
                        encodeSSE(
                            event: "content_block_start",
                            payload: [
                                "type": .string("content_block_start"),
                                "index": .number(Double(index)),
                                "content_block": .object([
                                    "type": .string("tool_use"),
                                    "id": .string(id),
                                    "name": .string(name),
                                    "input": .object([:])
                                ])
                            ]
                        )
                    )
                case .toolDelta(let index, let partialJSON):
                    deltaCount += 1
                    emit(
                        encodeSSE(
                            event: "content_block_delta",
                            payload: [
                                "type": .string("content_block_delta"),
                                "index": .number(Double(index)),
                                "delta": .object([
                                    "type": .string("input_json_delta"),
                                    "partial_json": .string(partialJSON)
                                ])
                            ]
                        )
                    )
                case .toolStop(let index):
                    emit(encodeSSE(event: "content_block_stop", payload: ["type": .string("content_block_stop"), "index": .number(Double(index))]))
                case .finish(let stopReason, let usage):
                    ensureMessageStart()
                    ClaudeCompatDiagnostics.shared.info(
                        "Streaming translation finished",
                        requestID: requestID,
                        metadata: [
                            "accountID": accountID,
                            "messageID": messageID,
                            "requestedModel": requestedModel,
                            "stopReason": stopReason,
                            "textBlocks": textBlockCount,
                            "toolBlocks": toolBlockCount,
                            "deltas": deltaCount,
                            "inputTokens": usage?.inputTokens ?? 0,
                            "outputTokens": usage?.outputTokens ?? 0,
                            "cachedTokens": usage?.cachedTokens ?? 0
                        ]
                    )
                    emit(
                        encodeSSE(
                            event: "message_delta",
                            payload: [
                                "type": .string("message_delta"),
                                "delta": .object([
                                    "stop_reason": .string(stopReason),
                                    "stop_sequence": .null
                                ]),
                                "usage": anthropicUsageObject(from: usage)
                            ]
                        )
                    )
                    emit(encodeSSE(event: "message_stop", payload: ["type": .string("message_stop")]))
                }
            }
        } catch let error as ClaudeCompatUpstreamStreamError {
            updateState(for: accountID, from: error)
            ClaudeCompatDiagnostics.shared.warning(
                "Streaming upstream error",
                requestID: requestID,
                metadata: [
                    "accountID": accountID,
                    "kind": String(describing: error.kind),
                    "message": error.message,
                    "retryAfter": error.retryAfterSeconds ?? -1
                ]
            )
            ensureMessageStart()
            emit(
                encodeSSE(
                    event: "error",
                    payload: [
                        "type": .string("error"),
                        "error": .object([
                            "type": .string(error.kind == .rateLimit ? "rate_limit_error" : "api_error"),
                            "message": .string(error.message)
                        ])
                    ]
                )
            )
        } catch {
            persistState(CodexAccountState(status: .unavailable, resetAt: nil, updatedAt: Date(), message: error.localizedDescription), for: accountID)
            ClaudeCompatDiagnostics.shared.error(
                "Streaming translation error",
                requestID: requestID,
                metadata: [
                    "accountID": accountID,
                    "message": error.localizedDescription
                ]
            )
            ensureMessageStart()
            emit(
                encodeSSE(
                    event: "error",
                    payload: [
                        "type": .string("error"),
                        "error": .object([
                            "type": .string("api_error"),
                            "message": .string(error.localizedDescription)
                        ])
                    ]
                )
            )
        }
    }

    private struct AnthropicResponseContentBlock: Encodable {
        let type: String
        let text: String?
        let id: String?
        let name: String?
        let input: JSONValue?
    }

    private struct AnthropicResponseEnvelope: Encodable {
        let id: String
        let type: String
        let role: String
        let model: String
        let content: [AnthropicResponseContentBlock]
        let stopReason: String?
        let stopSequence: String?
        let usage: [String: Int]

        enum CodingKeys: String, CodingKey {
            case id
            case type
            case role
            case model
            case content
            case stopReason = "stop_reason"
            case stopSequence = "stop_sequence"
            case usage
        }
    }

    private func accumulateNonStreamingResponse<S: AsyncSequence>(
        from bytes: S,
        requestID: String,
        accountID: String,
        requestedModel: String
    ) async throws -> AnthropicResponseEnvelope where S.Element == UInt8 {
        var order: [Int] = []
        var blocks: [Int: ClaudeCompatAccumulatedBlock] = [:]
        var stopReason: String?
        var usage: ClaudeCompatCodexUsage?

        do {
            try await reduceUpstream(bytes, requestID: requestID) { event in
                switch event {
                case .textStart(let index):
                    blocks[index] = .text("")
                    order.append(index)
                case .textDelta(let index, let text):
                    if case .text(let existing)? = blocks[index] {
                        blocks[index] = .text(existing + text)
                    }
                case .toolStart(let index, let id, let name):
                    blocks[index] = .tool(id: id, name: name, args: "")
                    order.append(index)
                case .toolDelta(let index, let partialJSON):
                    if case .tool(let id, let name, let args)? = blocks[index] {
                        blocks[index] = .tool(id: id, name: name, args: args + partialJSON)
                    }
                case .finish(let finalStopReason, let finalUsage):
                    stopReason = finalStopReason
                    usage = finalUsage
                case .textStop, .toolStop:
                    break
                }
            }
        } catch let error as ClaudeCompatUpstreamStreamError {
            updateState(for: accountID, from: error)
            ClaudeCompatDiagnostics.shared.warning(
                "Non-streaming upstream error",
                requestID: requestID,
                metadata: [
                    "accountID": accountID,
                    "kind": String(describing: error.kind),
                    "message": error.message
                ]
            )
            if error.kind == .rateLimit {
                throw ClaudeCompatUpstreamError(statusCode: 429, message: error.message, retryAfter: error.retryAfterSeconds.map(String.init))
            }
            throw ClaudeCompatUpstreamError(statusCode: 502, message: error.message, retryAfter: nil)
        }

        let content: [AnthropicResponseContentBlock] = order.compactMap { index in
            guard let block = blocks[index] else { return nil }
            switch block {
            case .text(let text):
                guard !text.isEmpty else { return nil }
                return AnthropicResponseContentBlock(type: "text", text: text, id: nil, name: nil, input: nil)
            case .tool(let id, let name, let args):
                let parsedInput: JSONValue
                if let data = args.data(using: .utf8),
                   let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
                    parsedInput = json
                } else {
                    parsedInput = .object(["_raw": .string(args)])
                }
                return AnthropicResponseContentBlock(type: "tool_use", text: nil, id: id, name: name, input: parsedInput)
            }
        }

        return AnthropicResponseEnvelope(
            id: "msg_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            type: "message",
            role: "assistant",
            model: requestedModel,
            content: content,
            stopReason: stopReason,
            stopSequence: nil,
            usage: anthropicUsageDictionary(from: usage)
        )
    }

    private func shouldBufferToolArgs(_ name: String) -> Bool {
        name == "Read"
    }

    private func sanitizeToolArgs(name: String, args: String) -> String {
        guard name == "Read", !args.isEmpty else { return args }
        guard let data = args.data(using: .utf8),
              var parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return args }
        if let pages = parsed["pages"] as? String, pages.isEmpty {
            parsed.removeValue(forKey: "pages")
            if let sanitized = try? JSONSerialization.data(withJSONObject: parsed),
               let result = String(data: sanitized, encoding: .utf8) {
                return result
            }
        }
        return args
    }

    private func reduceUpstream<S: AsyncSequence>(
        _ bytes: S,
        requestID: String,
        emit: (ClaudeCompatReducerEvent) throws -> Void
    ) async throws where S.Element == UInt8 {
        var blocksByOutputIndex: [Int: ClaudeCompatReducerBlockState] = [:]
        var itemIDToOutputIndex: [String: Int] = [:]
        var anthropicIndex = 0
        var sawToolUse = false
        var finalUsage: ClaudeCompatCodexUsage?
        var incomplete = false

        do {
        try await parseSSEBytes(bytes) { event in
            let preview = event.data.replacingOccurrences(of: "\n", with: "\\n").prefix(240)
            ClaudeCompatDiagnostics.shared.debug(
                "Raw upstream SSE event",
                requestID: requestID,
                metadata: [
                    "event": event.event.isEmpty ? "-" : event.event,
                    "preview": String(preview)
                ]
            )

            guard !event.data.isEmpty,
                  let data = event.data.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(JSONValue.self, from: data),
                  let object = payload.objectValue
            else {
                ClaudeCompatDiagnostics.shared.warning(
                    "Unable to decode upstream SSE payload",
                    requestID: requestID,
                    metadata: [
                        "event": event.event.isEmpty ? "-" : event.event,
                        "preview": String(preview)
                    ]
                )
                return
            }

            let type = object["type"]?.stringValue ?? event.event
            ClaudeCompatDiagnostics.shared.debug(
                "Upstream SSE event",
                requestID: requestID,
                metadata: [
                    "type": type,
                    "event": event.event,
                    "outputIndex": object["output_index"]?.intValue.map(String.init) ?? "-",
                    "itemType": object["item"]?.objectValue?["type"]?.stringValue ?? "-"
                ]
            )

            if type == "codex.rate_limits" {
                if object["rate_limits"]?.objectValue?["limit_reached"]?.boolValue == true {
                    let retryAfter = object["rate_limits"]?.objectValue?["primary"]?.objectValue?["reset_after_seconds"]?.intValue
                    throw ClaudeCompatUpstreamStreamError(kind: .rateLimit, message: "rate limit reached", retryAfterSeconds: retryAfter)
                }
                return
            }

            if type == "response.failed" || type == "response.error" || type == "error" {
                let message = object["response"]?.objectValue?["error"]?.objectValue?["message"]?.stringValue
                    ?? object["error"]?.objectValue?["message"]?.stringValue
                    ?? "Upstream error"
                throw ClaudeCompatUpstreamStreamError(kind: .failed, message: message, retryAfterSeconds: nil)
            }

            if type == "response.output_item.added" {
                guard let outputIndex = object["output_index"]?.intValue,
                      let item = object["item"]?.objectValue,
                      let itemType = item["type"]?.stringValue
                else { return }

                if itemType == "reasoning" {
                    return
                }

                if itemType == "message" {
                    let index = anthropicIndex
                    anthropicIndex += 1
                    blocksByOutputIndex[outputIndex] = .text(index: index, text: "")
                    if let itemID = item["id"]?.stringValue {
                        itemIDToOutputIndex[itemID] = outputIndex
                    }
                    try emit(.textStart(index: index))
                    return
                }

                if itemType == "function_call" {
                    guard let callID = item["call_id"]?.stringValue,
                          let name = item["name"]?.stringValue
                    else { return }
                    sawToolUse = true
                    let index = anthropicIndex
                    anthropicIndex += 1
                    blocksByOutputIndex[outputIndex] = .tool(index: index, id: callID, name: name, args: "", emitted: false, bufferUntilDone: shouldBufferToolArgs(name))
                    try emit(.toolStart(index: index, id: callID, name: name))
                }

                return
            }

            if type == "response.output_text.delta" {
                let outputIndex = object["output_index"]?.intValue
                    ?? object["item_id"]?.stringValue.flatMap { itemIDToOutputIndex[$0] }
                guard let outputIndex,
                      let state = blocksByOutputIndex[outputIndex],
                      case .text(let index, let text) = state
                else { return }

                let delta = object["delta"]?.stringValue ?? ""
                guard !delta.isEmpty else { return }
                blocksByOutputIndex[outputIndex] = .text(index: index, text: text + delta)
                try emit(.textDelta(index: index, text: delta))
                return
            }

            if type == "response.function_call_arguments.delta" {
                guard let outputIndex = object["output_index"]?.intValue,
                      let state = blocksByOutputIndex[outputIndex],
                      case .tool(let index, let id, let name, let args, _, let bufferUntilDone) = state
                else { return }

                let delta = object["delta"]?.stringValue ?? ""
                guard !delta.isEmpty else { return }
                if bufferUntilDone {
                    blocksByOutputIndex[outputIndex] = .tool(index: index, id: id, name: name, args: args + delta, emitted: false, bufferUntilDone: true)
                } else {
                    blocksByOutputIndex[outputIndex] = .tool(index: index, id: id, name: name, args: args + delta, emitted: true, bufferUntilDone: false)
                    try emit(.toolDelta(index: index, partialJSON: delta))
                }
                return
            }

            if type == "response.function_call_arguments.done" {
                guard let outputIndex = object["output_index"]?.intValue,
                      let state = blocksByOutputIndex[outputIndex],
                      case .tool(let index, let id, let name, let args, let emitted, let bufferUntilDone) = state
                else { return }

                let finalArgs = object["arguments"]?.stringValue ?? args
                blocksByOutputIndex[outputIndex] = .tool(index: index, id: id, name: name, args: finalArgs, emitted: emitted, bufferUntilDone: bufferUntilDone)
                return
            }

            if type == "response.output_item.done" {
                guard let outputIndex = object["output_index"]?.intValue,
                      let state = blocksByOutputIndex[outputIndex]
                else { return }

                switch state {
                case .text(let index, _):
                    try emit(.textStop(index: index))
                case .tool(let index, _, let name, let args, let emitted, let bufferUntilDone):
                    if !args.isEmpty, (bufferUntilDone || !emitted) {
                        let sanitized = sanitizeToolArgs(name: name, args: args)
                        try emit(.toolDelta(index: index, partialJSON: sanitized))
                    }
                    try emit(.toolStop(index: index))
                }

                blocksByOutputIndex.removeValue(forKey: outputIndex)
                // All output items complete — emit finish immediately, don't wait for response.completed
                if blocksByOutputIndex.isEmpty && anthropicIndex > 0 {
                    let stopReason = incomplete ? "max_tokens" : (sawToolUse ? "tool_use" : "end_turn")
                    throw ClaudeCompatEarlyFinish(stopReason: stopReason, usage: finalUsage)
                }
                return
            }

            if type == "response.completed" || type == "response.incomplete" {
                let usageObject = object["response"]?.objectValue?["usage"]?.objectValue
                finalUsage = ClaudeCompatCodexUsage(
                    inputTokens: usageObject?["input_tokens"]?.intValue ?? 0,
                    outputTokens: usageObject?["output_tokens"]?.intValue ?? 0,
                    cachedTokens: usageObject?["input_tokens_details"]?.objectValue?["cached_tokens"]?.intValue ?? 0
                )

                let reason = object["response"]?.objectValue?["incomplete_details"]?.objectValue?["reason"]?.stringValue
                if type == "response.incomplete"
                    || reason == "max_output_tokens"
                    || object["response"]?.objectValue?["status"]?.stringValue == "incomplete" {
                    incomplete = true
                }
            }
        }
        } catch let early as ClaudeCompatEarlyFinish {
            try emit(.finish(stopReason: early.stopReason, usage: early.usage))
            return
        }

        let stopReason = incomplete ? "max_tokens" : (sawToolUse ? "tool_use" : "end_turn")
        try emit(.finish(stopReason: stopReason, usage: finalUsage))
    }

    private func parseSSEBytes<S: AsyncSequence>(
        _ bytes: S,
        handleEvent: (ClaudeCompatSSEEvent) throws -> Void
    ) async throws where S.Element == UInt8 {
        var buffer = Data()

        func splitBoundary(in data: Data) -> Range<Data.Index>? {
            if let range = data.range(of: Data("\r\n\r\n".utf8)) { return range }
            if let range = data.range(of: Data("\n\n".utf8)) { return range }
            if let range = data.range(of: Data("\r\r".utf8)) { return range }
            return nil
        }

        func parseEventBlock(_ raw: String) -> ClaudeCompatSSEEvent? {
            var event = ""
            var dataLines: [String] = []

            for line in raw.components(separatedBy: CharacterSet.newlines) {
                guard !line.isEmpty, !line.hasPrefix(":") else { continue }
                let field: String
                let value: String
                if let colonIndex = line.firstIndex(of: ":") {
                    field = String(line[..<colonIndex])
                    value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    field = line
                    value = ""
                }

                if field == "event" {
                    event = value
                } else if field == "data" {
                    dataLines.append(value)
                }
            }

            guard !event.isEmpty || !dataLines.isEmpty else { return nil }
            return ClaudeCompatSSEEvent(event: event, data: dataLines.joined(separator: "\n"))
        }

        for try await byte in bytes {
            buffer.append(byte)

            while let boundary = splitBoundary(in: buffer) {
                let blockData = buffer.subdata(in: buffer.startIndex ..< boundary.lowerBound)
                buffer.removeSubrange(buffer.startIndex ..< boundary.upperBound)

                guard let raw = String(data: blockData, encoding: .utf8),
                      let event = parseEventBlock(raw)
                else { continue }

                try handleEvent(event)
            }
        }

        if !buffer.isEmpty,
           let raw = String(data: buffer, encoding: .utf8),
           let event = parseEventBlock(raw) {
            try handleEvent(event)
        }
    }

    private func translateRequest(
        _ request: ClaudeCompatAnthropicRequest,
        resolvedModel: String,
        sessionID: String?
    ) throws -> ClaudeCompatResponsesRequest {
        let input = request.messages.flatMap(translateMessage)
        let tools = request.tools?.map {
            ClaudeCompatResponsesRequest.Tool(
                type: "function",
                name: $0.name,
                description: $0.description,
                parameters: $0.inputSchema
            )
        }

        let toolChoice: JSONValue?
        switch request.toolChoice?.type {
        case "none":
            toolChoice = .string("none")
        case "any":
            toolChoice = .string("required")
        case "tool":
            if let name = request.toolChoice?.name {
                toolChoice = .object(["type": .string("function"), "name": .string(name)])
            } else {
                toolChoice = .string("required")
            }
        default:
            toolChoice = .string("auto")
        }

        let format = request.outputConfig?.format
        let textConfig: ClaudeCompatResponsesRequest.TextConfig?
        if let format, format.type == "json_schema", let schema = format.schema {
            textConfig = ClaudeCompatResponsesRequest.TextConfig(
                verbosity: "low",
                format: .init(
                    type: "json_schema",
                    name: format.name ?? "response",
                    schema: schema,
                    strict: format.strict ?? true
                )
            )
        } else {
            textConfig = ClaudeCompatResponsesRequest.TextConfig(verbosity: "low", format: nil)
        }

        return ClaudeCompatResponsesRequest(
            model: resolvedModel,
            instructions: request.system?.text,
            input: input,
            tools: tools,
            toolChoice: toolChoice,
            parallelToolCalls: true,
            store: false,
            stream: true,
            include: ["reasoning.encrypted_content"],
            promptCacheKey: sessionID,
            reasoning: request.outputConfig?.effort.map { ClaudeCompatResponsesRequest.Reasoning(effort: $0) },
            text: textConfig
        )
    }

    private func translateMessage(_ message: ClaudeCompatAnthropicRequest.Message) -> [ClaudeCompatResponsesRequest.InputItem] {
        let blocks = message.content.blocks
        if message.role == "user" {
            var items: [ClaudeCompatResponsesRequest.InputItem] = []
            var parts: [ClaudeCompatResponsesRequest.ContentPart] = []

            func flushMessage() {
                guard !parts.isEmpty else { return }
                items.append(.init(type: "message", role: "user", content: parts, callId: nil, name: nil, arguments: nil, output: nil))
                parts.removeAll(keepingCapacity: true)
            }

            for block in blocks {
                switch block.type {
                case "text":
                    if let text = block.text {
                        parts.append(.init(type: "input_text", text: text, imageURL: nil))
                    }
                case "image":
                    if let imageURL = imageURL(for: block.source) {
                        parts.append(.init(type: "input_image", text: nil, imageURL: imageURL))
                    }
                case "tool_result":
                    flushMessage()
                    let output = toolResultString(block.content)
                    items.append(
                        .init(
                            type: "function_call_output",
                            role: nil,
                            content: nil,
                            callId: block.toolUseId,
                            name: nil,
                            arguments: nil,
                            output: block.isError == true ? "[tool execution error]\n\(output)" : output
                        )
                    )
                default:
                    continue
                }
            }

            flushMessage()
            return items
        }

        var items: [ClaudeCompatResponsesRequest.InputItem] = []
        var parts: [ClaudeCompatResponsesRequest.ContentPart] = []

        func flushAssistant() {
            guard !parts.isEmpty else { return }
            items.append(.init(type: "message", role: "assistant", content: parts, callId: nil, name: nil, arguments: nil, output: nil))
            parts.removeAll(keepingCapacity: true)
        }

        for block in blocks {
            switch block.type {
            case "text":
                if let text = block.text {
                    parts.append(.init(type: "output_text", text: text, imageURL: nil))
                }
            case "tool_use":
                flushAssistant()
                let args = block.input.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) } ?? "{}"
                items.append(.init(type: "function_call", role: nil, content: nil, callId: block.id, name: block.name, arguments: args, output: nil))
            default:
                continue
            }
        }

        flushAssistant()
        return items
    }

    private func imageURL(for source: ClaudeCompatAnthropicRequest.ImageSource?) -> String? {
        guard let source else { return nil }
        if source.type == "url" {
            return source.url
        }
        if source.type == "base64",
           let mediaType = source.mediaType,
           let data = source.data {
            return "data:\(mediaType);base64,\(data)"
        }
        return nil
    }

    private func toolResultString(_ content: ClaudeCompatAnthropicRequest.ToolResultContent?) -> String {
        guard let content else { return "" }
        switch content {
        case .string(let text):
            return text
        case .blocks(let blocks):
            return blocks.compactMap { block in
                switch block.type {
                case "text":
                    return block.text ?? ""
                case "image":
                    let mediaType = block.source?.mediaType ?? "image"
                    return "[image omitted: \(mediaType)]"
                default:
                    return nil
                }
            }.joined(separator: "\n")
        }
    }

    private func approximateInputTokens(for request: ClaudeCompatAnthropicRequest) -> Int {
        var total = 0

        if let systemText = request.system?.text {
            total += tokenEstimate(for: systemText)
        }

        for message in request.messages {
            for block in message.content.blocks {
                switch block.type {
                case "text":
                    total += tokenEstimate(for: block.text ?? "")
                case "tool_use":
                    total += tokenEstimate(for: block.name ?? "")
                    if let input = block.input,
                       let data = try? JSONEncoder().encode(input),
                       let text = String(data: data, encoding: .utf8) {
                        total += tokenEstimate(for: text)
                    }
                case "tool_result":
                    total += tokenEstimate(for: toolResultString(block.content))
                default:
                    continue
                }
            }
        }

        for tool in request.tools ?? [] {
            total += tokenEstimate(for: tool.name)
            total += tokenEstimate(for: tool.description ?? "")
            if let data = try? JSONEncoder().encode(tool.inputSchema),
               let text = String(data: data, encoding: .utf8) {
                total += tokenEstimate(for: text)
            }
        }

        total += request.messages.count * 4
        return total
    }

    private func tokenEstimate(for text: String) -> Int {
        max(Int((Double(text.utf8.count) / 4.0).rounded(.up)), text.isEmpty ? 0 : 1)
    }

    private func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func parseUpstreamErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let object = json.objectValue
        else {
            return String(data: data, encoding: .utf8)
        }

        return object["error"]?.objectValue?["message"]?.stringValue
            ?? object["message"]?.stringValue
    }

    private func anthropicUsageObject(from usage: ClaudeCompatCodexUsage?) -> JSONValue {
        .object(
            anthropicUsageDictionary(from: usage).mapValues { .number(Double($0)) }
        )
    }

    private func anthropicUsageDictionary(from usage: ClaudeCompatCodexUsage?) -> [String: Int] {
        [
            "input_tokens": usage?.inputTokens ?? 0,
            "output_tokens": usage?.outputTokens ?? 0,
            "cache_creation_input_tokens": 0,
            "cache_read_input_tokens": usage?.cachedTokens ?? 0
        ]
    }

    private func encodeSSE(event: String, payload: [String: JSONValue]) -> Data {
        let data = (try? JSONEncoder().encode(JSONValue.object(payload))) ?? Data("{}".utf8)
        let payloadString = String(data: data, encoding: .utf8) ?? "{}"
        return Data("event: \(event)\ndata: \(payloadString)\n\n".utf8)
    }

    private func updateState(for accountID: String, from error: ClaudeCompatUpstreamStreamError) {
        switch error.kind {
        case .rateLimit:
            persistState(
                CodexAccountRouting.rateLimitedState(
                    retryAfter: error.retryAfterSeconds.map(TimeInterval.init),
                    message: error.message
                ),
                for: accountID
            )
        case .failed:
            persistState(
                CodexAccountState(status: .unavailable, resetAt: nil, updatedAt: Date(), message: error.message),
                for: accountID
            )
        }
    }

    private func persistState(_ state: CodexAccountState, for accountID: String) {
        stateQueue.async {
            self.accountStates[accountID] = state
        }
    }

    private func nextAccountContext(excluding excludedAccountIDs: Set<String>) -> ClaudeCompatAccountContext? {
        let now = Date()
        let normalizedStates = accountStates.mapValues { CodexAccountRouting.normalizedState($0, now: now) }
        let lastRoutedAccountId = UserDefaults.standard.string(forKey: lastRoutedAccountKey)
        let orderedIDs = CodexAccountRouting.orderedAccountIDs(
            accountIds: accounts.map(\.id),
            preferredAccountId: preferredAccountId,
            lastRoutedAccountId: lastRoutedAccountId,
            states: normalizedStates,
            excluding: excludedAccountIDs,
            now: now
        )

        for accountID in orderedIDs {
            guard let account = accounts.first(where: { $0.id == accountID }) else { continue }
            let chatGPTAccountId = account.chatGPTAccountId
                ?? decodeIDTokenClaims(from: account.idToken)?.chatGPTAccountID
                ?? decodeNestedAccountID(from: account.accessToken)

            guard let chatGPTAccountId, !chatGPTAccountId.isEmpty else { continue }

            return ClaudeCompatAccountContext(
                accountId: accountID,
                chatGPTAccountId: chatGPTAccountId,
                accessToken: account.accessToken
            )
        }

        return nil
    }

    private func recordSelectedAccount(_ accountID: String) {
        UserDefaults.standard.set(accountID, forKey: lastRoutedAccountKey)
        NotificationCenter.default.post(
            name: .codexActiveAccountSwitched,
            object: nil,
            userInfo: ["accountId": accountID]
        )
    }

    private func decodeNestedAccountID(from jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any],
              let accountID = auth["chatgpt_account_id"] as? String
        else { return nil }

        return accountID
    }

    private func decodeIDTokenClaims(from token: String?) -> ClaudeCompatIDTokenClaims? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }

        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONDecoder().decode(ClaudeCompatIDTokenClaims.self, from: data)
    }

    private func configure(channel: Channel) -> EventLoopFuture<Void> {
        channel.pipeline.configureHTTPServerPipeline().flatMap {
            channel.pipeline.addHandler(ClaudeCompatHTTPProxyHandler(service: self))
        }
    }

    private func publishStatus(_ status: Status) {
        DispatchQueue.main.async {
            self.status = status
        }
    }
}

private final class ClaudeCompatHTTPProxyHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let service: ClaudeCompatProxyService
    private var requestHead: HTTPRequestHead?
    private var requestBody = Data()
    private var requestID = UUID().uuidString

    init(service: ClaudeCompatProxyService) {
        self.service = service
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            requestBody.removeAll(keepingCapacity: true)
            requestID = String(UUID().uuidString.prefix(8))
        case .body(var buffer):
            if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                requestBody.append(contentsOf: bytes)
            }
        case .end:
            guard let requestHead else {
                writeError(status: .badRequest, message: "Missing request head", context: context)
                return
            }

            let headers = requestHead.headers.map { ($0.name, $0.value) }
            let method = requestHead.method.rawValue
            let uri = requestHead.uri
            let body = requestBody

            Task {
                do {
                    let result = try await self.service.handleRequest(
                        requestID: self.requestID,
                        method: method,
                        uri: uri,
                        headers: headers,
                        body: body
                    )

                    context.eventLoop.execute {
                        switch result {
                        case .response(let response):
                            self.write(response: response, requestVersion: requestHead.version, context: context)
                        case .stream(let stream):
                            self.writeStreamHead(stream: stream, requestVersion: requestHead.version, context: context)
                            Task {
                                do {
                                    try await stream.relay { chunk in
                                        context.eventLoop.execute {
                                            self.writeStreamChunk(chunk, context: context)
                                        }
                                    }
                                } catch {
                                    ClaudeCompatDiagnostics.shared.error(
                                        "Stream relay write error",
                                        requestID: self.requestID,
                                        metadata: ["message": error.localizedDescription]
                                    )
                                    context.eventLoop.execute {
                                        self.writeStreamChunk(Data("event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"\(error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\""))\"}}\n\n".utf8), context: context)
                                    }
                                }
                                context.eventLoop.execute {
                                    self.finishStream(context: context)
                                }
                            }
                        }
                    }
                } catch let error as ClaudeCompatProxyError {
                    ClaudeCompatDiagnostics.shared.warning(
                        "Proxy request failed",
                        requestID: self.requestID,
                        metadata: ["error": String(describing: error)]
                    )
                    context.eventLoop.execute {
                        switch error {
                        case .missingActiveAccount:
                            self.writeError(status: .unauthorized, message: "No active ChatGPT account", context: context)
                        case .invalidPath:
                            self.writeError(status: .notFound, message: "Unsupported proxy path", context: context)
                        case .modelNotAllowed(let model):
                            self.writeError(status: .badRequest, message: "Model not allowed: \(model)", context: context)
                        case .invalidJSON:
                            self.writeError(status: .badRequest, message: "Invalid JSON request", context: context)
                        case .invalidResponse:
                            self.writeError(status: .badGateway, message: "Invalid upstream response", context: context)
                        }
                    }
                } catch let error as ClaudeCompatUpstreamError {
                    ClaudeCompatDiagnostics.shared.warning(
                        "Upstream request failed",
                        requestID: self.requestID,
                        metadata: [
                            "statusCode": error.statusCode,
                            "message": error.message,
                            "retryAfter": error.retryAfter ?? "-"
                        ]
                    )
                    context.eventLoop.execute {
                        self.writeJSONError(
                            status: HTTPResponseStatus(statusCode: error.statusCode),
                            type: error.statusCode == 429 ? "rate_limit_error" : (error.statusCode == 401 || error.statusCode == 403 ? "authentication_error" : "api_error"),
                            message: error.message,
                            retryAfter: error.retryAfter,
                            context: context
                        )
                    }
                } catch {
                    ClaudeCompatDiagnostics.shared.error(
                        "Unhandled proxy error",
                        requestID: self.requestID,
                        metadata: ["message": error.localizedDescription]
                    )
                    context.eventLoop.execute {
                        self.writeError(status: .badGateway, message: error.localizedDescription, context: context)
                    }
                }
            }
        }
    }

    private func write(
        response: ClaudeCompatProxyResponse,
        requestVersion: HTTPVersion,
        context: ChannelHandlerContext
    ) {
        var head = HTTPResponseHead(
            version: requestVersion,
            status: HTTPResponseStatus(statusCode: response.statusCode, reasonPhrase: response.reasonPhrase)
        )
        for (name, value) in response.headers where !name.lowercased().hasPrefix("transfer-encoding") {
            head.headers.add(name: name, value: value)
        }
        head.headers.replaceOrAdd(name: "Content-Length", value: "\(response.body.count)")
        head.headers.replaceOrAdd(name: "Connection", value: "close")

        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: response.body.count)
        buffer.writeBytes(response.body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private func writeStreamHead(
        stream: ClaudeCompatSSEStream,
        requestVersion: HTTPVersion,
        context: ChannelHandlerContext
    ) {
        var head = HTTPResponseHead(
            version: requestVersion,
            status: HTTPResponseStatus(statusCode: stream.statusCode, reasonPhrase: stream.reasonPhrase)
        )
        for (name, value) in stream.headers {
            head.headers.replaceOrAdd(name: name, value: value)
        }
        head.headers.replaceOrAdd(name: "Transfer-Encoding", value: "chunked")
        context.writeAndFlush(wrapOutboundOut(.head(head)), promise: nil)
    }

    private func writeStreamChunk(_ data: Data, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
    }

    private func finishStream(context: ChannelHandlerContext) {
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private func writeJSONError(
        status: HTTPResponseStatus,
        type: String,
        message: String,
        retryAfter: String?,
        context: ChannelHandlerContext
    ) {
        let payload = """
        {"type":"error","error":{"type":"\(type)","message":"\(message.replacingOccurrences(of: "\"", with: "\\\""))"}}
        """
        let body = Data(payload.utf8)
        var head = HTTPResponseHead(version: .http1_1, status: status)
        head.headers.add(name: "Content-Type", value: "application/json")
        head.headers.add(name: "Content-Length", value: "\(body.count)")
        head.headers.add(name: "Connection", value: "close")
        if let retryAfter {
            head.headers.add(name: "Retry-After", value: retryAfter)
        }

        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private func writeError(status: HTTPResponseStatus, message: String, context: ChannelHandlerContext) {
        let body = Data(message.utf8)
        var head = HTTPResponseHead(version: .http1_1, status: status)
        head.headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        head.headers.add(name: "Content-Length", value: "\(body.count)")
        head.headers.add(name: "Connection", value: "close")

        context.write(wrapOutboundOut(.head(head)), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}
