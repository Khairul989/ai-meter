import AppKit
import CryptoKit
import Foundation
import OSLog

private let logger = Logger(subsystem: AppConstants.bundleId, category: "CodexOAuth")

// MARK: - Constants
//
// client_id and redirect_uri are the Codex CLI's public OAuth client.
// OpenAI whitelists port 1455 for this client_id specifically — no other port works.
private enum OAuthConstants {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let issuer = "https://auth.openai.com"
    static let redirectURI = "http://localhost:1455/auth/callback"
    static let refreshMarginSeconds: TimeInterval = 5 * 60
}

// MARK: - CodexOAuthTokens

struct CodexOAuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let idToken: String
    let expiresAt: Date
    let chatGPTAccountID: String?
}

// MARK: - CodexOAuthError

enum CodexOAuthError: Error, LocalizedError {
    case portInUse
    case browserLaunchFailed
    case callbackTimeout
    case cancelled
    case stateMismatch
    case accountMismatch(expected: String, got: String?)
    case tokenExchangeFailed(status: Int, message: String)
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .portInUse:
            return "Port 1455 is in use by another process. Close it and try again."
        case .browserLaunchFailed:
            return "Failed to open the browser. Please try again."
        case .callbackTimeout:
            return "Sign-in timed out. Click Upgrade to try again."
        case .cancelled:
            return "Sign-in was cancelled."
        case .stateMismatch:
            return "Security check failed (state mismatch). Please try again."
        case .accountMismatch(let expected, let got):
            let gotDescription = got ?? "unknown"
            return "Signed in as \(gotDescription), expected \(expected). Please try again with the correct ChatGPT account."
        case .tokenExchangeFailed(let status, let message):
            return "Token exchange failed (HTTP \(status)): \(message)"
        case .invalidTokenResponse:
            return "The server returned an unexpected token response. Please try again."
        }
    }
}

// MARK: - CodexOAuthService

@MainActor
final class CodexOAuthService: ObservableObject {
    static let shared = CodexOAuthService()

    @Published private(set) var pendingLoginAccountID: String?
    @Published private(set) var lastError: String?

    // Single-flight guard: maps accountID -> in-flight refresh Task.
    // Safe without a separate actor because this class is @MainActor.
    private var inflightRefresh: [String: Task<CodexOAuthTokens, Error>] = [:]

    // Retained while a PKCE login is in progress so cancelPendingLogin() can stop it.
    private var pendingCallbackServer: CodexOAuthCallbackServer?

    private init() {}

    // MARK: - Cancellation

    /// Cancel an in-flight login: stops the local callback server, clears
    /// `pendingLoginAccountID`, and makes the pending `startLogin` call throw
    /// `CodexOAuthError.cancelled`. Safe to call even if no login is in flight.
    @MainActor
    func cancelPendingLogin() async {
        await pendingCallbackServer?.stop()
        // pendingCallbackServer and pendingLoginAccountID are cleared in startLogin's defer.
    }

    // MARK: - Public API

    /// Starts the PKCE login flow for the given account.
    /// Returns the full token set on success.
    /// If `expectedChatGPTAccountID` is non-nil, the signed-in account must match it.
    func startLogin(
        for accountID: String,
        expectedChatGPTAccountID: String?
    ) async throws -> CodexOAuthTokens {
        pendingLoginAccountID = accountID
        lastError = nil
        logger.info("oauth.login.started account=\(accountID, privacy: .public)")

        defer {
            pendingLoginAccountID = nil
            pendingCallbackServer = nil
        }

        // Step 1: Generate PKCE codes and state
        let verifier = generateCodeVerifier()
        let challenge = codeChallenge(for: verifier)
        let state = generateState()

        // Step 2: Build authorize URL and open browser
        let authorizeURL = buildAuthorizeURL(challenge: challenge, state: state)
        logger.info("oauth.login.browser_opened account=\(accountID, privacy: .public)")

        guard NSWorkspace.shared.open(authorizeURL) else {
            throw CodexOAuthError.browserLaunchFailed
        }

        // Step 3: Start local callback server and wait for redirect.
        // Keep a reference so cancelPendingLogin() can stop the server mid-flight.
        let server = CodexOAuthCallbackServer()
        pendingCallbackServer = server
        let (code, returnedState) = try await server.listen(expectedState: state)
        server.shutdown()

        // Step 4: Validate state (belt-and-suspenders; server already checks this)
        guard returnedState == state else {
            throw CodexOAuthError.stateMismatch
        }

        // Step 5: Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(code: code, verifier: verifier)
        logger.info(
            "oauth.token_exchange.success account=\(accountID, privacy: .public) expires=\(tokens.expiresAt, privacy: .public)"
        )

        // Step 6: Validate chatgpt_account_id if caller requires it
        if let expected = expectedChatGPTAccountID {
            guard tokens.chatGPTAccountID == expected else {
                logger.warning(
                    "oauth.login.account_mismatch expected=\(expected, privacy: .public) got=\(tokens.chatGPTAccountID ?? "nil", privacy: .public)"
                )
                throw CodexOAuthError.accountMismatch(expected: expected, got: tokens.chatGPTAccountID)
            }
        }

        // Step 7: Persist tokens to keychain
        saveTokens(tokens, for: accountID)

        return tokens
    }

