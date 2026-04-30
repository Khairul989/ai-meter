import Foundation
import WebKit
import AppKit
import SwiftUI
import Combine

// MARK: - CodexAccount

struct CodexAccount: Identifiable, Equatable {
    let id: String        // email (unique identifier)
    let accessToken: String
    let idToken: String?
    let refreshToken: String?
    let expiresAt: Date?
    let email: String
    let planType: String?
    let chatGPTAccountId: String?

    // OAuth PKCE upgrade fields — optional, fully backwards-compatible.
    // When present, CodexTokenWarden uses oauthAccessTokenExpiresAt to schedule
    // proactive refresh; oauthAccessToken is kept current by CodexOAuthService.
    var oauthRefreshToken: String?
    var oauthAccessToken: String?
    var oauthAccessTokenExpiresAt: Date?

    /// True when this account has a stored OAuth refresh token (has been "upgraded").
    var hasOAuthUpgrade: Bool { oauthRefreshToken != nil }

    var resolvedPlanType: String? {
        planType ?? CodexIDTokenClaims.decode(from: idToken)?.planType
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

// MARK: - CodexAuthManager

@MainActor
final class CodexAuthManager: ObservableObject {
    @Published var accounts: [CodexAccount] = []
    @Published var activeAccountId: String?
    @Published var isLoggingIn = false
    @Published var lastError: String?
    @Published private(set) var proxyStatus: CodexProxyService.Status = .stopped
    @Published private(set) var accountStates: [String: CodexAccountState] = [:]

    private let proxyService = CodexProxyService.shared
    private var cancellables = Set<AnyCancellable>()

    var activeAccount: CodexAccount? {
        accounts.first { $0.id == activeAccountId }
    }
    var isAuthenticated: Bool { activeAccount != nil }
    var accessToken: String? { activeAccount?.accessToken }
    var email: String? { activeAccount?.email }
    var planType: String? { activeAccount?.resolvedPlanType }
    var isProxyRunning: Bool { proxyStatus.isRunning }
    var isLoadBalancingAvailable: Bool { accounts.count > 1 }
    var activeAccountState: CodexAccountState? {
        guard let activeAccountId else { return nil }
        return accountStates[activeAccountId]
    }

    init() {
        bindProxyService()
        loadCredentials()
        if activeAccount != nil {
            ensureProxyRunning()
        }
    }

    // MARK: - Credential Storage

    private func loadCredentials() {
        // Migration: check for legacy un-namespaced keys
        if let legacyToken = CodexSessionKeychain.read(account: .accessToken) {
            let legacyEmail = CodexSessionKeychain.read(account: .email) ?? "Unknown"
            let legacyPlan = CodexSessionKeychain.read(account: .planType)
            // Save to namespaced keychain
            CodexSessionKeychain.save(account: .accessToken, accountId: legacyEmail, value: legacyToken)
            if let e = CodexSessionKeychain.read(account: .email) {
                CodexSessionKeychain.save(account: .email, accountId: legacyEmail, value: e)
            }
            if let p = legacyPlan {
                CodexSessionKeychain.save(account: .planType, accountId: legacyEmail, value: p)
            }
            CodexSessionKeychain.addAccountId(legacyEmail)
            // Delete legacy keys
            CodexSessionKeychain.deleteAll()
        }

        // Load all accounts
        let ids = CodexSessionKeychain.savedAccountIds()
        accounts = ids.compactMap { id in
            guard let token = CodexSessionKeychain.read(account: .accessToken, accountId: id) else { return nil }
            let email = CodexSessionKeychain.read(account: .email, accountId: id) ?? id
            let plan = CodexSessionKeychain.read(account: .planType, accountId: id)
            let idToken = CodexSessionKeychain.read(account: .idToken, accountId: id)
            let refreshToken = CodexSessionKeychain.read(account: .refreshToken, accountId: id)
            let expiresAt = CodexSessionKeychain.read(account: .expiresAt, accountId: id)
                .flatMap(CodexDateCodec.decode)
            let chatGPTAccountId = CodexSessionKeychain.read(account: .chatGPTAccountId, accountId: id)

            // Load OAuth upgrade fields — these may be absent if account hasn't been upgraded yet.
            let oauthRefreshToken = CodexSessionKeychain.read(account: .oauthRefreshToken, accountId: id)
            let oauthAccessToken: String?
            let oauthAccessTokenExpiresAt: Date?
            if let cacheJson = CodexSessionKeychain.read(account: .oauthAccessTokenCache, accountId: id),
               let cacheData = cacheJson.data(using: .utf8),
               let cache = try? JSONDecoder().decode(OAuthAccessTokenCache.self, from: cacheData) {
                oauthAccessToken = cache.token
                oauthAccessTokenExpiresAt = cache.expiresAt
            } else {
                oauthAccessToken = nil
                oauthAccessTokenExpiresAt = nil
            }

            var account = CodexAccount(
                id: id,
                accessToken: token,
                idToken: idToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                email: email,
                planType: plan,
                chatGPTAccountId: chatGPTAccountId
            )
            account.oauthRefreshToken = oauthRefreshToken
            account.oauthAccessToken = oauthAccessToken
            account.oauthAccessTokenExpiresAt = oauthAccessTokenExpiresAt
            return account
        }

        // Restore active account from UserDefaults, or pick first
        let savedActive = UserDefaults.standard.string(forKey: "codexActiveAccountId")
        if let saved = savedActive, accounts.contains(where: { $0.id == saved }) {
            activeAccountId = saved
        } else {
            activeAccountId = accounts.first?.id
        }

        accountStates = proxyService.accountStatesSnapshot()
        syncProxyAccounts()
    }

    func saveCredentials(
        accessToken: String,
        idToken: String?,
        refreshToken: String?,
        expiresAt: Date?,
        email: String?,
        planType: String?,
        chatGPTAccountId: String?
    ) {
        let claims = CodexIDTokenClaims.decode(from: idToken)
        let resolvedEmail = email ?? claims?.email
        let resolvedPlanType = planType ?? claims?.planType
        let accountId = resolvedEmail ?? "Unknown"
        CodexSessionKeychain.save(account: .accessToken, accountId: accountId, value: accessToken)
        if let resolvedEmail {
            CodexSessionKeychain.save(account: .email, accountId: accountId, value: resolvedEmail)
        } else {
            CodexSessionKeychain.delete(account: .email, accountId: accountId)
        }
        if let resolvedPlanType {
            CodexSessionKeychain.save(account: .planType, accountId: accountId, value: resolvedPlanType)
        } else {
            CodexSessionKeychain.delete(account: .planType, accountId: accountId)
        }
        if let idToken {
            CodexSessionKeychain.save(account: .idToken, accountId: accountId, value: idToken)
        } else {
            CodexSessionKeychain.delete(account: .idToken, accountId: accountId)
        }
        if let refreshToken {
            CodexSessionKeychain.save(account: .refreshToken, accountId: accountId, value: refreshToken)
        } else {
            CodexSessionKeychain.delete(account: .refreshToken, accountId: accountId)
        }
        if let expiresAt {
            CodexSessionKeychain.save(
                account: .expiresAt,
                accountId: accountId,
                value: CodexDateCodec.encode(expiresAt)
            )
        } else {
            CodexSessionKeychain.delete(account: .expiresAt, accountId: accountId)
        }
        if let chatGPTAccountId {
            CodexSessionKeychain.save(account: .chatGPTAccountId, accountId: accountId, value: chatGPTAccountId)
        } else {
            CodexSessionKeychain.delete(account: .chatGPTAccountId, accountId: accountId)
        }
        CodexSessionKeychain.addAccountId(accountId)

        // Preserve any existing OAuth upgrade fields — a web-session re-login must not
        // overwrite them (keychain entries survive, but we need the in-memory struct to match).
        let existingOAuthRefreshToken = CodexSessionKeychain.read(account: .oauthRefreshToken, accountId: accountId)
        let existingOAuthAccessToken: String?
        let existingOAuthAccessTokenExpiresAt: Date?
        if let cacheJson = CodexSessionKeychain.read(account: .oauthAccessTokenCache, accountId: accountId),
           let cacheData = cacheJson.data(using: .utf8),
           let cache = try? JSONDecoder().decode(OAuthAccessTokenCache.self, from: cacheData) {
            existingOAuthAccessToken = cache.token
            existingOAuthAccessTokenExpiresAt = cache.expiresAt
        } else {
            existingOAuthAccessToken = nil
            existingOAuthAccessTokenExpiresAt = nil
        }

        var account = CodexAccount(
            id: accountId,
            accessToken: accessToken,
            idToken: idToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            email: resolvedEmail ?? accountId,
            planType: resolvedPlanType,
            chatGPTAccountId: chatGPTAccountId
        )
        account.oauthRefreshToken = existingOAuthRefreshToken
        account.oauthAccessToken = existingOAuthAccessToken
        account.oauthAccessTokenExpiresAt = existingOAuthAccessTokenExpiresAt

        if let idx = accounts.firstIndex(where: { $0.id == accountId }) {
            accounts[idx] = account
        } else {
            accounts.append(account)
        }

        // Set as active if first account or no active
        if activeAccountId == nil || accounts.count == 1 {
            setActiveAccount(accountId)
        }
        syncProxyAccounts()
        ensureProxyRunning()
        self.lastError = nil
    }

    func signOut() {
        guard let id = activeAccountId else { return }
        signOut(accountId: id)
    }

    func signOut(accountId: String) {
        CodexSessionKeychain.deleteAll(accountId: accountId)
        CodexSessionKeychain.removeAccountId(accountId)
        accounts.removeAll { $0.id == accountId }
        if activeAccountId == accountId {
            activeAccountId = accounts.first?.id
            if let id = activeAccountId {
                UserDefaults.standard.set(id, forKey: "codexActiveAccountId")
            } else {
                UserDefaults.standard.removeObject(forKey: "codexActiveAccountId")
            }
        }
        if accounts.isEmpty {
            proxyService.stop()
        }
        syncProxyAccounts()
        lastError = nil
    }

    func setActiveAccount(_ id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        activeAccountId = id
        UserDefaults.standard.set(id, forKey: "codexActiveAccountId")
        syncProxyAccounts()
        ensureProxyRunning()
    }

    /// Re-reads keychain for a single account and publishes the updated struct.
    /// Called after OAuth upgrade or token revocation so the UI and proxy see the new state.
    func reloadAccount(id: String) {
        guard let token = CodexSessionKeychain.read(account: .accessToken, accountId: id) else { return }
        let email = CodexSessionKeychain.read(account: .email, accountId: id) ?? id
        let plan = CodexSessionKeychain.read(account: .planType, accountId: id)
        let idToken = CodexSessionKeychain.read(account: .idToken, accountId: id)
        let refreshToken = CodexSessionKeychain.read(account: .refreshToken, accountId: id)
        let expiresAt = CodexSessionKeychain.read(account: .expiresAt, accountId: id)
            .flatMap(CodexDateCodec.decode)
        let chatGPTAccountId = CodexSessionKeychain.read(account: .chatGPTAccountId, accountId: id)
        let oauthRefreshToken = CodexSessionKeychain.read(account: .oauthRefreshToken, accountId: id)
        let oauthAccessToken: String?
        let oauthAccessTokenExpiresAt: Date?
        if let cacheJson = CodexSessionKeychain.read(account: .oauthAccessTokenCache, accountId: id),
           let cacheData = cacheJson.data(using: .utf8),
           let cache = try? JSONDecoder().decode(OAuthAccessTokenCache.self, from: cacheData) {
            oauthAccessToken = cache.token
            oauthAccessTokenExpiresAt = cache.expiresAt
        } else {
            oauthAccessToken = nil
            oauthAccessTokenExpiresAt = nil
        }
        var updated = CodexAccount(
            id: id,
            accessToken: token,
            idToken: idToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            email: email,
            planType: plan,
            chatGPTAccountId: chatGPTAccountId
        )
        updated.oauthRefreshToken = oauthRefreshToken
        updated.oauthAccessToken = oauthAccessToken
        updated.oauthAccessTokenExpiresAt = oauthAccessTokenExpiresAt
        if let idx = accounts.firstIndex(where: { $0.id == id }) {
            accounts[idx] = updated
        }
        syncProxyAccounts()
    }

    func openLoginWindow() {
        isLoggingIn = true
        lastError = nil
        CodexLoginWindowManager.shared.openLoginWindow(authManager: self)
    }

    func loginCompleted() {
        isLoggingIn = false
    }

    func loginFailed(_ message: String) {
        isLoggingIn = false
        lastError = message
    }

    private func bindProxyService() {
        proxyStatus = proxyService.status
        accountStates = proxyService.accountStatesSnapshot()

        // Bootstrap: if the proxy previously auto-switched accounts, sync the UI on launch
        if let lastRouted = UserDefaults.standard.string(forKey: "codexProxyLastRoutedAccountId"),
           lastRouted != activeAccountId,
           accounts.contains(where: { $0.id == lastRouted }) {
            activeAccountId = lastRouted
            UserDefaults.standard.set(lastRouted, forKey: "codexActiveAccountId")
        }

        proxyService.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.proxyStatus = status
            }
            .store(in: &cancellables)

        proxyService.$accountStates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] states in
                self?.accountStates = states
            }
            .store(in: &cancellables)

