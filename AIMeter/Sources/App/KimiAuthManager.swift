import Foundation
import WebKit
import AppKit
import SwiftUI

// MARK: - KimiAuthManager

@MainActor
final class KimiAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoggingIn = false
    @Published var lastError: String?
    @Published var userName: String?
    @Published var planName: String?

    private(set) var jwtToken: String?
    private(set) var userId: String?

    init() {
        loadCredentials()
    }

    // MARK: - Credential Storage

    private func loadCredentials() {
        jwtToken = KimiSessionKeychain.read(account: .jwtToken)
        userId = KimiSessionKeychain.read(account: .userId)
        userName = KimiSessionKeychain.read(account: .userName)
        planName = KimiSessionKeychain.read(account: .planName)
        isAuthenticated = jwtToken != nil
    }

    func saveCredentials(jwtToken: String, userId: String?, userName: String?, planName: String?) {
        KimiSessionKeychain.save(account: .jwtToken, value: jwtToken)
        if let userId { KimiSessionKeychain.save(account: .userId, value: userId) }
        if let userName { KimiSessionKeychain.save(account: .userName, value: userName) }
        if let planName { KimiSessionKeychain.save(account: .planName, value: planName) }
        self.jwtToken = jwtToken
        self.userId = userId
        self.userName = userName
        self.planName = planName
        self.isAuthenticated = true
        self.lastError = nil
    }

    func signOut() {
        KimiSessionKeychain.deleteAll()
        jwtToken = nil
        userId = nil
        userName = nil
        planName = nil
        isAuthenticated = false
        lastError = nil
    }

    func openLoginWindow() {
        isLoggingIn = true
        lastError = nil
        KimiLoginWindowManager.shared.openLoginWindow(authManager: self)
    }

    func loginCompleted() {
        isLoggingIn = false
    }

    func loginFailed(_ message: String) {
        isLoggingIn = false
        lastError = message
    }
}

// MARK: - KimiLoginWindowManager

@MainActor
final class KimiLoginWindowManager {
    static let shared = KimiLoginWindowManager()
    private var window: NSWindow?

    func openLoginWindow(authManager: KimiAuthManager) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let coordinator = KimiLoginCoordinator(authManager: authManager)
        let view = KimiLoginContentView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: view)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in to Kimi"
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

// MARK: - KimiLoginCoordinator

final class KimiLoginCoordinator: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum LoginState: Equatable {
        case loading
        case waitingForLogin
        case validating
        case success(name: String)
        case failed(message: String)
    }

    @Published var loginState: LoginState = .loading
    @Published var loadProgress: Double = 0

    let webView: WKWebView
    private weak var authManager: KimiAuthManager?
    private var cookieTimer: Timer?
    private var lastValidatedJWT: String?
    private var isValidatingJWT = false
    private var progressObservation: NSKeyValueObservation?
    private var popupWebView: WKWebView?
    private var popupWindow: NSWindow?

    private let blockedDomains: Set<String> = [
        "support.google.com", "support.apple.com", "help.apple.com"
    ]

    @MainActor
    init(authManager: KimiAuthManager) {
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
        guard let url = URL(string: "https://www.kimi.com/code/console") else { return }
        loginState = .loading
        webView.load(URLRequest(url: url))
    }

    func cleanup() {
        cookieTimer?.invalidate()
        cookieTimer = nil
        lastValidatedJWT = nil
        isValidatingJWT = false
        progressObservation = nil
        popupWindow?.close()
        popupWindow = nil
        popupWebView = nil
    }

    // MARK: - Cookie Monitoring

    private func startCookieMonitoring() {
        cookieTimer?.invalidate()
        cookieTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForAuthCookie()
        }
    }

    private func checkForAuthCookie() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            if let cookie = cookies.first(where: {
                $0.name == "kimi-auth" && $0.domain.contains("kimi.com")
            }) {
                let rawJwt = cookie.value
                let jwt = rawJwt.removingPercentEncoding ?? rawJwt
                DispatchQueue.main.async {
                    if self.isValidatingJWT { return }
                    if self.lastValidatedJWT == jwt { return }
                    self.cookieTimer?.invalidate()
                    self.cookieTimer = nil
                    self.validateJWT(jwt)
                }
            }
        }
    }

    private func validateJWT(_ jwt: String) {
        isValidatingJWT = true
        lastValidatedJWT = jwt
        loginState = .validating

        Task { @MainActor in
            // Validate by making a test request to GetUsages endpoint
            let url = URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
            request.timeoutInterval = 15
            let body: [String: Any] = ["scope": ["FEATURE_CODING"]]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let session = URLSession(configuration: .ephemeral)
                let (data, response) = try await session.data(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    loginState = .waitingForLogin
                    isValidatingJWT = false
                    startCookieMonitoring()
                    return
                }

                // Parse the response to extract user info if available
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Extract any available user/plan info from the response
                    // The response contains usage data but may not have explicit user info
                    authManager?.saveCredentials(
                        jwtToken: jwt,
                        userId: nil,
                        userName: nil,
                        planName: nil
                    )
                    isValidatingJWT = false
                    loginState = .success(name: "Kimi User")
                    try? await Task.sleep(for: .milliseconds(1500))
                    KimiLoginWindowManager.shared.closeLoginWindow()
                } else {
                    loginState = .waitingForLogin
                    isValidatingJWT = false
                    startCookieMonitoring()
                }
            } catch {
                loginState = .waitingForLogin
                isValidatingJWT = false
                startCookieMonitoring()
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
        DispatchQueue.main.async {
            if case .validating = self.loginState { return }
            if case .success = self.loginState { return }
            self.loginState = .waitingForLogin
            self.startCookieMonitoring()
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            if case .validating = self.loginState { return }
            self.loginState = .loading
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
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

// MARK: - KimiLoginContentView

struct KimiLoginContentView: View {
    @ObservedObject var coordinator: KimiLoginCoordinator

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
                statusRow(icon: "person.crop.circle", color: .orange, text: "Sign in to your Kimi account", spinner: false)
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill").font(.caption2).foregroundColor(.secondary)
                    Text("Your credentials stay on this device only")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        case .validating:
            statusRow(icon: "checkmark.shield.fill", color: .blue, text: "Verifying session...", spinner: true)
        case .success(let name):
            statusRow(icon: "checkmark.circle.fill", color: .green, text: "Signed in as \(name)", spinner: false)
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