    /// Returns a valid access token for the account, refreshing if within the margin window.
    /// Returns nil if the account has no OAuth credentials yet.
    func currentAccessToken(for accountID: String) async throws -> String? {
        guard hasOAuthTokens(for: accountID) else { return nil }

        // Check cached access token first
        if let cached = loadCachedAccessToken(for: accountID),
           cached.expiresAt > Date().addingTimeInterval(OAuthConstants.refreshMarginSeconds) {
            return cached.token
        }

        // Need a refresh — use single-flight to avoid concurrent calls hitting the token endpoint
        let task: Task<CodexOAuthTokens, Error>
        if let existing = inflightRefresh[accountID] {
            task = existing
        } else {
            let refreshTask = Task<CodexOAuthTokens, Error> { [weak self] in
                guard let self else { throw CodexOAuthError.invalidTokenResponse }
                return try await self.performRefresh(for: accountID)
            }
            inflightRefresh[accountID] = refreshTask
            task = refreshTask
        }

        do {
            let tokens = try await task.value
            inflightRefresh[accountID] = nil
            return tokens.accessToken
        } catch {
            inflightRefresh[accountID] = nil
            throw error
        }
    }

    /// Returns true if this account has a stored refresh token (OAuth upgrade present).
    func hasOAuthTokens(for accountID: String) -> Bool {
        CodexSessionKeychain.read(account: .oauthRefreshToken, accountId: accountID) != nil
    }

    /// Removes stored OAuth tokens from keychain (user-initiated or after double-401 failure).
    func revokeLocalTokens(for accountID: String) {
        CodexSessionKeychain.delete(account: .oauthRefreshToken, accountId: accountID)
        CodexSessionKeychain.delete(account: .oauthAccessTokenCache, accountId: accountID)
        logger.info("oauth.revoked_local account=\(accountID, privacy: .public)")
    }

    /// Force-refreshes the access token regardless of cached expiry.
    /// Uses the same single-flight guard as currentAccessToken to prevent concurrent refresh POSTs.
    /// Returns the fresh access token, or nil if this account has no OAuth credentials.
    /// Separate from currentAccessToken so the 401-retry path can force a refresh without
    /// bypassing the cached-token check in the normal hot path.
    func refreshAccessToken(for accountID: String) async throws -> String? {
        guard hasOAuthTokens(for: accountID) else { return nil }

        // Reuse the single-flight guard — if a refresh is already in flight, join it
        let task: Task<CodexOAuthTokens, Error>
        if let existing = inflightRefresh[accountID] {
            task = existing
        } else {
            let refreshTask = Task<CodexOAuthTokens, Error> { [weak self] in
                guard let self else { throw CodexOAuthError.invalidTokenResponse }
                return try await self.performRefresh(for: accountID)
            }
            inflightRefresh[accountID] = refreshTask
            task = refreshTask
        }

        do {
            let tokens = try await task.value
            inflightRefresh[accountID] = nil
            return tokens.accessToken
        } catch {
            inflightRefresh[accountID] = nil
            throw error
        }
    }

    // MARK: - PKCE Generation

