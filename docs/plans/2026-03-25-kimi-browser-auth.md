# Kimi Browser Authentication Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add browser-based OAuth-style authentication for Kimi to access the `/GetUsages` endpoint using JWT tokens from web session cookies.

**Architecture:** Create a `KimiAuthManager` that manages JWT tokens stored in keychain, similar to `CodexAuthManager`. Use WKWebView to load kimi.com, monitor for the `kimi-auth` cookie containing the JWT, then call the internal BillingService/GetUsages endpoint with that token. Replace the current API key-based balance fetching with JWT-based usage fetching.

**Tech Stack:** Swift/SwiftUI, WebKit (WKWebView), Security framework (Keychain), URLSession

---

## Background

The current Kimi implementation uses the public API (`api.moonshot.cn/v1/users/me/balance`) with API key authentication. However, the detailed usage data is only available through the internal endpoint:

```
POST https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages
Authorization: Bearer <JWT_FROM_KIMI_AUTH_COOKIE>
Content-Type: application/json

{"scope":["FEATURE_CODING"]}
```

This requires browser authentication to obtain the JWT token from the `kimi-auth` cookie.

---

### Task 1: Create KimiSessionKeychain for JWT Storage

**Files:**
- Create: `AIMeter/Sources/Shared/KimiSessionKeychain.swift`

**Step 1: Write the keychain helper**

```swift
import Foundation
import Security
import os

enum KimiSessionKeychain {
    private static let serviceName = "com.khairul.aimeter.kimi"
    private static let logger = Logger(subsystem: "com.khairul.aimeter", category: "KimiSessionKeychain")

    enum Account: String, CaseIterable {
        case jwtToken
        case userId
        case userName
        case planName
    }

    static func save(account: Account, value: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save keychain item for account \(account.rawValue), status \(status)")
        }
    }

    static func read(account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty
        else { return nil }
        return str
    }

    static func delete(account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        for account in Account.allCases {
            delete(account: account)
        }
    }
}
```

**Step 2: Regenerate and build**

```bash
cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: Build succeeds with new file.

**Step 3: Commit**

```bash
git add AIMeter/Sources/Shared/KimiSessionKeychain.swift && git commit -m "feat: add KimiSessionKeychain for JWT token storage"
```

---

### Task 2: Create KimiAuthManager

**Files:**
- Create: `AIMeter/Sources/App/KimiAuthManager.swift`

**Step 1: Write the auth manager**

```swift
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
                let jwt = cookie.value
                DispatchQueue.main.async {
                    self.cookieTimer?.invalidate()
                    self.cookieTimer = nil
                    self.validateJWT(jwt)
                }
            }
        }
    }

    private func validateJWT(_ jwt: String) {
        loginState = .validating

        Task { @MainActor in
            // Validate by making a test request to GetUsages endpoint
            let url = URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["scope": ["FEATURE_CODING"]])

            do {
                let session = URLSession(configuration: .ephemeral)
                let (data, response) = try await session.data(for: request)

                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    loginState = .failed(message: "HTTP \(http.statusCode): \(errorBody)")
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
                    loginState = .success(name: "Kimi User")
                    try? await Task.sleep(for: .milliseconds(1500))
                    KimiLoginWindowManager.shared.closeLoginWindow()
                } else {
                    loginState = .failed(message: "Invalid response format")
                    startCookieMonitoring()
                }
            } catch {
                loginState = .failed(message: error.localizedDescription)
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
```

**Step 2: Regenerate and build**

```bash
cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add AIMeter/Sources/App/KimiAuthManager.swift && git commit -m "feat: add KimiAuthManager with browser-based login"
```

---

### Task 3: Update KimiUsageData for GetUsages Response

**Files:**
- Modify: `AIMeter/Sources/Shared/KimiUsageData.swift`

**Step 1: Update the data models**

```swift
import Foundation

// MARK: - Usage Data Models for GetUsages endpoint

struct KimiUsageData: Codable, Equatable {
    let scope: String
    let detail: KimiUsageDetail
    let limits: [KimiLimitWindow]
    let fetchedAt: Date

    static let empty = KimiUsageData(
        scope: "FEATURE_CODING",
        detail: KimiUsageDetail(limit: 0, used: 0, remaining: 0, resetTime: nil),
        limits: [],
        fetchedAt: .distantPast
    )

    /// Total usage percentage (0-100)
    var utilizationPercent: Int {
        guard detail.limit > 0 else { return 0 }
        return Int((Double(detail.used) / Double(detail.limit)) * 100)
    }

    /// True if usage is at or over limit
    var isOverLimit: Bool {
        detail.remaining <= 0
    }

    /// Formatted reset time string
    var resetTimeFormatted: String? {
        guard let resetTime = detail.resetTime else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: resetTime)
    }
}

