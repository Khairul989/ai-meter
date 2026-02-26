# ClaudeQuota Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS menu bar app + WidgetKit widgets that display Claude API usage and rate limits.

**Architecture:** SwiftUI menu bar app (LSUIElement) with a WidgetKit extension. Main app polls the API on a timer, stores data in App Group UserDefaults. Widget reads from shared storage. XcodeGen manages the project declaratively.

**Tech Stack:** Swift 5.9+, SwiftUI, WidgetKit, Keychain Services, XcodeGen, macOS 14+ (Sonoma)

**Design doc:** `docs/plans/2026-02-26-claudequota-menubar-design.md`

---

### Task 1: Project Scaffolding with XcodeGen

XcodeGen lets us define the Xcode project in YAML and generate `.xcodeproj` from CLI — no manual Xcode fiddling.

**Step 1: Install XcodeGen**

Run: `brew install xcodegen`

**Step 2: Create directory structure**

```bash
mkdir -p ClaudeQuota/Sources/App
mkdir -p ClaudeQuota/Sources/Shared
mkdir -p ClaudeQuota/Sources/Widget
mkdir -p ClaudeQuota/Resources
mkdir -p ClaudeQuota/Tests
```

**Step 3: Create `ClaudeQuota/project.yml`**

```yaml
name: ClaudeQuota
options:
  bundleIdPrefix: com.khairul
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "16.0"
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "14.0"

targets:
  ClaudeQuota:
    type: application
    platform: macOS
    sources:
      - path: Sources/App
      - path: Sources/Shared
    resources:
      - path: Resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.khairul.claudequota
        INFOPLIST_VALUES: >-
          LSUIElement=true;
          CFBundleDisplayName=ClaudeQuota;
          CFBundleShortVersionString=1.0.0;
          CFBundleVersion=1
        CODE_SIGN_ENTITLEMENTS: Resources/ClaudeQuota.entitlements
        CODE_SIGN_IDENTITY: "Apple Development"
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: ""
    entitlements:
      path: Resources/ClaudeQuota.entitlements
      properties:
        com.apple.security.app-sandbox: false
        com.apple.security.application-groups:
          - group.com.khairul.claudequota
        keychain-access-groups:
          - $(AppIdentifierPrefix)com.khairul.claudequota

  ClaudeQuotaWidget:
    type: app-extension
    platform: macOS
    sources:
      - path: Sources/Widget
      - path: Sources/Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.khairul.claudequota.widget
        INFOPLIST_VALUES: >-
          CFBundleDisplayName=ClaudeQuota Widget;
          CFBundleShortVersionString=1.0.0;
          CFBundleVersion=1;
          NSExtension={NSExtensionPointIdentifier=com.apple.widgetkit-extension}
        CODE_SIGN_ENTITLEMENTS: Resources/ClaudeQuotaWidget.entitlements
        CODE_SIGN_IDENTITY: "Apple Development"
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: ""
    entitlements:
      path: Resources/ClaudeQuotaWidget.entitlements
      properties:
        com.apple.security.app-sandbox: false
        com.apple.security.application-groups:
          - group.com.khairul.claudequota
    dependencies:
      - target: ClaudeQuota
        embed: false
        link: false
```

**Step 4: Create entitlements files**

Create `ClaudeQuota/Resources/ClaudeQuota.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.khairul.claudequota</string>
    </array>
</dict>
</plist>
```

Create `ClaudeQuota/Resources/ClaudeQuotaWidget.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.khairul.claudequota</string>
    </array>
</dict>
</plist>
```

**Step 5: Create placeholder Swift files so Xcode project generates**

Create `ClaudeQuota/Sources/App/ClaudeQuotaApp.swift`:

```swift
import SwiftUI

@main
struct ClaudeQuotaApp: App {
    var body: some Scene {
        MenuBarExtra("ClaudeQuota", systemImage: "gauge.medium") {
            Text("ClaudeQuota — Loading...")
        }
    }
}
```

Create `ClaudeQuota/Sources/Shared/UsageData.swift`:

```swift
import Foundation

struct UsageData: Codable {
    let fiveHour: RateLimit
    let sevenDay: RateLimit
    let sevenDaySonnet: RateLimit?
    let extraCredits: ExtraCredits?
    let fetchedAt: Date
}

struct RateLimit: Codable {
    let utilization: Int
    let resetsAt: Date?
}

struct ExtraCredits: Codable {
    let utilization: Int
    let used: Double
    let limit: Double
}
```

