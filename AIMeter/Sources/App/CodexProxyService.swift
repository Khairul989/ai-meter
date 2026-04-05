import Combine
import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

struct CodexAccountState: Codable, Equatable {
    enum Status: String, Codable {
        case ready
        case rateLimited
        case unauthorized
        case unavailable
    }

    let status: Status
    let resetAt: Date?
    let updatedAt: Date
    let message: String?
}

final class CodexProxyService: ObservableObject {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case failed(String)

        var isRunning: Bool {
            if case .running = self {
                return true
            }
            return false
        }

        var displayText: String {
            switch self {
            case .stopped:
                return "Stopped"
            case .starting:
                return "Starting"
            case .running:
                return "Running"
            case .failed:
                return "Stopped"
            }
        }
    }

    struct ActiveAccountContext {
        let accountId: String
        let chatGPTAccountId: String
        let accessToken: String
    }

    struct ForwardedResponse {
        let statusCode: Int
        let reasonPhrase: String
        let headers: [(String, String)]
        let body: Data
    }

    static let shared = CodexProxyService()

    @Published private(set) var status: Status = .stopped
    @Published private(set) var accountStates: [String: CodexAccountState]

    private let stateKey = "codexAccountStates"
    private let port = CodexProxyStore.defaultPort
    private let host = "127.0.0.1"
    private let strippedInboundHeaders: Set<String> = [
        "authorization",
        "chatgpt-account-id",
        "content-length",
        "connection",
        "host",
        "forwarded",
        "upgrade",
        "proxy-connection"
    ]
    private let stateQueue = DispatchQueue(label: "com.khairul.aimeter.codex-proxy.state")
    private let store = CodexProxyStore()
    private let urlSession: URLSession

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?
    private var starting = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let states = try? JSONDecoder.appDecoder.decode([String: CodexAccountState].self, from: data) {
            self.accountStates = states
        } else {
            self.accountStates = [:]
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        self.urlSession = URLSession(configuration: configuration)
    }

    func accountStatesSnapshot() -> [String: CodexAccountState] {
        stateQueue.sync { accountStates }
    }

    func startIfNeeded() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            guard self.serverChannel == nil, !self.starting else { return }
            self.starting = true
            self.publishStatus(.starting)

            do {
                try self.store.writeConfig(port: self.port)
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
        stateQueue.async { [weak self] in
            guard let self else { return }
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

    func setActiveAccount(_ account: CodexAccount?) {
        if let account {
            UserDefaults.standard.set(account.id, forKey: "codexActiveAccountId")
            // Validate account can work and set initial status
            if activeAccountContext() != nil {
                let state = CodexAccountState(status: .ready, resetAt: nil, updatedAt: Date(), message: nil)
                persistState(state, for: account.id)
            }
            startIfNeeded()
        }
    }

    func forwardHTTPRequest(
        method: String,
        uri: String,
        headers: [(String, String)],
        body: Data
    ) async throws -> ForwardedResponse {
        guard let context = activeAccountContext() else {
            throw ProxyError.missingActiveAccount
        }
        guard let upstreamURL = upstreamURL(for: uri, websocket: false) else {
            throw ProxyError.invalidPath
        }

        var request = URLRequest(url: upstreamURL)
        request.httpMethod = method
        request.httpBody = body.isEmpty ? nil : body
        request.timeoutInterval = 60

        for (name, value) in buildHTTPHeaders(from: headers, context: context) {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProxyError.invalidResponse
        }

        updateState(for: context.accountId, response: httpResponse, message: nil)

        let reason = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode).capitalized
        let responseHeaders = httpResponse.allHeaderFields.compactMap { key, value -> (String, String)? in
            guard let name = key as? String else { return nil }
            return (name, "\(value)")
        }

        return ForwardedResponse(
            statusCode: httpResponse.statusCode,
            reasonPhrase: reason,
            headers: responseHeaders,
            body: data
        )
    }

    func openUpstreamWebSocket(
        uri: String,
        headers: [(String, String)]
    ) throws -> (URLSessionWebSocketTask, ActiveAccountContext) {
        guard let context = activeAccountContext() else {
            throw ProxyError.missingActiveAccount
        }
        guard let upstreamURL = upstreamURL(for: uri, websocket: true) else {
            throw ProxyError.invalidPath
        }

        var request = URLRequest(url: upstreamURL)
        buildWebSocketHeaders(from: headers, context: context).forEach { name, value in
            request.setValue(value, forHTTPHeaderField: name)
        }

        let task = urlSession.webSocketTask(with: request)
        task.resume()
        return (task, context)
    }

    private static let httpProxyHandlerName = "aimeter.httpProxy"

    private func configure(channel: Channel) -> EventLoopFuture<Void> {
        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, head in
                guard head.uri.hasPrefix("/backend-api/codex/responses") else {
                    return channel.eventLoop.makeFailedFuture(ProxyError.invalidPath)
                }
                return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { channel, head in
                // Remove HTTPProxyHandler before adding WebSocket handler —
                // NIO only removes its own HTTP handlers during upgrade, not ours.
                channel.pipeline.removeHandler(name: Self.httpProxyHandlerName).flatMap {
                    channel.pipeline.addHandler(LocalWebSocketHandler(service: self, requestHead: head))
                }.flatMapError { _ in
                    channel.pipeline.addHandler(LocalWebSocketHandler(service: self, requestHead: head))
                }
            }
        )

        let config = NIOHTTPServerUpgradeConfiguration(
            upgraders: [upgrader],
            completionHandler: { _ in }
        )

        return channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: config).flatMap {
            channel.pipeline.addHandler(HTTPProxyHandler(service: self), name: Self.httpProxyHandlerName)
        }
    }

    private func publishStatus(_ status: Status) {
        DispatchQueue.main.async {
            self.status = status
        }
    }

    private func updateState(for accountId: String, response: HTTPURLResponse, message: String?) {
        let retryAfter = parseRetryAfter(response.value(forHTTPHeaderField: "retry-after"))
        let nextState: CodexAccountState

        switch response.statusCode {
        case 200 ..< 300:
            nextState = CodexAccountState(status: .ready, resetAt: nil, updatedAt: Date(), message: nil)
        case 401:
            nextState = CodexAccountState(status: .unauthorized, resetAt: nil, updatedAt: Date(), message: message)
        case 429:
            let resetAt = retryAfter.map { Date().addingTimeInterval($0) }
            nextState = CodexAccountState(
                status: .rateLimited,
                resetAt: resetAt,
                updatedAt: Date(),
                message: message ?? "Retry after \(Int(retryAfter ?? 0))s"
            )
        default:
            nextState = CodexAccountState(status: .unavailable, resetAt: nil, updatedAt: Date(), message: message)
        }

        persistState(nextState, for: accountId)
    }

    func recordWebSocketFailure(for accountId: String, message: String) {
        let state = CodexAccountState(status: .unavailable, resetAt: nil, updatedAt: Date(), message: message)
        persistState(state, for: accountId)
    }

    private func persistState(_ state: CodexAccountState, for accountId: String) {
        stateQueue.async {
            self.accountStates[accountId] = state
            if let encoded = try? JSONEncoder.appEncoder.encode(self.accountStates) {
                UserDefaults.standard.set(encoded, forKey: self.stateKey)
            }
            let snapshot = self.accountStates
            DispatchQueue.main.async {
                self.accountStates = snapshot
            }
        }
    }

    private func activeAccountContext() -> ActiveAccountContext? {
        guard let accountId = UserDefaults.standard.string(forKey: "codexActiveAccountId"),
              let accessToken = CodexSessionKeychain.read(account: .accessToken, accountId: accountId)
        else {
            return nil
        }

        // Try: keychain → idToken JWT (top-level) → accessToken JWT (nested)
        let chatGPTAccountId = CodexSessionKeychain.read(account: .chatGPTAccountId, accountId: accountId)
            ?? decodeIDTokenClaims(from: CodexSessionKeychain.read(account: .idToken, accountId: accountId))?.chatGPTAccountID
            ?? decodeNestedAccountId(from: accessToken)

        guard let chatGPTAccountId, !chatGPTAccountId.isEmpty else {
            return nil
        }

        return ActiveAccountContext(
            accountId: accountId,
            chatGPTAccountId: chatGPTAccountId,
            accessToken: accessToken
        )
    }

    private func upstreamURL(for uri: String, websocket: Bool) -> URL? {
        guard uri.hasPrefix("/backend-api/") else { return nil }
        let base = websocket ? "wss://chatgpt.com" : "https://chatgpt.com"
        return URL(string: "\(base)\(uri)")
    }

    private func buildHTTPHeaders(
        from headers: [(String, String)],
        context: ActiveAccountContext
    ) -> [(String, String)] {
        var filtered: [(String, String)] = headers.filter { !shouldStripInboundHeader($0.0) }
        filtered.append(("Authorization", "Bearer \(context.accessToken)"))
        filtered.append(("chatgpt-account-id", context.chatGPTAccountId))
        return filtered
    }

    private func buildWebSocketHeaders(
        from headers: [(String, String)],
        context: ActiveAccountContext
    ) -> [(String, String)] {
        var filtered = headers.filter { header in
            let lowercased = header.0.lowercased()
            if shouldStripInboundHeader(header.0) {
                return false
            }
            return !lowercased.hasPrefix("sec-websocket-")
        }
        filtered.append(("Authorization", "Bearer \(context.accessToken)"))
        filtered.append(("chatgpt-account-id", context.chatGPTAccountId))
        return filtered
    }

    private func shouldStripInboundHeader(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return strippedInboundHeaders.contains(lowercased) || lowercased.hasPrefix("x-forwarded-")
    }

    private func parseRetryAfter(_ rawValue: String?) -> TimeInterval? {
        guard let rawValue else { return nil }
        if let seconds = TimeInterval(rawValue) {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: rawValue) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    /// Decode chatgpt_account_id from access token where it's nested:
    /// { "https://api.openai.com/auth": { "chatgpt_account_id": "..." } }
    private func decodeNestedAccountId(from jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 { payload += String(repeating: "=", count: 4 - padding) }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = json["https://api.openai.com/auth"] as? [String: Any],
              let accountId = auth["chatgpt_account_id"] as? String
        else { return nil }

        return accountId
    }

    private func decodeIDTokenClaims(from token: String?) -> CodexProxyIDTokenClaims? {
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
        return try? JSONDecoder().decode(CodexProxyIDTokenClaims.self, from: data)
    }
}

