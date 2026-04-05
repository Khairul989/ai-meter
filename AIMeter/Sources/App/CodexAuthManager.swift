import Foundation
import WebKit
import AppKit
import SwiftUI

// MARK: - CodexAccount

struct CodexAccount: Identifiable, Equatable {
    let id: String        // email (unique identifier)
    let accessToken: String
    let email: String
    let planType: String?
}

// MARK: - CodexAuthManager

@MainActor
final class CodexAuthManager: ObservableObject {
    @Published var accounts: [CodexAccount] = []
    @Published var activeAccountId: String?
    @Published var isLoggingIn = false
    @Published var lastError: String?

    var activeAccount: CodexAccount? {
        accounts.first { $0.id == activeAccountId }
    }
    var isAuthenticated: Bool { activeAccount != nil }
    var accessToken: String? { activeAccount?.accessToken }
    var email: String? { activeAccount?.email }
    var planType: String? { activeAccount?.planType }

    init() {
        loadCredentials()
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
            return CodexAccount(id: id, accessToken: token, email: email, planType: plan)
        }

        // Restore active account from UserDefaults, or pick first
        let savedActive = UserDefaults.standard.string(forKey: "codexActiveAccountId")
        if let saved = savedActive, accounts.contains(where: { $0.id == saved }) {
            activeAccountId = saved
        } else {
            activeAccountId = accounts.first?.id
        }
    }

    func saveCredentials(accessToken: String, email: String?, planType: String?) {
        let accountId = email ?? "Unknown"
        CodexSessionKeychain.save(account: .accessToken, accountId: accountId, value: accessToken)
        if let email { CodexSessionKeychain.save(account: .email, accountId: accountId, value: email) }
        if let planType { CodexSessionKeychain.save(account: .planType, accountId: accountId, value: planType) }
        CodexSessionKeychain.addAccountId(accountId)

        let account = CodexAccount(id: accountId, accessToken: accessToken, email: accountId, planType: planType)
        if let idx = accounts.firstIndex(where: { $0.id == accountId }) {
            accounts[idx] = account
        } else {
            accounts.append(account)
        }

        // Set as active if first account or no active
        if activeAccountId == nil || accounts.count == 1 {
            setActiveAccount(accountId)
        }
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
        lastError = nil
    }

    func setActiveAccount(_ id: String) {
        activeAccountId = id
        UserDefaults.standard.set(id, forKey: "codexActiveAccountId")
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
            coordinator.cleanup()
            authManager.loginCompleted()
            self?.window = nil
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
        const j = await r.json();
        return JSON.stringify(j);
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

            let userEmail: String?
            if let user = json["user"] as? [String: Any] {
                userEmail = user["email"] as? String
            } else {
                userEmail = nil
            }

            DispatchQueue.main.async {
                self.cookieTimer?.invalidate()
                self.cookieTimer = nil
                self.loginState = .validating

                self.authManager?.saveCredentials(accessToken: token, email: userEmail, planType: nil)
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