        // Keep activeAccountId in sync when the proxy auto-switches accounts (load balancing)
        NotificationCenter.default.publisher(for: .codexActiveAccountSwitched)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let accountId = notification.userInfo?["accountId"] as? String,
                      accounts.contains(where: { $0.id == accountId }),
                      activeAccountId != accountId
                else { return }
                activeAccountId = accountId
                UserDefaults.standard.set(accountId, forKey: "codexActiveAccountId")
            }
            .store(in: &cancellables)
    }

    private func ensureProxyRunning() {
        guard activeAccount != nil else { return }
        proxyService.startIfNeeded()
    }

    private func syncProxyAccounts() {
        proxyService.setAccounts(accounts, preferredAccountId: activeAccountId)
    }
}

// MARK: - CodexLoginWindowManager

@MainActor
final class CodexLoginWindowManager {
    static let shared = CodexLoginWindowManager()
    private var window: NSWindow?

    func openLoginWindow(authManager: CodexAuthManager) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let coordinator = CodexLoginCoordinator(authManager: authManager)
        let view = CodexLoginContentView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: view)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in to ChatGPT"
        win.contentView = hostingView
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                coordinator.cleanup()
                authManager.loginCompleted()
                self?.window = nil
            }
        }

        window = win
    }

    func closeLoginWindow() {
        window?.close()
        window = nil
    }
}