struct KimiUsageDetail: Codable, Equatable {
    let limit: Int
    let used: Int
    let remaining: Int
    let resetTime: Date?

    enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remaining
        case resetTime = "resetTime"
    }
}

struct KimiLimitWindow: Codable, Equatable {
    let window: KimiWindowConfig
    let detail: KimiUsageDetail
}

struct KimiWindowConfig: Codable, Equatable {
    let duration: Int
    let timeUnit: String
}

// MARK: - API Response Models

struct KimiGetUsagesResponse: Codable {
    let usages: [KimiUsageResponseItem]
}

struct KimiUsageResponseItem: Codable {
    let scope: String
    let detail: KimiUsageDetailResponse
    let limits: [KimiLimitWindowResponse]?
}

struct KimiUsageDetailResponse: Codable {
    let limit: String
    let used: String
    let remaining: String
    let resetTime: String?

    func toDetail() -> KimiUsageDetail {
        KimiUsageDetail(
            limit: Int(limit) ?? 0,
            used: Int(used) ?? 0,
            remaining: Int(remaining) ?? 0,
            resetTime: resetTime?.toISO8601Date()
        )
    }
}

struct KimiLimitWindowResponse: Codable {
    let window: KimiWindowConfig
    let detail: KimiUsageDetailResponse
}

// MARK: - Legacy Balance API Models (for backward compatibility)

struct KimiBalanceData: Codable, Equatable {
    let cashBalance: Double      // available cash balance (CNY)
    let voucherBalance: Double   // available voucher/credits balance
    let totalBalance: Double     // cash + voucher
    let fetchedAt: Date

    static let empty = KimiBalanceData(
        cashBalance: 0,
        voucherBalance: 0,
        totalBalance: 0,
        fetchedAt: .distantPast
    )
}

// MARK: - Date Helpers

extension String {
    func toISO8601Date() -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: self)
    }
}
```

**Step 2: Regenerate and build**

```bash
cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add AIMeter/Sources/Shared/KimiUsageData.swift && git commit -m "feat: update KimiUsageData for GetUsages endpoint response"
```

---

### Task 4: Update KimiService to Use JWT Authentication

**Files:**
- Modify: `AIMeter/Sources/App/KimiService.swift`

**Step 1: Rewrite KimiService to use auth manager**

```swift
import Foundation
import WidgetKit

@MainActor
final class KimiService: PollingServiceBase {
    @Published var kimiData: KimiUsageData = .empty
    @Published var isStale: Bool = false
    @Published var error: KimiServiceError? = nil
    @Published var retryDate: Date? = nil

    private weak var authManager: KimiAuthManager?
    private weak var kimiHistoryService: KimiHistoryService?
    private var isFetching = false
    private var consecutiveRateLimits = 0
    private(set) var refreshInterval: TimeInterval = 300

    enum KimiServiceError: Error, Equatable {
        case notAuthenticated
        case fetchFailed
        case rateLimited(retryAfter: TimeInterval)
        case invalidResponse
    }

    func start(interval: TimeInterval = 300, authManager: KimiAuthManager, historyService: KimiHistoryService? = nil) {
        self.refreshInterval = interval
        self.authManager = authManager
        self.kimiHistoryService = historyService
        loadCachedData(staleThreshold: interval * 2)
        super.start(interval: interval)
    }

    override func tick() async {
        await fetch()
    }

    func fetch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        guard let auth = authManager,
              let jwtToken = auth.jwtToken else {
            self.error = .notAuthenticated
            return
        }

