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
    private var callbackHandler: CodexOAuthCallbackHandler?

    // listen(state:) validates that the returned state matches the expected value.
    func listen(expectedState: String) async throws -> (code: String, state: String) {
        return try await withCheckedThrowingContinuation { continuation in
            // Capture so the handler can resume exactly once.
            let callbackHandler = CodexOAuthCallbackHandler(
                expectedState: expectedState,
                continuation: continuation
            )
            self.callbackHandler = callbackHandler

            let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            self.group = group

            let bootstrap = ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline(withErrorHandling: false)
                        .flatMap { channel.pipeline.addHandler(callbackHandler) }
                }
                .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 4)

            do {
                // Bind only loopback — never 0.0.0.0
                let channel = try bootstrap.bind(host: "127.0.0.1", port: Int(Self.callbackPort)).wait()
                self.serverChannel = channel
                logger.info("oauth.callback_server.bound port=\(Self.callbackPort, privacy: .public)")
            } catch {
                logger.error("oauth.callback_server.bind_failed error=\(error.localizedDescription, privacy: .public)")
                try? group.syncShutdownGracefully()
                self.group = nil
                // Heuristic: bind failure most likely means port is already in use.
                continuation.resume(throwing: CodexOAuthError.portInUse)
                return
            }

            // 5-minute timeout — cancel the continuation and shut down.
            let capturedSelf = self
            let capturedContinuation = continuation
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeoutSeconds) {
                // Only fires if handler hasn't already resumed.
                if callbackHandler.markTimedOut() {
                    logger.warning("oauth.callback_server.timeout")
                    capturedSelf.shutdown()
                    capturedContinuation.resume(throwing: CodexOAuthError.callbackTimeout)
                }
            }
        }
    }

    /// Cancel a pending listen: resumes the waiting continuation with `.cancelled`,
    /// then closes the NIO channel so port 1455 is freed immediately.
    func stop() async {
        if let handler = callbackHandler, handler.markCancelled() {
            handler.resumeWithCancellation()
        }
        callbackHandler = nil
        // Close synchronously so port 1455 is released before this returns.
        try? serverChannel?.close().wait()
        serverChannel = nil
        try? group?.syncShutdownGracefully()
        group = nil
    }

    func shutdown() {
        try? serverChannel?.close().wait()
        serverChannel = nil
        try? group?.syncShutdownGracefully()
        group = nil
        callbackHandler = nil
    }
}

// MARK: - CodexOAuthCallbackHandler

// Handles a single inbound HTTP request. After writing the response it
// resumes the continuation and closes the channel — one-shot lifecycle.
private final class CodexOAuthCallbackHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let expectedState: String
    private let continuation: CheckedContinuation<(code: String, state: String), Error>

    // Guards against double-resume from timeout racing with callback receipt.
    private var lock = NSLock()
    private var resumed = false

    init(
        expectedState: String,
        continuation: CheckedContinuation<(code: String, state: String), Error>
    ) {
        self.expectedState = expectedState
        self.continuation = continuation
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

    // Resumes the continuation with .cancelled — called only after markCancelled() succeeds.
    func resumeWithCancellation() {
        continuation.resume(throwing: CodexOAuthError.cancelled)
    }

    // Called by the timeout path to signal that we already resumed.
    private func tryResume(with result: Result<(code: String, state: String), Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
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

        if tryResume(with: .success((code: code, state: state))) {
            continuation.resume(returning: (code: code, state: state))
            // Close this channel after writing response; the server shuts down in the caller.
            context.channel.close(promise: nil)
        }
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