// MARK: - CodexLoginCoordinator

final class CodexLoginCoordinator: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum LoginState: Equatable {
        case loading
        case waitingForLogin
        case validating
        case success(email: String)
        case failed(message: String)
    }

    @Published var loginState: LoginState = .loading
    @Published var loadProgress: Double = 0

    let webView: WKWebView
    private weak var authManager: CodexAuthManager?
    private var cookieTimer: Timer?
    private var progressObservation: NSKeyValueObservation?
    private var popupWebView: WKWebView?
    private var popupWindow: NSWindow?

    private let blockedDomains: Set<String> = [
        "support.google.com", "support.apple.com", "help.apple.com"
    ]

    @MainActor
    init(authManager: CodexAuthManager) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        self.webView = wv
        self.authManager = authManager
        super.init()
        wv.navigationDelegate = self
        wv.uiDelegate = self

        progressObservation = wv.observe(\.estimatedProgress) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.loadProgress = wv.estimatedProgress }
        }
    }

    @MainActor
    func loadLoginPage() {
        guard let url = URL(string: "https://chatgpt.com") else { return }
        loginState = .loading
        webView.load(URLRequest(url: url))
    }

    func cleanup() {
        cookieTimer?.invalidate()
        cookieTimer = nil
        progressObservation = nil
        popupWindow?.close()
        popupWindow = nil
        popupWebView = nil
    }

    // MARK: - Session Polling

    private func startSessionPolling() {
        cookieTimer?.invalidate()
        cookieTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkSession()
        }
    }

    /// Use JavaScript fetch to check /api/auth/session without navigating away from the page
    private func checkSession() {
        let js = """
        const r = await fetch('/api/auth/session', { credentials: 'include' });
        if (!r.ok) { return null; }
        const j = await r.json();
        return JSON.stringify({
          accessToken: j?.accessToken ?? null,
          sessionToken: j?.sessionToken ?? null,
          expires: j?.expires ?? null,
          user: { email: j?.user?.email ?? null },
          account: { id: j?.account?.id ?? null, planType: j?.account?.planType ?? null }
        });
        """
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            guard case .success(let value) = result,
                  let jsonString = value as? String,
                  let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["accessToken"] as? String else {
                return // Not logged in yet, keep polling
            }

            let userEmail = (json["user"] as? [String: Any])?["email"] as? String
            let account = json["account"] as? [String: Any]
            let sessionToken = json["sessionToken"] as? String
            let expiresAt = CodexDateCodec.date(fromSessionValue: json["expires"])
            let planType = account?["planType"] as? String
            let chatGPTAccountId = account?["id"] as? String

            DispatchQueue.main.async {
                self.cookieTimer?.invalidate()
                self.cookieTimer = nil
                self.loginState = .validating

                self.authManager?.saveCredentials(
                    accessToken: token,
                    idToken: token,
                    refreshToken: sessionToken,
                    expiresAt: expiresAt,
                    email: userEmail,
                    planType: planType,
                    chatGPTAccountId: chatGPTAccountId
                )
                self.loginState = .success(email: userEmail ?? "ChatGPT")

                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1500))
                    CodexLoginWindowManager.shared.closeLoginWindow()
                }
            }
        }
    }

    // MARK: - WKUIDelegate (popup handling for Google Sign-In)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = webView.customUserAgent
        popup.navigationDelegate = self
        popup.uiDelegate = self

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in with Google"
        win.contentView = popup
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)

        self.popupWebView = popup
        self.popupWindow = win
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popupWebView {
            popupWindow?.close()
            popupWindow = nil
            popupWebView = nil
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Only process navigation events from the main webview
        guard webView === self.webView else { return }
        DispatchQueue.main.async {
            if case .validating = self.loginState { return }
            if case .success = self.loginState { return }
            self.loginState = .waitingForLogin
            self.startSessionPolling()
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        DispatchQueue.main.async {
            if case .validating = self.loginState { return }
            if case .success = self.loginState { return }
            self.loginState = .loading
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        DispatchQueue.main.async {
            self.loginState = .failed(message: error.localizedDescription)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let host = navigationAction.request.url?.host?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        let blocked = blockedDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
        if blocked {
            if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}

private struct CodexIDTokenClaims: Decodable {
    let chatGPTAccountID: String?
    let email: String?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case chatGPTAccountID = "chatgpt_account_id"
        case email
        case planType = "plan_type"
    }

    static func decode(from token: String?) -> CodexIDTokenClaims? {
        guard let token else { return nil }
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONDecoder().decode(CodexIDTokenClaims.self, from: data)
    }
}


private enum CodexDateCodec {
    private static let formatter = ISO8601DateFormatter()

    static func encode(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func decode(_ string: String) -> Date? {
        formatter.date(from: string)
    }

    static func date(fromSessionValue value: Any?) -> Date? {
        switch value {
        case let timestamp as TimeInterval:
            return normalize(timestamp)
        case let timestamp as Double:
            return normalize(timestamp)
        case let timestamp as Int:
            return normalize(TimeInterval(timestamp))
        case let timestamp as Int64:
            return normalize(TimeInterval(timestamp))
        case let string as String:
            if let numeric = TimeInterval(string) {
                return normalize(numeric)
            }
            return formatter.date(from: string)
        default:
            return nil
        }
    }

    private static func normalize(_ timestamp: TimeInterval) -> Date {
        if timestamp > 10_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1000)
        }
        return Date(timeIntervalSince1970: timestamp)
    }
}

// MARK: - CodexLoginContentView

struct CodexLoginContentView: View {
    @ObservedObject var coordinator: CodexLoginCoordinator

    var body: some View {
        VStack(spacing: 0) {
            statusBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            WebViewWrapper(webView: coordinator.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if coordinator.loadProgress > 0 && coordinator.loadProgress < 1.0 {
                ProgressView(value: coordinator.loadProgress)
                    .progressViewStyle(.linear)
            }
        }
        .onAppear { coordinator.loadLoginPage() }
        .onDisappear { coordinator.cleanup() }
    }

    @ViewBuilder
    private var statusBar: some View {
        switch coordinator.loginState {
        case .loading:
            statusRow(icon: "globe", color: .blue, text: "Loading...", spinner: true)
        case .waitingForLogin:
            VStack(alignment: .leading, spacing: 4) {
                statusRow(icon: "person.crop.circle", color: .orange, text: "Sign in to your ChatGPT account", spinner: false)
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill").font(.caption2).foregroundColor(.secondary)
                    Text("Your credentials stay on this device only")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        case .validating:
            statusRow(icon: "checkmark.shield.fill", color: .blue, text: "Verifying session...", spinner: true)
        case .success(let email):
            statusRow(icon: "checkmark.circle.fill", color: .green, text: "Signed in as \(email)", spinner: false)
        case .failed(let msg):
            statusRow(icon: "exclamationmark.triangle.fill", color: .red, text: msg, spinner: false)
        }
    }

    private func statusRow(icon: String, color: Color, text: String, spinner: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).font(.subheadline)
            Spacer()
            if spinner { ProgressView().scaleEffect(0.7).frame(width: 16, height: 16) }
        }
    }
}