Create `ClaudeQuota/Sources/Widget/ClaudeQuotaWidget.swift`:

```swift
import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300)))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct ClaudeQuotaWidgetView: View {
    var entry: SimpleEntry
    var body: some View {
        Text("ClaudeQuota")
    }
}

@main
struct ClaudeQuotaWidget: Widget {
    let kind = "ClaudeQuotaWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ClaudeQuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Quota")
        .description("Monitor Claude API usage limits")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

**Step 6: Generate Xcode project**

Run: `cd ClaudeQuota && xcodegen generate`
Expected: `⚙️  Generating plists... ✅  Created project: ClaudeQuota.xcodeproj`

**Step 7: Build to verify**

Run: `cd ClaudeQuota && xcodebuild -scheme ClaudeQuota -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 8: Commit**

```bash
git add ClaudeQuota/ project.yml
git commit -m "feat: scaffold ClaudeQuota Xcode project with XcodeGen"
```

---

### Task 2: Shared Models & Color Utilities

**Files:**
- Modify: `ClaudeQuota/Sources/Shared/UsageData.swift`
- Create: `ClaudeQuota/Sources/Shared/UsageColor.swift`
- Create: `ClaudeQuota/Sources/Shared/SharedDefaults.swift`
- Test: `ClaudeQuota/Tests/UsageDataTests.swift`

**Step 1: Write tests for models and color logic**

```swift
import XCTest
@testable import ClaudeQuota

final class UsageDataTests: XCTestCase {
    func testDecodingFullResponse() throws {
        let json = """
        {
            "fiveHour": {"utilization": 37, "resetsAt": "2026-02-26T10:00:00Z"},
            "sevenDay": {"utilization": 54, "resetsAt": "2026-02-27T03:00:00Z"},
            "sevenDaySonnet": {"utilization": 3, "resetsAt": "2026-02-27T04:00:00Z"},
            "extraCredits": {"utilization": 12, "used": 2.4, "limit": 20.0},
            "fetchedAt": "2026-02-26T08:00:00Z"
        }
        """.data(using: .utf8)!
        let data = try JSONDecoder.appDecoder.decode(UsageData.self, from: json)
        XCTAssertEqual(data.fiveHour.utilization, 37)
        XCTAssertEqual(data.sevenDay.utilization, 54)
        XCTAssertEqual(data.sevenDaySonnet?.utilization, 3)
        XCTAssertEqual(data.extraCredits?.utilization, 12)
        XCTAssertEqual(data.extraCredits?.used, 2.4)
    }

    func testDecodingWithoutOptionals() throws {
        let json = """
        {
            "fiveHour": {"utilization": 10},
            "sevenDay": {"utilization": 20},
            "fetchedAt": "2026-02-26T08:00:00Z"
        }
        """.data(using: .utf8)!
        let data = try JSONDecoder.appDecoder.decode(UsageData.self, from: json)
        XCTAssertNil(data.sevenDaySonnet)
        XCTAssertNil(data.extraCredits)
        XCTAssertNil(data.fiveHour.resetsAt)
    }

    func testUsageColorThresholds() {
        XCTAssertEqual(UsageColor.forUtilization(0), .green)
        XCTAssertEqual(UsageColor.forUtilization(49), .green)
        XCTAssertEqual(UsageColor.forUtilization(50), .yellow)
        XCTAssertEqual(UsageColor.forUtilization(79), .yellow)
        XCTAssertEqual(UsageColor.forUtilization(80), .red)
        XCTAssertEqual(UsageColor.forUtilization(100), .red)
    }

    func testHighestUtilization() {
        let data = UsageData(
            fiveHour: RateLimit(utilization: 37, resetsAt: nil),
            sevenDay: RateLimit(utilization: 54, resetsAt: nil),
            sevenDaySonnet: RateLimit(utilization: 80, resetsAt: nil),
            extraCredits: nil,
            fetchedAt: Date()
        )
        XCTAssertEqual(data.highestUtilization, 80)
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd ClaudeQuota && xcodebuild test -scheme ClaudeQuota -configuration Debug 2>&1 | tail -10`
Expected: FAIL — missing types and methods

**Step 3: Implement shared models**