        do {
            let data = try await fetchUsages(jwtToken: jwtToken)
            self.kimiData = data
            self.isStale = false
            consecutiveRateLimits = 0
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            self.retryDate = nil
            SharedDefaults.saveKimi(self.kimiData)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.shared.check(metrics: NotificationManager.metrics(from: self.kimiData))
            kimiHistoryService?.recordDataPoint(utilization: self.kimiData.utilizationPercent)
        } catch let serviceError as KimiServiceError {
            self.isStale = true
            self.error = serviceError
            if case .rateLimited(let retryAfter) = serviceError {
                consecutiveRateLimits += 1
                let backoff = retryAfter * pow(1.5, Double(min(consecutiveRateLimits - 1, 4)))
                let jitter = Double.random(in: 0...5)
                let delay = backoff + jitter
                self.retryDate = Date().addingTimeInterval(delay)
                rescheduleTimer(interval: delay)
            } else {
                self.retryDate = nil
            }
        } catch {
            self.isStale = true
            self.error = .fetchFailed
            self.retryDate = nil
        }
    }

    private func fetchUsages(jwtToken: String) async throws -> KimiUsageData {
        let url = URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("connect-protocol-version", forHTTPHeaderField: "1")
        request.timeoutInterval = 15

        let body: [String: Any] = ["scope": ["FEATURE_CODING"]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                    .flatMap { TimeInterval($0) } ?? 60
                throw KimiServiceError.rateLimited(retryAfter: retryAfter)
            }
            guard (200...299).contains(http.statusCode) else {
                throw KimiServiceError.fetchFailed
            }
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usages = json["usages"] as? [[String: Any]],
              let firstUsage = usages.first else {
            throw KimiServiceError.invalidResponse
        }

        return parseUsageResponse(firstUsage)
    }

    private func parseUsageResponse(_ json: [String: Any]) -> KimiUsageData {
        let scope = json["scope"] as? String ?? "FEATURE_CODING"

        let detail: KimiUsageDetail
        if let detailJson = json["detail"] as? [String: Any] {
            let limit = Int(detailJson["limit"] as? String ?? "0") ?? 0
            let used = Int(detailJson["used"] as? String ?? "0") ?? 0
            let remaining = Int(detailJson["remaining"] as? String ?? "0") ?? 0
            let resetTime = (detailJson["resetTime"] as? String)?.toISO8601Date()
            detail = KimiUsageDetail(limit: limit, used: used, remaining: remaining, resetTime: resetTime)
        } else {
            detail = KimiUsageDetail(limit: 0, used: 0, remaining: 0, resetTime: nil)
        }

        var limits: [KimiLimitWindow] = []
        if let limitsJson = json["limits"] as? [[String: Any]] {
            limits = limitsJson.compactMap { limitJson in
                guard let windowJson = limitJson["window"] as? [String: Any],
                      let duration = windowJson["duration"] as? Int,
                      let timeUnit = windowJson["timeUnit"] as? String,
                      let windowDetailJson = limitJson["detail"] as? [String: Any] else {
                    return nil
                }
                let window = KimiWindowConfig(duration: duration, timeUnit: timeUnit)
                let windowLimit = Int(windowDetailJson["limit"] as? String ?? "0") ?? 0
                let windowUsed = Int(windowDetailJson["used"] as? String ?? "0") ?? 0
                let windowRemaining = Int(windowDetailJson["remaining"] as? String ?? "0") ?? 0
                let windowResetTime = (windowDetailJson["resetTime"] as? String)?.toISO8601Date()
                let windowDetail = KimiUsageDetail(limit: windowLimit, used: windowUsed, remaining: windowRemaining, resetTime: windowResetTime)
                return KimiLimitWindow(window: window, detail: windowDetail)
            }
        }

        return KimiUsageData(scope: scope, detail: detail, limits: limits, fetchedAt: Date())
    }

    private func loadCachedData(staleThreshold: TimeInterval) {
        if let cached = SharedDefaults.loadKimi() {
            self.kimiData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > staleThreshold
        }
    }

    private func rescheduleTimer(interval: TimeInterval) {
        stop()
        start(interval: interval, authManager: authManager!, historyService: kimiHistoryService)
    }
}
```

**Step 2: Regenerate and build**

```bash
cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add AIMeter/Sources/App/KimiService.swift && git commit -m "feat: update KimiService to use JWT authentication and GetUsages endpoint"
```

---

### Task 5: Update SharedDefaults for New KimiUsageData

**Files:**
- Modify: `AIMeter/Sources/Shared/SharedDefaults.swift`

**Step 1: Check current implementation and update if needed**

The SharedDefaults should already have methods for Kimi. Verify and update:

```swift
// In SharedDefaults.swift, ensure these methods exist:

static func saveKimi(_ data: KimiUsageData) {
    if let encoded = try? JSONEncoder().encode(data) {
        shared.set(encoded, forKey: Keys.kimi)
        shared.set(Date(), forKey: Keys.kimiTimestamp)
    }
}