private enum ProxyError: Error {
    case invalidPath
    case invalidResponse
    case missingActiveAccount
}

private struct CodexProxyIDTokenClaims: Decodable {
    let chatGPTAccountID: String?

    enum CodingKeys: String, CodingKey {
        case chatGPTAccountID = "chatgpt_account_id"
    }
}

private final class HTTPProxyHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let service: CodexProxyService
    private var requestHead: HTTPRequestHead?
    private var requestBody = Data()

    init(service: CodexProxyService) {
        self.service = service
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            requestBody.removeAll(keepingCapacity: true)
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
                    let response = try await self.service.forwardHTTPRequest(
                        method: method,
                        uri: uri,
                        headers: headers,
                        body: body
                    )
                    context.eventLoop.execute {
                        self.write(response: response, requestVersion: requestHead.version, context: context)
                    }
                } catch ProxyError.missingActiveAccount {
                    context.eventLoop.execute {
                        self.writeError(status: .unauthorized, message: "No active Codex account", context: context)
                    }
                } catch ProxyError.invalidPath {
                    context.eventLoop.execute {
                        self.writeError(status: .notFound, message: "Unsupported proxy path", context: context)
                    }
                } catch {
                    context.eventLoop.execute {
                        self.writeError(status: .badGateway, message: error.localizedDescription, context: context)
                    }
                }
            }
        }
    }

    private func write(
        response: CodexProxyService.ForwardedResponse,
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

private final class LocalWebSocketHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = WebSocketFrame

    private let service: CodexProxyService
    private let requestHead: HTTPRequestHead
    private var upstreamTask: URLSessionWebSocketTask?
    private var accountContext: CodexProxyService.ActiveAccountContext?
    private var didClose = false

    init(service: CodexProxyService, requestHead: HTTPRequestHead) {
        self.service = service
        self.requestHead = requestHead
    }

    func handlerAdded(context: ChannelHandlerContext) {
        do {
            let headers = requestHead.headers.map { ($0.name, $0.value) }
            let (task, accountContext) = try service.openUpstreamWebSocket(uri: requestHead.uri, headers: headers)
            self.upstreamTask = task
            self.accountContext = accountContext
            receiveFromUpstream(context: context, task: task)
        } catch {
            close(context: context, code: .policyViolation)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        guard let upstreamTask else { return }

        switch frame.opcode {
        case .connectionClose:
            didClose = true
            let closeCode = parseCloseCode(from: frame) ?? .normalClosure
            upstreamTask.cancel(with: closeCode, reason: nil)
            close(context: context, code: closeCode)
        case .ping:
            writeFrame(opcode: .pong, payload: frame.unmaskedData.dataValue, context: context)
        case .pong:
            break
        case .text:
            Task {
                let text = String(decoding: frame.unmaskedData.dataValue, as: UTF8.self)
                do {
                    try await upstreamTask.send(.string(text))
                } catch {
                    if let accountId = accountContext?.accountId {
                        service.recordWebSocketFailure(for: accountId, message: error.localizedDescription)
                    }
                    context.eventLoop.execute {
                        self.close(context: context, code: .internalServerError)
                    }
                }
            }
        case .binary:
            Task {
                do {
                    try await upstreamTask.send(.data(frame.unmaskedData.dataValue))
                } catch {
                    if let accountId = accountContext?.accountId {
                        service.recordWebSocketFailure(for: accountId, message: error.localizedDescription)
                    }
                    context.eventLoop.execute {
                        self.close(context: context, code: .internalServerError)
                    }
                }
            }
        default:
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        upstreamTask?.cancel(with: .goingAway, reason: nil)
        upstreamTask = nil
    }

    private func receiveFromUpstream(context: ChannelHandlerContext, task: URLSessionWebSocketTask) {
        Task {
            do {
                while !Task.isCancelled {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        context.eventLoop.execute {
                            self.writeFrame(opcode: .text, payload: Data(text.utf8), context: context)
                        }
                    case .data(let data):
                        context.eventLoop.execute {
                            self.writeFrame(opcode: .binary, payload: data, context: context)
                        }
                    @unknown default:
                        context.eventLoop.execute {
                            self.close(context: context, code: .internalServerError)
                        }
                    }
                }
            } catch {
                if let accountId = accountContext?.accountId {
                    service.recordWebSocketFailure(for: accountId, message: error.localizedDescription)
                }
                context.eventLoop.execute {
                    let closeCode = task.closeCode == .invalid ? URLSessionWebSocketTask.CloseCode.internalServerError : task.closeCode
                    self.close(context: context, code: closeCode)
                }
            }
        }
    }

    private func close(context: ChannelHandlerContext, code: URLSessionWebSocketTask.CloseCode) {
        guard !didClose else { return }
        didClose = true

        var buffer = context.channel.allocator.buffer(capacity: 2)
        buffer.writeInteger(UInt16(code.rawValue).bigEndian)
        let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: buffer)
        context.writeAndFlush(NIOAny(frame)).whenComplete { _ in
            context.close(promise: nil)
        }
    }

    private func writeFrame(opcode: WebSocketOpcode, payload: Data, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: payload.count)
        buffer.writeBytes(payload)
        let frame = WebSocketFrame(fin: true, opcode: opcode, data: buffer)
        context.writeAndFlush(NIOAny(frame), promise: nil)
    }

    private func parseCloseCode(from frame: WebSocketFrame) -> URLSessionWebSocketTask.CloseCode? {
        var buffer = frame.unmaskedData
        guard let rawCode = buffer.readInteger(as: UInt16.self) else { return nil }
        return URLSessionWebSocketTask.CloseCode(rawValue: Int(rawCode))
    }
}

private extension ByteBuffer {
    var dataValue: Data {
        var copy = self
        if let bytes: [UInt8] = copy.readBytes(length: copy.readableBytes) {
            return Data(bytes)
        }
        return Data()
    }
}

extension HTTPProxyHandler: @unchecked Sendable {}

extension LocalWebSocketHandler: @unchecked Sendable {}
