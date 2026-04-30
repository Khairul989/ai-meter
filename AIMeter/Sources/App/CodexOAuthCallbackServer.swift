import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import OSLog

private let logger = Logger(subsystem: AppConstants.bundleId, category: "CodexOAuth")

// MARK: - CodexOAuthCallbackServer
//
// One-shot local HTTP listener on 127.0.0.1:1455.
// Binds, waits for a single GET /auth/callback?code=&state=, returns
// (code, state), then shuts down. Never binds 0.0.0.0.

final class CodexOAuthCallbackServer {
    private static let callbackPort: UInt16 = 1455
    private static let callbackPath = "/auth/callback"
    private static let timeoutSeconds: TimeInterval = 5 * 60

    private var group: MultiThreadedEventLoopGroup?
    private var serverChannel: Channel?
    // Retained so stop() can signal the handler's continuation with .cancelled.
    private var pendingHandler: CodexOAuthCallbackHandler?
    // Fix 3: tracks whether stop() was called so awaitCallback can throw .cancelled.
    private var didCancel = false

    /// Binds `127.0.0.1:1455` and returns once the port is accepting connections.
    /// Must be called before `awaitCallback(expectedState:)`.
    func bind(expectedState: String) async throws {
        // Fix 3: reset cancel flag on each fresh bind.
        didCancel = false

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        // Fix 1: construct handler before bind so requests arriving immediately are buffered.
        let handler = CodexOAuthCallbackHandler(expectedState: expectedState)
        self.pendingHandler = handler

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [handler] channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: false)
                    .flatMap { channel.pipeline.addHandler(handler) }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 4)

        do {
            // Fix 2: use async .get() instead of blocking .wait() inside an async function.
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: Int(Self.callbackPort)).get()
            self.serverChannel = channel
            logger.info("oauth.callback_server.bound port=\(Self.callbackPort, privacy: .public)")
        } catch {
            logger.error("oauth.callback_server.bind_failed error=\(error.localizedDescription, privacy: .public)")
            try? group.syncShutdownGracefully()
            self.group = nil
            self.pendingHandler = nil
            if let ioError = error as? IOError, ioError.errnoCode == EADDRINUSE {
                throw CodexOAuthError.portInUse
            }
            throw CodexOAuthError.callbackServerBindFailed(underlying: error)
        }
    }

    /// Waits for a single GET /auth/callback, validates state, and returns (code, state).
    /// Requires `bind(expectedState:)` to have completed successfully first.
    func awaitCallback(expectedState: String) async throws -> (code: String, state: String) {
        // Fix 3: check cancellation before checking channel.
        if didCancel {
            throw CodexOAuthError.cancelled
        }
        guard let handler = pendingHandler, serverChannel != nil else {
            throw CodexOAuthError.invalidTokenResponse
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Fix 1: wire the pre-built handler with the continuation.
            // If a request already arrived and buffered a result, wire() drains it immediately.
            handler.wire(continuation: continuation)

            let capturedSelf = self
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutSeconds) {
                if handler.markTimedOut() {
                    logger.warning("oauth.callback_server.timeout")
                    capturedSelf.shutdown()
                    handler.resumeWithError(CodexOAuthError.callbackTimeout)
                }
            }
        }
    }

    // listen(expectedState:) validates that the returned state matches the expected value.
    func listen(expectedState: String) async throws -> (code: String, state: String) {
        try await bind(expectedState: expectedState)
        return try await awaitCallback(expectedState: expectedState)
    }

    /// Cancel a pending listen: resumes the waiting continuation with `.cancelled`,
    /// then closes the NIO channel so port 1455 is freed immediately.
    func stop() async {
        // Fix 3: set didCancel before nilling so awaitCallback sees .cancelled.
        didCancel = true
        if let handler = pendingHandler, handler.markCancelled() {
            handler.resumeWithError(CodexOAuthError.cancelled)
        }
        pendingHandler = nil
        // Fix 2: use async close/shutdown to avoid blocking the caller's actor.
        try? await serverChannel?.close().get()
        serverChannel = nil
        try? await group?.shutdownGracefully()
        group = nil
    }

    func shutdown() {
        try? serverChannel?.close().wait()
        serverChannel = nil
        try? group?.syncShutdownGracefully()
        group = nil
        pendingHandler = nil
    }
}