static func loadKimi() -> KimiUsageData? {
    guard let data = shared.object(forKey: Keys.kimi) as? Data,
          let decoded = try? JSONDecoder().decode(KimiUsageData.self, from: data) else {
        return nil
    }
    return decoded
}
```

If the methods already exist and work with the updated `KimiUsageData` model, no changes needed.

**Step 2: Build verification**

```bash
cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 3: Commit (if changes made)**

```bash
git add AIMeter/Sources/Shared/SharedDefaults.swift && git commit -m "feat: update SharedDefaults for new KimiUsageData model"
```

---

### Task 6: Update KimiHistory for New Data Structure

**Files:**
- Modify: `AIMeter/Sources/Shared/KimiHistory.swift`

**Step 1: Update to track utilization percentage**

```swift
import Foundation

struct KimiHistoryDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let utilization: Int  // Changed from totalBalance to utilization percentage

    init(utilization: Int) {
        self.id = UUID()
        self.timestamp = Date()
        self.utilization = utilization
    }
}

struct KimiHistory: Codable {
    var dataPoints: [KimiHistoryDataPoint] = []
}
```

**Step 2: Update KimiHistoryService**

```swift
// In KimiHistoryService.swift, update recordDataPoint method:

func recordDataPoint(utilization: Int) {
    let point = KimiHistoryDataPoint(utilization: utilization)
    history.dataPoints.append(point)
    markDirty()
}
```

**Step 3: Regenerate and build**

```bash
cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 4: Commit**

```bash
git add AIMeter/Sources/Shared/KimiHistory.swift AIMeter/Sources/App/KimiHistoryService.swift && git commit -m "feat: update Kimi history to track utilization percentage"
```

---

### Task 7: Update KimiTabView for Sign-In UI

**Files:**
- Modify: `AIMeter/Sources/App/KimiTabView.swift`

**Step 1: Rewrite to show sign-in prompt when not authenticated**

```swift
import SwiftUI

struct KimiTabView: View {
    @ObservedObject var kimiService: KimiService
    @ObservedObject var historyService: KimiHistoryService
    @ObservedObject var authManager: KimiAuthManager
    var onKeySaved: (() -> Void)? = nil

    var body: some View {
        if !authManager.isAuthenticated {
            signInPromptView
        } else {
            usageContentView
        }
    }