    /// Generates a 43-char code verifier from the RFC 7636 unreserved set [A-Za-z0-9-._~].
    /// Uses SecRandomCopyBytes for cryptographic randomness.
    private func generateCodeVerifier() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: 43)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    /// Produces the S256 code challenge: base64url-no-padding(SHA256(verifier)).
    /// RFC 7636 §4.2 — test vector: verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    /// → challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM".
    private func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncodedString()
    }

    /// Generates a 32-byte random state value encoded as base64url-no-padding.
    private func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    // MARK: - URL Building

    private func buildAuthorizeURL(challenge: String, state: String) -> URL {
        var components = URLComponents(string: "\(OAuthConstants.issuer)/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: OAuthConstants.clientID),
            URLQueryItem(name: "redirect_uri", value: OAuthConstants.redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: "claude-codex-proxy"),
        ]
        return components.url!
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, verifier: String) async throws -> CodexOAuthTokens {
        let params: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthConstants.redirectURI,
            "client_id": OAuthConstants.clientID,
            "code_verifier": verifier,
        ]
        return try await postTokenRequest(params: params)
    }

    // MARK: - Refresh

    private func performRefresh(for accountID: String) async throws -> CodexOAuthTokens {
        guard let refreshToken = CodexSessionKeychain.read(
            account: .oauthRefreshToken,
            accountId: accountID
        ) else {
            throw CodexOAuthError.invalidTokenResponse
        }

        logger.info("oauth.refresh.started account=\(accountID, privacy: .public)")

        let params: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthConstants.clientID,
        ]

        do {
            let tokens = try await postTokenRequest(params: params)
            saveTokens(tokens, for: accountID)
            logger.info(
                "oauth.refresh.success account=\(accountID, privacy: .public) expires=\(tokens.expiresAt, privacy: .public)"
            )
            return tokens
        } catch {
            logger.error(
                "oauth.refresh.failure account=\(accountID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    // MARK: - Token HTTP POST

    private func postTokenRequest(params: [String: String]) async throws -> CodexOAuthTokens {
        guard let url = URL(string: "\(OAuthConstants.issuer)/oauth/token") else {
            throw CodexOAuthError.invalidTokenResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = params.map { k, v in
            "\(k.urlFormEncoded)=\(v.urlFormEncoded)"
        }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error(
                "oauth.token_exchange.failure status=\(httpResponse.statusCode, privacy: .public)"
            )
            throw CodexOAuthError.tokenExchangeFailed(
                status: httpResponse.statusCode,
                message: message
            )
        }

        guard let json = try? JSONDecoder().decode(OAuthTokenResponse.self, from: data) else {
            throw CodexOAuthError.invalidTokenResponse
        }

        let expiresAt = Date().addingTimeInterval(json.expiresIn > 0 ? TimeInterval(json.expiresIn) : 3600)
        let chatGPTAccountID = extractChatGPTAccountID(from: json.idToken ?? json.accessToken)

        return CodexOAuthTokens(
            accessToken: json.accessToken,
            refreshToken: json.refreshToken,
            idToken: json.idToken ?? "",
            expiresAt: expiresAt,
            chatGPTAccountID: chatGPTAccountID
        )
    }

    // MARK: - Keychain Storage

    private func saveTokens(_ tokens: CodexOAuthTokens, for accountID: String) {
        // Persist refresh token (long-lived credential)
        CodexSessionKeychain.save(
            account: .oauthRefreshToken,
            accountId: accountID,
            value: tokens.refreshToken
        )

        // Cache access token as a small JSON blob: { "token": "...", "expiresAt": "ISO8601" }
        // Storing expiresAt here avoids a separate keychain entry just for the date.
        let cacheEntry = AccessTokenCacheEntry(token: tokens.accessToken, expiresAt: tokens.expiresAt)
        if let encoded = try? JSONEncoder().encode(cacheEntry),
           let json = String(data: encoded, encoding: .utf8) {
            CodexSessionKeychain.save(
                account: .oauthAccessTokenCache,
                accountId: accountID,
                value: json
            )
        }
    }

    private func loadCachedAccessToken(for accountID: String) -> AccessTokenCacheEntry? {
        guard let json = CodexSessionKeychain.read(
            account: .oauthAccessTokenCache,
            accountId: accountID
        ),
              let data = json.data(using: .utf8)
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AccessTokenCacheEntry.self, from: data)
    }

    // MARK: - JWT / Account ID Extraction

    /// Mirrors reference `extractAccountIdFromClaims` in reference/src/auth/jwt.ts.
    /// Priority: chatgpt_account_id → nested auth object → literal-dot key → organizations[0].id.
    private func extractChatGPTAccountID(from token: String) -> String? {
        guard let claims = parseJWTPayload(token) else { return nil }

        // 1. Top-level chatgpt_account_id
        if let id = claims["chatgpt_account_id"] as? String { return id }

        // 2. Nested: https://api.openai.com/auth.chatgpt_account_id (nested object)
        if let nested = claims["https://api.openai.com/auth"] as? [String: Any],
           let id = nested["chatgpt_account_id"] as? String { return id }

        // 3. Literal-dot key: https://api.openai.com/auth.chatgpt_account_id
        if let id = claims["https://api.openai.com/auth.chatgpt_account_id"] as? String { return id }

        // 4. organizations[0].id
        if let orgs = claims["organizations"] as? [[String: Any]],
           let first = orgs.first,
           let id = first["id"] as? String { return id }

        return nil
    }

    private func parseJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        // base64url → standard base64 with padding
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 { payload += String(repeating: "=", count: 4 - remainder) }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return json
    }
}

// MARK: - Supporting Types

/// Wire format returned by the OpenAI token endpoint.
private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }
}

/// Access token cached in keychain as JSON: { "token": "…", "expiresAt": "ISO8601" }
private struct AccessTokenCacheEntry: Codable {
    let token: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case token, expiresAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        let iso = ISO8601DateFormatter()
        try container.encode(iso.string(from: expiresAt), forKey: .expiresAt)
    }

    init(token: String, expiresAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        let dateString = try container.decode(String.self, forKey: .expiresAt)
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .expiresAt, in: container,
                debugDescription: "Invalid ISO8601 date: \(dateString)"
            )
        }
        expiresAt = date
    }
}

// MARK: - Data Extension

private extension Data {
    /// base64url encoding without padding — used for PKCE challenge and state.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    /// Percent-encodes a string for use in application/x-www-form-urlencoded bodies.
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "+", with: "%2B")
            ?? self
    }
}