Update `ClaudeQuota/Sources/Shared/UsageData.swift`:

```swift
import Foundation

struct UsageData: Codable, Equatable {
    let fiveHour: RateLimit
    let sevenDay: RateLimit
    let sevenDaySonnet: RateLimit?
    let extraCredits: ExtraCredits?
    let fetchedAt: Date

    var highestUtilization: Int {
        var values = [fiveHour.utilization, sevenDay.utilization]
        if let sonnet = sevenDaySonnet { values.append(sonnet.utilization) }
        if let credits = extraCredits { values.append(credits.utilization) }
        return values.max() ?? 0
    }

    static let empty = UsageData(
        fiveHour: RateLimit(utilization: 0, resetsAt: nil),
        sevenDay: RateLimit(utilization: 0, resetsAt: nil),
        sevenDaySonnet: nil,
        extraCredits: nil,
        fetchedAt: .distantPast
    )
}

struct RateLimit: Codable, Equatable {
    let utilization: Int
    let resetsAt: Date?
}

struct ExtraCredits: Codable, Equatable {
    let utilization: Int
    let used: Double
    let limit: Double
}

extension JSONDecoder {
    static let appDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let appEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
```

**Step 4: Create `UsageColor.swift`**

```swift
import SwiftUI

enum UsageColor {
    static func forUtilization(_ value: Int) -> Color {
        switch value {
        case ..<50: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }
}
```

**Step 5: Create `SharedDefaults.swift`**

```swift
import Foundation
import WidgetKit

enum SharedDefaults {
    static let suiteName = "group.com.khairul.claudequota"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func save(_ data: UsageData) {
        guard let encoded = try? JSONEncoder.appEncoder.encode(data) else { return }
        suite?.set(encoded, forKey: "usageData")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> UsageData? {
        guard let data = suite?.data(forKey: "usageData"),
              let decoded = try? JSONDecoder.appDecoder.decode(UsageData.self, from: data)
        else { return nil }
        return decoded
    }
}
```

**Step 6: Run tests to verify they pass**

Run: `cd ClaudeQuota && xcodebuild test -scheme ClaudeQuota -configuration Debug 2>&1 | tail -10`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add ClaudeQuota/Sources/Shared/ ClaudeQuota/Tests/
git commit -m "feat: add shared models, color utilities, and App Group defaults"
```

---

### Task 3: KeychainHelper

**Files:**
- Create: `ClaudeQuota/Sources/Shared/KeychainHelper.swift`
- Test: `ClaudeQuota/Tests/KeychainHelperTests.swift`

**Step 1: Write tests**

```swift
import XCTest
@testable import ClaudeQuota