// MARK: - CodexOAuthCallbackHandler

// Handles a single inbound HTTP request. After writing the response it
// resumes the continuation and closes the channel — one-shot lifecycle.
private final class CodexOAuthCallbackHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let expectedState: String
    private var continuation: CheckedContinuation<(code: String, state: String), Error>?

    // Guards against double-resume from timeout racing with callback receipt.
    private var lock = NSLock()
    private var resumed = false
    // Fix 1: buffers a result that arrives before wire() is called.
    private var bufferedResult: Result<(code: String, state: String), Error>?

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    // Fix 1: called from awaitCallback to provide the continuation.
    // If a result already arrived and was buffered, drains it immediately.
    func wire(continuation: CheckedContinuation<(code: String, state: String), Error>) {
        lock.lock()
        if resumed {
            // Cancelled/timed-out before wire() was called.
            // bufferedResult may already hold the error (resumeWithError ran),
            // or resumeWithError is racing and will arrive shortly — stash
            // the continuation so it can deliver directly.
            let result = bufferedResult
            if result != nil {
                bufferedResult = nil
                lock.unlock()
                switch result! {
                case .success(let value): continuation.resume(returning: value)
                case .failure(let error): continuation.resume(throwing: error)
                }
            } else {
                self.continuation = continuation
                lock.unlock()
            }
            return
        }
        let captured = bufferedResult
        if captured != nil {
            bufferedResult = nil
            resumed = true
        } else {
            self.continuation = continuation
        }
        lock.unlock()
        if let result = captured {
            switch result {
            case .success(let value): continuation.resume(returning: value)
            case .failure(let error): continuation.resume(throwing: error)
            }
        }
    }

    // Returns true if this call atomically transitions to "timed out".
    func markTimedOut() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }

    // Returns true if this call atomically transitions to "cancelled".
    func markCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }

    // Resumes the continuation (or buffers the error if not yet wired).
    func resumeWithError(_ error: Error) {
        lock.lock()
        let c = continuation
        if c != nil {
            continuation = nil
        } else {
            bufferedResult = .failure(error)
        }
        lock.unlock()
        c?.resume(throwing: error)
    }

    private func deliver(_ result: Result<(code: String, state: String), Error>) {
        lock.lock()
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        let c = continuation
        if c != nil {
            continuation = nil
        } else {
            bufferedResult = result
        }
        lock.unlock()
        if let c {
            switch result {
            case .success(let value): c.resume(returning: value)
            case .failure(let error): c.resume(throwing: error)
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        guard case .head(let head) = part else { return }
        guard head.method == .GET else {
            respond(context: context, status: .notFound, body: "Not found")
            return
        }

        // Parse query string from the request URI (e.g. "/auth/callback?code=…&state=…")
        guard let urlComponents = URLComponents(string: "http://localhost\(head.uri)"),
              urlComponents.path == "/auth/callback" else {
            respond(context: context, status: .notFound, body: "Not found")
            return
        }

        let items = urlComponents.queryItems ?? []
        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value

        guard let code, let state else {
            respond(context: context, status: .badRequest, body: "Missing code or state parameter")
            return
        }

        guard state == expectedState else {
            respond(context: context, status: .badRequest, body: "State mismatch — possible CSRF")
            return
        }

        logger.info("oauth.callback.received code_length=\(code.count, privacy: .public)")

        let html = """
        <html><body style="font-family:system-ui;text-align:center;padding:40px">
        <h1>Authorization Successful</h1>
        <p>You can close this window and return to AIMeter.</p>
        </body></html>
        """
        respond(context: context, status: .ok, body: html, contentType: "text/html; charset=utf-8")

        deliver(.success((code: code, state: state)))
        // Close this channel after writing response; the server shuts down in the caller.
        context.channel.close(promise: nil)
    }

    private func respond(
        context: ChannelHandlerContext,
        status: HTTPResponseStatus,
        body: String,
        contentType: String = "text/plain; charset=utf-8"
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