    private var signInPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Sign in to Kimi")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text("Access your Kimi for Coding usage data")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Sign in with Browser") {
                authManager.openLoginWindow()
            }
            .font(.system(size: 13, weight: .medium))
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            if let error = authManager.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var usageContentView: some View {
        VStack(spacing: 8) {
            if case .fetchFailed = kimiService.error {
                ErrorBannerView(message: "Failed to fetch usage") {
                    Task { await kimiService.fetch() }
                }
            }
            if case .rateLimited = kimiService.error {
                ErrorBannerView(message: "Rate limited — retrying", retryDate: kimiService.retryDate)
            }

            // Main usage card
            usageCard

            // Rate limit windows
            ForEach(kimiService.kimiData.limits.indices, id: \.self) { index in
                limitWindowCard(kimiService.kimiData.limits[index])
            }

            UsageHistoryChartView(
                title: "Usage History",
                dataPoints: historyService.history.dataPoints.map {
                    (date: $0.timestamp, value: Double($0.utilization), label: shortDateLabel($0.timestamp))
                },
                valueFormatter: { "\(Int($0))%" },
                accentColor: ProviderTheme.kimi.accentColor
            )
        }
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("Weekly Usage")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                if let resetTime = kimiService.kimiData.resetTimeFormatted {
                    Text("Resets: \(resetTime)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(kimiService.kimiData.detail.used)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("/ \(kimiService.kimiData.detail.limit)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(kimiService.kimiData.utilizationPercent)%")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(utilizationColor)
            }

            ProgressBarView(
                value: Double(kimiService.kimiData.detail.used),
                maxValue: Double(kimiService.kimiData.detail.limit),
                color: utilizationColor
            )
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .frame(width: 2)
                .foregroundColor(ProviderTheme.kimi.accentColor)
        }
    }

    private func limitWindowCard(_ limit: KimiLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("\(limit.window.duration)-minute Window")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }

            HStack {
                Text("\(limit.detail.used) / \(limit.detail.limit)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(limit.detail.remaining) remaining")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private var utilizationColor: Color {
        let pct = kimiService.kimiData.utilizationPercent
        if pct < 50 { return .green }
        if pct < 80 { return .yellow }
        return .red
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
```

**Step 2: Regenerate and build**

```bash
cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add AIMeter/Sources/App/KimiTabView.swift && git commit -m "feat: update KimiTabView with sign-in prompt and new usage UI"
```

---

### Task 8: Wire KimiAuthManager into AIMeterApp

**Files:**
- Modify: `AIMeter/Sources/App/AIMeterApp.swift`

**Step 1: Add KimiAuthManager state object**

Add to the `@StateObject` declarations:
```swift
@StateObject private var kimiAuthManager = KimiAuthManager()
```

**Step 2: Update kimiService.start() call**

In the `.task` modifier, update the kimiService start call:
```swift
kimiService.start(interval: interval(for: .kimi), authManager: kimiAuthManager, historyService: kimiHistoryService)
```

**Step 3: Update restartAll closure**

Update the restartAll closure to pass authManager:
```swift
kimiService.stop()
kimiService.start(interval: interval(for: .kimi), authManager: kimiAuthManager, historyService: kimiHistoryService)
```

**Step 4: Add environment object**

Add to the PopoverView environment objects:
```swift
.environmentObject(kimiAuthManager)
```

**Step 5: Add onChange for authentication**

Add after other onChange modifiers:
```swift
.onChange(of: kimiAuthManager.isAuthenticated) { _, isAuth in
    if isAuth {
        Task { await kimiService.fetch() }
    }
}
```

**Step 6: Regenerate and build**

```bash
cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 7: Commit**

```bash
git add AIMeter/Sources/App/AIMeterApp.swift && git commit -m "feat: wire KimiAuthManager into app lifecycle"
```

---

### Task 9: Update PopoverView to Pass Auth Manager

**Files:**
- Modify: `AIMeter/Sources/App/PopoverView.swift`

**Step 1: Add kimAuthManager to PopoverView**

Add property:
```swift
@EnvironmentObject var kimiAuthManager: KimiAuthManager
```

**Step 2: Update Kimi tab case**

In the tab view switch statement, update the kimi case:
```swift
case .kimi:
    KimiTabView(
        kimiService: kimiService,
        historyService: kimiHistoryService,
        authManager: kimiAuthManager
    )
```

**Step 3: Regenerate and build**

```bash
cd /Users/firdausnasir/coding/ai-meter/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 4: Commit**

```bash
git add AIMeter/Sources/App/PopoverView.swift && git commit -m "feat: pass KimiAuthManager to KimiTabView"
```

---

### Task 10: Final Build Verification

**Step 1: Full clean build**

```bash
cd /Users/firdausnasir/coding/ai-meter/AIMeter
xcodegen generate
xcodebuild clean
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -10
```

**Step 2: Run tests (if any exist)**

```bash
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug test ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

**Expected:** All builds pass without errors.

---

## Summary of Changes

### New Files:
1. `AIMeter/Sources/Shared/KimiSessionKeychain.swift` - Keychain storage for JWT
2. `AIMeter/Sources/App/KimiAuthManager.swift` - Browser-based auth manager

### Modified Files:
1. `AIMeter/Sources/Shared/KimiUsageData.swift` - New data models for GetUsages
2. `AIMeter/Sources/Shared/KimiHistory.swift` - Track utilization instead of balance
3. `AIMeter/Sources/App/KimiService.swift` - JWT-based API calls
4. `AIMeter/Sources/App/KimiHistoryService.swift` - Updated record method
5. `AIMeter/Sources/App/KimiTabView.swift` - Sign-in UI and new usage display
6. `AIMeter/Sources/App/AIMeterApp.swift` - Wire up auth manager
7. `AIMeter/Sources/App/PopoverView.swift` - Pass auth manager to tab

### API Endpoint:
- **URL:** `POST https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages`
- **Auth:** Bearer token from `kimi-auth` cookie
- **Body:** `{"scope":["FEATURE_CODING"]}`

### Testing Instructions:
1. Build and run the app
2. Navigate to the Kimi tab
3. Click "Sign in with Browser"
4. Log in to kimi.com in the web view
5. The app should automatically extract the JWT and fetch usage data
6. Usage data should display weekly limits and rate limit windows

---

## Rollback Plan

If issues occur:
1. Revert commits in reverse order
2. Restore the original API key-based implementation
3. Keep the JWT implementation in a feature branch for further testing