final class KeychainHelperTests: XCTestCase {
    func testParseCredentialJSON() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"sk-ant-test-123","refreshToken":"rt-456"}}
        """
        let token = KeychainHelper.extractToken(from: json)
        XCTAssertEqual(token, "sk-ant-test-123")
    }

    func testParseInvalidJSON() {
        let token = KeychainHelper.extractToken(from: "not json")
        XCTAssertNil(token)
    }

    func testParseMissingToken() {
        let json = """
        {"claudeAiOauth":{}}
        """
        let token = KeychainHelper.extractToken(from: json)
        XCTAssertNil(token)
    }
}
```

**Step 2: Run tests — expect FAIL**

Run: `cd ClaudeQuota && xcodebuild test -scheme ClaudeQuota -configuration Debug 2>&1 | tail -10`

**Step 3: Implement KeychainHelper**

```swift
import Foundation
import Security

enum KeychainHelper {
    private static let serviceName = "Claude Code-credentials"

    /// Read the OAuth access token from Claude Code's Keychain entry
    static func readAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let jsonString = String(data: data, encoding: .utf8)
        else { return nil }

        return extractToken(from: jsonString)
    }

    /// Parse the credential JSON to extract the access token (testable)
    static func extractToken(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }
}
```

**Step 4: Run tests — expect PASS**

Run: `cd ClaudeQuota && xcodebuild test -scheme ClaudeQuota -configuration Debug 2>&1 | tail -10`

**Step 5: Commit**

```bash
git add ClaudeQuota/Sources/Shared/KeychainHelper.swift ClaudeQuota/Tests/KeychainHelperTests.swift
git commit -m "feat: add KeychainHelper for reading Claude Code OAuth token"
```

---

### Task 4: API Client & UsageService

**Files:**
- Create: `ClaudeQuota/Sources/Shared/APIClient.swift`
- Create: `ClaudeQuota/Sources/App/UsageService.swift`
- Test: `ClaudeQuota/Tests/APIClientTests.swift`

**Step 1: Write test for API response parsing**

```swift
import XCTest
@testable import ClaudeQuota

final class APIClientTests: XCTestCase {
    func testParseAPIResponse() throws {
        let json = """
        {
            "five_hour": {"utilization": 0.37, "resets_at": "2026-02-26T10:00:00.000Z"},
            "seven_day": {"utilization": 0.54, "resets_at": "2026-02-27T03:00:00.000Z"},
            "seven_day_sonnet": {"utilization": 0.03, "resets_at": "2026-02-27T04:00:00.000Z"},
            "extra_usage": {
                "is_enabled": true,
                "monthly_limit": 20.0,
                "used_credits": 2.4,
                "utilization": 0.12
            }
        }
        """.data(using: .utf8)!
        let usage = try APIClient.parseResponse(json)
        XCTAssertEqual(usage.fiveHour.utilization, 37)
        XCTAssertEqual(usage.sevenDay.utilization, 54)
        XCTAssertEqual(usage.sevenDaySonnet?.utilization, 3)
        XCTAssertEqual(usage.extraCredits?.utilization, 12)
        XCTAssertEqual(usage.extraCredits?.used, 2.4)
        XCTAssertEqual(usage.extraCredits?.limit, 20.0)
    }

    func testParseResponseWithoutOptionals() throws {
        let json = """
        {
            "five_hour": {"utilization": 0.10, "resets_at": "2026-02-26T10:00:00.000Z"},
            "seven_day": {"utilization": 0.20, "resets_at": "2026-02-27T03:00:00.000Z"},
            "extra_usage": {"is_enabled": false}
        }
        """.data(using: .utf8)!
        let usage = try APIClient.parseResponse(json)
        XCTAssertEqual(usage.fiveHour.utilization, 10)
        XCTAssertNil(usage.sevenDaySonnet)
        XCTAssertNil(usage.extraCredits)
    }
}
```

**Step 2: Run tests — expect FAIL**

**Step 3: Implement APIClient**

```swift
import Foundation

enum APIClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Fetch usage data from the API
    static func fetchUsage(token: String) async throws -> UsageData {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 5

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseResponse(data)
    }

    /// Parse the raw API response into our UsageData model (testable)
    static func parseResponse(_ data: Data) throws -> UsageData {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let fiveHour = parseRateLimit(json["five_hour"] as? [String: Any] ?? [:])
        let sevenDay = parseRateLimit(json["seven_day"] as? [String: Any] ?? [:])

        let sevenDaySonnet: RateLimit?
        if let sonnetDict = json["seven_day_sonnet"] as? [String: Any],
           sonnetDict["utilization"] != nil {
            sevenDaySonnet = parseRateLimit(sonnetDict)
        } else {
            sevenDaySonnet = nil
        }

        let extraCredits: ExtraCredits?
        if let extraDict = json["extra_usage"] as? [String: Any],
           extraDict["is_enabled"] as? Bool == true {
            extraCredits = ExtraCredits(
                utilization: percentFromFloat(extraDict["utilization"]),
                used: extraDict["used_credits"] as? Double ?? 0,
                limit: extraDict["monthly_limit"] as? Double ?? 0
            )
        } else {
            extraCredits = nil
        }

        return UsageData(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            sevenDaySonnet: sevenDaySonnet,
            extraCredits: extraCredits,
            fetchedAt: Date()
        )
    }

    private static func parseRateLimit(_ dict: [String: Any]) -> RateLimit {
        let resetsAt: Date?
        if let resetStr = dict["resets_at"] as? String {
            resetsAt = ISO8601DateFormatter().date(from: resetStr)
        } else {
            resetsAt = nil
        }
        return RateLimit(
            utilization: percentFromFloat(dict["utilization"]),
            resetsAt: resetsAt
        )
    }

    /// API returns utilization as 0.0-1.0 float, convert to 0-100 int
    private static func percentFromFloat(_ value: Any?) -> Int {
        guard let floatVal = value as? Double else { return 0 }
        return Int(floatVal * 100)
    }
}
```

**Step 4: Implement UsageService**

```swift
import Foundation
import Combine

@MainActor
final class UsageService: ObservableObject {
    @Published var usageData: UsageData = SharedDefaults.load() ?? .empty
    @Published var isStale: Bool = false
    @Published var error: UsageError? = nil

    private var timer: Timer?
    private var refreshInterval: TimeInterval = 60

    enum UsageError: Equatable {
        case noToken
        case fetchFailed
    }

    func start(interval: TimeInterval = 60) {
        self.refreshInterval = interval
        // Load cached data immediately
        if let cached = SharedDefaults.load() {
            self.usageData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > refreshInterval * 2
        }
        // Fetch immediately then on timer
        Task { await fetch() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.fetch() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fetch() async {
        guard let token = KeychainHelper.readAccessToken() else {
            self.error = .noToken
            return
        }

        do {
            let data = try await APIClient.fetchUsage(token: token)
            self.usageData = data
            self.isStale = false
            self.error = nil
            SharedDefaults.save(data)
        } catch {
            self.isStale = true
            self.error = .fetchFailed
        }
    }
}
```

**Step 5: Run tests — expect PASS**

Run: `cd ClaudeQuota && xcodebuild test -scheme ClaudeQuota -configuration Debug 2>&1 | tail -10`

**Step 6: Commit**

```bash
git add ClaudeQuota/Sources/Shared/APIClient.swift ClaudeQuota/Sources/App/UsageService.swift ClaudeQuota/Tests/APIClientTests.swift
git commit -m "feat: add API client and usage service with polling"
```

---

### Task 5: Reusable UI Components

**Files:**
- Create: `ClaudeQuota/Sources/Shared/CircularGaugeView.swift`
- Create: `ClaudeQuota/Sources/Shared/ProgressBarView.swift`
- Create: `ClaudeQuota/Sources/Shared/ResetTimeFormatter.swift`

**Step 1: Create CircularGaugeView**

```swift
import SwiftUI

struct CircularGaugeView: View {
    let percentage: Int
    let lineWidth: CGFloat
    let size: CGFloat

    private var color: Color { UsageColor.forUtilization(percentage) }
    private var progress: Double { Double(percentage) / 100.0 }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: percentage)
            // Percentage text
            Text("\(percentage)%")
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}
```

**Step 2: Create ProgressBarView**

```swift
import SwiftUI

struct ProgressBarView: View {
    let percentage: Int
    let height: CGFloat

    private var color: Color { UsageColor.forUtilization(percentage) }
    private var progress: Double { Double(min(percentage, 100)) / 100.0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color.opacity(0.2))
                // Fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geo.size.width * progress)
                    .animation(.easeInOut(duration: 0.3), value: percentage)
            }
        }
        .frame(height: height)
    }
}
```

**Step 3: Create ResetTimeFormatter**

```swift
import Foundation

enum ResetTimeFormatter {
    /// Format a reset date for display, relative to now.
    /// Short format: "3h01" for 5-hour resets (same day).
    /// Long format: "Thu 11am" for 7-day resets.
    static func format(_ date: Date?, style: Style, timeZone: TimeZone = .current) -> String? {
        guard let date else { return nil }

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.timeZone = timeZone

        switch style {
        case .countdown:
            let diff = calendar.dateComponents([.hour, .minute], from: Date(), to: date)
            guard let h = diff.hour, let m = diff.minute, h >= 0, m >= 0 else { return nil }
            return String(format: "%dh%02d", h, m)
        case .dayTime:
            formatter.dateFormat = "EEE h:mma"
            return formatter.string(from: date).lowercased()
        }
    }

    enum Style {
        case countdown  // "3h01"
        case dayTime    // "thu 11:00am"
    }
}
```

**Step 4: Build to verify**

Run: `cd ClaudeQuota && xcodebuild -scheme ClaudeQuota -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
git add ClaudeQuota/Sources/Shared/CircularGaugeView.swift ClaudeQuota/Sources/Shared/ProgressBarView.swift ClaudeQuota/Sources/Shared/ResetTimeFormatter.swift
git commit -m "feat: add reusable gauge, progress bar, and reset time formatter"
```

---

### Task 6: Menu Bar Popover UI

**Files:**
- Create: `ClaudeQuota/Sources/App/PopoverView.swift`
- Create: `ClaudeQuota/Sources/App/UsageCardView.swift`
- Create: `ClaudeQuota/Sources/App/SettingsView.swift`
- Modify: `ClaudeQuota/Sources/App/ClaudeQuotaApp.swift`

**Step 1: Create UsageCardView**

```swift
import SwiftUI

struct UsageCardView: View {
    let icon: String
    let title: String
    let subtitle: String
    let percentage: Int
    let resetText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(UsageColor.forUtilization(percentage))
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(percentage)%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(UsageColor.forUtilization(percentage))
            }
            HStack {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if let resetText {
                    Text("Reset \(resetText)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            ProgressBarView(percentage: percentage, height: 6)
        }
        .padding(.vertical, 8)
    }
}
```

**Step 2: Create PopoverView**

```swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var service: UsageService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundColor(UsageColor.forUtilization(service.usageData.highestUtilization))
                    .font(.system(size: 10))
                Text("ClaudeQuota")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.bottom, 8)

            if let error = service.error, error == .noToken {
                noTokenView
            } else {
                usageCards
            }

            Divider().background(Color.gray.opacity(0.3))

            // Footer
            HStack {
                Text(updatedText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                if service.isStale {
                    Text("(stale)")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                Spacer()
                Button(action: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }) {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private var usageCards: some View {
        let data = service.usageData

        UsageCardView(
            icon: "timer",
            title: "Session",
            subtitle: "5h sliding window",
            percentage: data.fiveHour.utilization,
            resetText: ResetTimeFormatter.format(data.fiveHour.resetsAt, style: .countdown)
        )

        UsageCardView(
            icon: "chart.bar.fill",
            title: "Weekly",
            subtitle: "Opus + Sonnet + Haiku",
            percentage: data.sevenDay.utilization,
            resetText: ResetTimeFormatter.format(data.sevenDay.resetsAt, style: .dayTime)
        )

        if let sonnet = data.sevenDaySonnet {
            UsageCardView(
                icon: "sparkles",
                title: "Sonnet",
                subtitle: "Dedicated limit",
                percentage: sonnet.utilization,
                resetText: ResetTimeFormatter.format(sonnet.resetsAt, style: .dayTime)
            )
        }

        if let credits = data.extraCredits {
            UsageCardView(
                icon: "creditcard.fill",
                title: "Extra Credits",
                subtitle: String(format: "$%.2f / $%.2f", credits.used, credits.limit),
                percentage: credits.utilization,
                resetText: nil
            )
        }
    }

    private var noTokenView: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No token found")
                .font(.headline)
                .foregroundColor(.white)
            Text("Sign into Claude Code to get started")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var updatedText: String {
        let seconds = Int(Date().timeIntervalSince(service.usageData.fetchedAt))
        if seconds < 60 { return "Updated less than a minute ago" }
        let minutes = seconds / 60
        return "Updated \(minutes)m ago"
    }
}
```

**Step 3: Create SettingsView**

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = 8 // UTC+8 Malaysia
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Picker("Refresh interval", selection: $refreshInterval) {
                Text("30 seconds").tag(30.0)
                Text("60 seconds").tag(60.0)
                Text("120 seconds").tag(120.0)
            }

            Picker("Timezone", selection: $timezoneOffset) {
                Text("UTC-8 (PST)").tag(-8)
                Text("UTC-5 (EST)").tag(-5)
                Text("UTC+0 (GMT)").tag(0)
                Text("UTC+1 (CET)").tag(1)
                Text("UTC+8 (MYT)").tag(8)
                Text("UTC+9 (JST)").tag(9)
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }

            Button("Quit ClaudeQuota") {
                NSApp.terminate(nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 300, height: 200)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
```

**Step 4: Update ClaudeQuotaApp.swift**

```swift
import SwiftUI

@main
struct ClaudeQuotaApp: App {
    @StateObject private var service = UsageService()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(service: service)
        } label: {
            MenuBarLabel(utilization: service.usageData.highestUtilization)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }

    init() {
        // Will be started by .onAppear or .task in the popover
    }
}

struct MenuBarLabel: View {
    let utilization: Int

    var body: some View {
        Image(systemName: menuBarIcon)
            .symbolRenderingMode(.palette)
            .foregroundStyle(UsageColor.forUtilization(utilization))
    }

    private var menuBarIcon: String {
        switch utilization {
        case ..<25: return "gauge.low"
        case ..<50: return "gauge.medium"
        case ..<80: return "gauge.high"
        default: return "gauge.high"
        }
    }
}
```

**Step 5: Build to verify**

Run: `cd ClaudeQuota && xcodebuild -scheme ClaudeQuota -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 6: Run the app manually to visually verify**

Run: `cd ClaudeQuota && xcodebuild -scheme ClaudeQuota -configuration Debug build 2>&1 | tail -3 && open build/Debug/ClaudeQuota.app`

**Step 7: Commit**

```bash
git add ClaudeQuota/Sources/App/
git commit -m "feat: add menu bar popover UI with usage cards and settings"
```

---

### Task 7: Widget Extension

**Files:**
- Modify: `ClaudeQuota/Sources/Widget/ClaudeQuotaWidget.swift`
- Create: `ClaudeQuota/Sources/Widget/SmallWidgetView.swift`
- Create: `ClaudeQuota/Sources/Widget/MediumWidgetView.swift`

**Step 1: Update the widget entry and provider**

Replace `ClaudeQuota/Sources/Widget/ClaudeQuotaWidget.swift`:

```swift
import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let usageData: UsageData

    static let placeholder = UsageEntry(
        date: Date(),
        usageData: UsageData(
            fiveHour: RateLimit(utilization: 37, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: RateLimit(utilization: 54, resetsAt: Date().addingTimeInterval(86400)),
            sevenDaySonnet: RateLimit(utilization: 3, resetsAt: Date().addingTimeInterval(86400)),
            extraCredits: nil,
            fetchedAt: Date()
        )
    )
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let data = SharedDefaults.load() ?? .empty
        completion(UsageEntry(date: Date(), usageData: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let data = SharedDefaults.load() ?? .empty
        let entry = UsageEntry(date: Date(), usageData: data)
        // Refresh every 5 minutes
        let nextUpdate = Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

@main
struct ClaudeQuotaWidget: Widget {
    let kind = "ClaudeQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            WidgetEntryView(entry: entry)
                .containerBackground(.black.gradient, for: .widget)
        }
        .configurationDisplayName("Claude Quota")
        .description("Monitor Claude API usage limits")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: UsageEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(data: entry.usageData)
        case .systemMedium:
            MediumWidgetView(data: entry.usageData)
        default:
            SmallWidgetView(data: entry.usageData)
        }
    }
}
```

**Step 2: Create SmallWidgetView**

```swift
import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let data: UsageData

    private var highestLimit: (String, RateLimit) {
        var candidates: [(String, RateLimit)] = [
            ("Session", data.fiveHour),
            ("Weekly", data.sevenDay)
        ]
        if let sonnet = data.sevenDaySonnet {
            candidates.append(("Sonnet", sonnet))
        }
        return candidates.max(by: { $0.1.utilization < $1.1.utilization }) ?? ("Session", data.fiveHour)
    }

    var body: some View {
        let (label, limit) = highestLimit

        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(UsageColor.forUtilization(data.highestUtilization))
                    .frame(width: 6, height: 6)
                Text("ClaudeQuota")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            CircularGaugeView(percentage: limit.utilization, lineWidth: 6, size: 64)

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)

            if let resetText = ResetTimeFormatter.format(limit.resetsAt, style: .countdown) {
                Text("Reset \(resetText)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

**Step 3: Create MediumWidgetView**

```swift
import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let data: UsageData

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(UsageColor.forUtilization(data.highestUtilization))
                    .frame(width: 6, height: 6)
                Text("ClaudeQuota")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(updatedText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                gaugeColumn(
                    label: "Session",
                    limit: data.fiveHour,
                    resetStyle: .countdown
                )

                gaugeColumn(
                    label: "Weekly",
                    limit: data.sevenDay,
                    resetStyle: .dayTime
                )

                if let sonnet = data.sevenDaySonnet {
                    gaugeColumn(
                        label: "Sonnet",
                        limit: sonnet,
                        resetStyle: .dayTime
                    )
                }

                if let credits = data.extraCredits {
                    VStack(spacing: 4) {
                        CircularGaugeView(
                            percentage: credits.utilization,
                            lineWidth: gaugeLineWidth,
                            size: gaugeSize
                        )
                        Text("Credits")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                        Text(String(format: "$%.0f/$%.0f", credits.used, credits.limit))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var gaugeSize: CGFloat {
        data.extraCredits != nil ? 48 : 56
    }

    private var gaugeLineWidth: CGFloat {
        data.extraCredits != nil ? 4 : 5
    }

    private func gaugeColumn(label: String, limit: RateLimit, resetStyle: ResetTimeFormatter.Style) -> some View {
        VStack(spacing: 4) {
            CircularGaugeView(percentage: limit.utilization, lineWidth: gaugeLineWidth, size: gaugeSize)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
            if let resetText = ResetTimeFormatter.format(limit.resetsAt, style: resetStyle) {
                Text(resetText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var updatedText: String {
        let seconds = Int(Date().timeIntervalSince(data.fetchedAt))
        if seconds < 60 { return "< 1 min ago" }
        return "\(seconds / 60)m ago"
    }
}
```

**Step 4: Build widget extension**

Run: `cd ClaudeQuota && xcodebuild -scheme ClaudeQuotaWidget -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
git add ClaudeQuota/Sources/Widget/
git commit -m "feat: add WidgetKit extension with small and medium widgets"
```

---

### Task 8: Wire Up App Lifecycle

**Files:**
- Modify: `ClaudeQuota/Sources/App/ClaudeQuotaApp.swift`

**Step 1: Add service start/stop to app lifecycle**

Update `ClaudeQuotaApp.swift` to start the service and respond to settings changes:

```swift
import SwiftUI

@main
struct ClaudeQuotaApp: App {
    @StateObject private var service = UsageService()
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60

    var body: some Scene {
        MenuBarExtra {
            PopoverView(service: service)
                .task {
                    service.start(interval: refreshInterval)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    service.stop()
                    service.start(interval: newValue)
                }
        } label: {
            MenuBarLabel(utilization: service.usageData.highestUtilization)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarLabel: View {
    let utilization: Int

    var body: some View {
        Image(systemName: menuBarIcon)
            .symbolRenderingMode(.palette)
            .foregroundStyle(UsageColor.forUtilization(utilization))
    }

    private var menuBarIcon: String {
        switch utilization {
        case ..<25: return "gauge.low"
        case ..<50: return "gauge.medium"
        case ..<80: return "gauge.high"
        default: return "gauge.high"
        }
    }
}
```

**Step 2: Build and run full app**

Run: `cd ClaudeQuota && xcodebuild -scheme ClaudeQuota -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 3: Manual verification**

- Run the app, verify menu bar icon appears
- Click icon, verify popover shows with usage data
- Verify data refreshes on timer
- Add small and medium widgets to desktop, verify they display data

**Step 4: Commit**

```bash
git add ClaudeQuota/Sources/App/ClaudeQuotaApp.swift
git commit -m "feat: wire up app lifecycle with service start and settings sync"
```

---

### Task 9: Polish & Final Build

**Step 1: Add `.gitignore`**

Create `.gitignore` in project root:

```
# Xcode
ClaudeQuota/*.xcodeproj
ClaudeQuota/build/
*.xcuserdata
*.xcworkspace
DerivedData/
*.hmap
*.ipa
*.dSYM.zip
*.dSYM

# macOS
.DS_Store

# Dependencies
.build/
```

**Step 2: Full clean build**

Run: `cd ClaudeQuota && xcodegen generate && xcodebuild -scheme ClaudeQuota -configuration Release build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 3: Run all tests**

Run: `cd ClaudeQuota && xcodebuild test -scheme ClaudeQuota -configuration Debug 2>&1 | tail -10`
Expected: All tests pass

**Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: add gitignore and verify clean release build"
```

---

## Task Summary

| Task | Description | Dependencies |
|------|-------------|-------------|
| 1 | Project scaffolding with XcodeGen | None |
| 2 | Shared models & color utilities | Task 1 |
| 3 | KeychainHelper | Task 1 |
| 4 | API client & UsageService | Tasks 2, 3 |
| 5 | Reusable UI components | Task 2 |
| 6 | Menu bar popover UI | Tasks 4, 5 |
| 7 | Widget extension | Tasks 2, 5 |
| 8 | Wire up app lifecycle | Task 6 |
| 9 | Polish & final build | All |

**Parallelizable:** Tasks 2, 3 can run in parallel. Tasks 5, 3 can run in parallel. Tasks 6, 7 can run in parallel.
