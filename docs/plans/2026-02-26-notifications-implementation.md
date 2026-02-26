# Notifications Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fire native macOS local notifications when any AI quota metric crosses a configurable warning or critical utilization threshold.

**Architecture:** A single `NotificationManager` singleton handles all threshold logic and `UNUserNotificationCenter` calls. Services pass `MetricSnapshot` arrays after each successful fetch. A `NotificationTracker` struct persisted in `UserDefaults` prevents repeat notifications for the same crossing; it resets when utilization drops below warning.

**Tech Stack:** UserNotifications framework, `UNUserNotificationCenter`, `@AppStorage`, SwiftUI `Picker` / `Toggle`.

---

## Task 1: NotificationManager — core types and logic

**Files:**
- Create: `AIMeter/Sources/Shared/NotificationManager.swift`

### Step 1: Create the file with all types

```swift
import Foundation
import UserNotifications

// MARK: - Types

enum NotificationLevel: Int, Codable, Comparable {
    case none = 0
    case warning = 1
    case critical = 2

    static func < (lhs: NotificationLevel, rhs: NotificationLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct MetricSnapshot {
    let key: String        // e.g. "claude.session"
    let label: String      // e.g. "Claude Session" — used in notification title
    let utilization: Int   // 0-100
    let detail: String?    // used as notification body, e.g. "Resets in 3h" or "42/300 remaining"
}

struct NotificationTracker: Codable {
    var levels: [String: NotificationLevel] = [:]

    func level(for key: String) -> NotificationLevel {
        levels[key] ?? .none
    }

    mutating func set(_ key: String, to level: NotificationLevel) {
        levels[key] = level
    }
}

// MARK: - Manager

final class NotificationManager {
    static let shared = NotificationManager()

    private let defaults = UserDefaults.standard

    // Internal so tests can read it directly
    var tracker: NotificationTracker {
        get {
            guard let data = defaults.data(forKey: "notificationTracker"),
                  let decoded = try? JSONDecoder().decode(NotificationTracker.self, from: data)
            else { return NotificationTracker() }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "notificationTracker")
            }
        }
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(metrics: [MetricSnapshot]) {
        guard defaults.bool(forKey: "notificationsEnabled") else { return }
        let warnThreshold = defaults.integer(forKey: "notifyWarning").nonZeroOrDefault(80)
        let critThreshold = defaults.integer(forKey: "notifyCritical").nonZeroOrDefault(90)

        var tracker = self.tracker
        for metric in metrics {
            let current = level(for: metric.utilization, warning: warnThreshold, critical: critThreshold)
            let previous = tracker.level(for: metric.key)

            if current > previous {
                fire(metric: metric, level: current)
                tracker.set(metric.key, to: current)
            } else if current == .none {
                // Reset so future crossings notify again
                tracker.set(metric.key, to: .none)
            }
        }
        self.tracker = tracker
    }

    // Internal so tests can call directly
    func level(for utilization: Int, warning: Int, critical: Int) -> NotificationLevel {
        if utilization >= critical { return .critical }
        if utilization >= warning { return .warning }
        return .none
    }

    private func fire(metric: MetricSnapshot, level: NotificationLevel) {
        let content = UNMutableNotificationContent()
        let prefix = level == .critical ? "⚠️ " : ""
        content.title = "\(prefix)\(metric.label) at \(metric.utilization)%"
        if let detail = metric.detail { content.body = detail }
        let request = UNNotificationRequest(
            identifier: "\(metric.key).\(level.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - MetricSnapshot factories

    static func metrics(from data: UsageData) -> [MetricSnapshot] {
        var result: [MetricSnapshot] = [
            MetricSnapshot(
                key: "claude.session",
                label: "Claude Session",
                utilization: data.fiveHour.utilization,
                detail: ResetTimeFormatter.format(data.fiveHour.resetsAt, style: .countdown, timeZone: .current)
            ),
            MetricSnapshot(
                key: "claude.weekly",
                label: "Claude Weekly",
                utilization: data.sevenDay.utilization,
                detail: ResetTimeFormatter.format(data.sevenDay.resetsAt, style: .dayTime, timeZone: .current)
            )
        ]
        if let sonnet = data.sevenDaySonnet {
            result.append(MetricSnapshot(
                key: "claude.sonnet",
                label: "Claude Sonnet",
                utilization: sonnet.utilization,
                detail: ResetTimeFormatter.format(sonnet.resetsAt, style: .dayTime, timeZone: .current)
            ))
        }
        if let credits = data.extraCredits {
            result.append(MetricSnapshot(
                key: "claude.credits",
                label: "Claude Credits",
                utilization: credits.utilization,
                detail: String(format: "$%.2f remaining", (credits.limit - credits.used) / 100)
            ))
        }
        return result
    }

    static func metrics(from data: CopilotUsageData) -> [MetricSnapshot] {
        guard !data.premiumInteractions.unlimited else { return [] }
        return [MetricSnapshot(
            key: "copilot.premium",
            label: "Copilot Premium",
            utilization: data.premiumInteractions.utilization,
            detail: "\(data.premiumInteractions.remaining)/\(data.premiumInteractions.entitlement) remaining"
        )]
    }
}

// MARK: - Helpers

private extension Int {
    func nonZeroOrDefault(_ value: Int) -> Int {
        self == 0 ? value : self
    }
}
```

### Step 2: Build the app target to confirm it compiles

In Xcode: **Product → Build** (⌘B) with AIMeter scheme selected.

Expected: Build succeeded, no errors.

---

## Task 2: Tests for NotificationManager

**Files:**
- Create: `AIMeter/Tests/NotificationManagerTests.swift`

### Step 1: Write the tests

```swift
import XCTest
@testable import AIMeter

final class NotificationManagerTests: XCTestCase {
    var manager: NotificationManager!

    override func setUp() {
        super.setUp()
        manager = NotificationManager()
    }

    // MARK: - Level calculation

    func testLevelNoneWhenBelowWarning() {
        XCTAssertEqual(manager.level(for: 79, warning: 80, critical: 90), .none)
    }

    func testLevelWarningAtExactThreshold() {
        XCTAssertEqual(manager.level(for: 80, warning: 80, critical: 90), .warning)
    }

    func testLevelWarningBetweenThresholds() {
        XCTAssertEqual(manager.level(for: 85, warning: 80, critical: 90), .warning)
    }

    func testLevelCriticalAtExactThreshold() {
        XCTAssertEqual(manager.level(for: 90, warning: 80, critical: 90), .critical)
    }

    func testLevelCriticalAboveThreshold() {
        XCTAssertEqual(manager.level(for: 100, warning: 80, critical: 90), .critical)
    }

    func testLevelNoneAtZero() {
        XCTAssertEqual(manager.level(for: 0, warning: 80, critical: 90), .none)
    }

    // MARK: - NotificationLevel ordering

    func testLevelOrdering() {
        XCTAssertLessThan(NotificationLevel.none, .warning)
        XCTAssertLessThan(NotificationLevel.warning, .critical)
        XCTAssertGreaterThan(NotificationLevel.critical, .none)
    }

    // MARK: - NotificationTracker

    func testTrackerDefaultsToNone() {
        let tracker = NotificationTracker()
        XCTAssertEqual(tracker.level(for: "claude.session"), .none)
        XCTAssertEqual(tracker.level(for: "unknown.key"), .none)
    }

    func testTrackerUpdatesLevel() {
        var tracker = NotificationTracker()
        tracker.set("claude.session", to: .warning)
        XCTAssertEqual(tracker.level(for: "claude.session"), .warning)
    }

    func testTrackerResetsToNone() {
        var tracker = NotificationTracker()
        tracker.set("claude.session", to: .critical)
        tracker.set("claude.session", to: .none)
        XCTAssertEqual(tracker.level(for: "claude.session"), .none)
    }

    func testTrackerIndependentKeys() {
        var tracker = NotificationTracker()
        tracker.set("claude.session", to: .warning)
        tracker.set("claude.weekly", to: .critical)
        XCTAssertEqual(tracker.level(for: "claude.session"), .warning)
        XCTAssertEqual(tracker.level(for: "claude.weekly"), .critical)
    }

    // MARK: - MetricSnapshot from UsageData

    func testMetricsFromUsageDataBaseCase() {
        let data = UsageData(
            fiveHour: RateLimit(utilization: 37, resetsAt: nil),
            sevenDay: RateLimit(utilization: 54, resetsAt: nil),
            sevenDaySonnet: nil,
            extraCredits: nil,
            fetchedAt: Date()
        )
        let metrics = NotificationManager.metrics(from: data)
        XCTAssertEqual(metrics.count, 2)
        XCTAssertEqual(metrics[0].key, "claude.session")
        XCTAssertEqual(metrics[0].utilization, 37)
        XCTAssertEqual(metrics[1].key, "claude.weekly")
        XCTAssertEqual(metrics[1].utilization, 54)
    }

    func testMetricsFromUsageDataWithAllOptionals() {
        let data = UsageData(
            fiveHour: RateLimit(utilization: 10, resetsAt: nil),
            sevenDay: RateLimit(utilization: 20, resetsAt: nil),
            sevenDaySonnet: RateLimit(utilization: 80, resetsAt: nil),
            extraCredits: ExtraCredits(utilization: 50, used: 2500, limit: 5000),
            fetchedAt: Date()
        )
        let metrics = NotificationManager.metrics(from: data)
        XCTAssertEqual(metrics.count, 4)
        XCTAssertTrue(metrics.contains { $0.key == "claude.sonnet" && $0.utilization == 80 })
        XCTAssertTrue(metrics.contains { $0.key == "claude.credits" && $0.utilization == 50 })
    }

    func testMetricsFromUsageDataCreditsDetail() {
        let data = UsageData(
            fiveHour: RateLimit(utilization: 0, resetsAt: nil),
            sevenDay: RateLimit(utilization: 0, resetsAt: nil),
            sevenDaySonnet: nil,
            extraCredits: ExtraCredits(utilization: 50, used: 1000, limit: 5000),
            fetchedAt: Date()
        )
        let metrics = NotificationManager.metrics(from: data)
        let credits = metrics.first { $0.key == "claude.credits" }
        // (5000 - 1000) / 100 = $40.00 remaining
        XCTAssertEqual(credits?.detail, "$40.00 remaining")
    }

    // MARK: - MetricSnapshot from CopilotUsageData

    func testMetricsFromCopilotSkipsUnlimitedPremium() {
        let data = CopilotUsageData(
            plan: "business",
            chat: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            completions: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            premiumInteractions: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            resetDate: nil,
            fetchedAt: Date()
        )
        XCTAssertTrue(NotificationManager.metrics(from: data).isEmpty)
    }

    func testMetricsFromCopilotIncludesPremiumWhenLimited() {
        let data = CopilotUsageData(
            plan: "individual",
            chat: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            completions: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            premiumInteractions: CopilotQuota(utilization: 88, remaining: 35, entitlement: 300, unlimited: false),
            resetDate: nil,
            fetchedAt: Date()
        )
        let metrics = NotificationManager.metrics(from: data)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics[0].key, "copilot.premium")
        XCTAssertEqual(metrics[0].utilization, 88)
        XCTAssertEqual(metrics[0].label, "Copilot Premium")
        XCTAssertEqual(metrics[0].detail, "35/300 remaining")
    }
}
```

### Step 2: Run tests

In Xcode: **Product → Test** (⌘U), or run the `AIMeterTests` target.

Expected: All new tests pass. Existing 19 tests still pass.

### Step 3: Commit

```bash
git add AIMeter/Sources/Shared/NotificationManager.swift AIMeter/Tests/NotificationManagerTests.swift
git commit -m "feat: add NotificationManager with threshold logic and metric factories"
```

---

## Task 3: Wire UsageService to NotificationManager

**Files:**
- Modify: `AIMeter/Sources/App/UsageService.swift`

### Step 1: Add the call after a successful fetch

In `UsageService.fetch()`, after `SharedDefaults.save(data)`, add:

```swift
NotificationManager.shared.check(metrics: NotificationManager.metrics(from: data))
```

The full `fetch()` method after the change:

```swift
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
        WidgetCenter.shared.reloadAllTimelines()
        NotificationManager.shared.check(metrics: NotificationManager.metrics(from: data))
    } catch {
        self.isStale = true
        self.error = .fetchFailed
    }
}
```

### Step 2: Build to confirm

**Product → Build** (⌘B). Expected: Build succeeded.

---

## Task 4: Wire CopilotService to NotificationManager

**Files:**
- Modify: `AIMeter/Sources/App/CopilotService.swift`

### Step 1: Add the call after a successful fetch

In `CopilotService.fetch()`, after `SharedDefaults.saveCopilot(data)`, add:

```swift
NotificationManager.shared.check(metrics: NotificationManager.metrics(from: data))
```

The full `fetch()` method after the change:

```swift
func fetch() async {
    guard let token = GitHubKeychainHelper.readAccessToken() else {
        self.error = .noToken
        return
    }

    do {
        let data = try await CopilotAPIClient.fetchUsage(token: token)
        self.copilotData = data
        self.isStale = false
        self.error = nil
        SharedDefaults.saveCopilot(data)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationManager.shared.check(metrics: NotificationManager.metrics(from: data))
    } catch {
        self.isStale = true
        self.error = .fetchFailed
    }
}
```

### Step 2: Build to confirm

**Product → Build** (⌘B). Expected: Build succeeded.

### Step 3: Commit

```bash
git add AIMeter/Sources/App/UsageService.swift AIMeter/Sources/App/CopilotService.swift
git commit -m "feat: wire UsageService and CopilotService to NotificationManager"
```

---

## Task 5: Add notification settings to InlineSettingsView

**Files:**
- Modify: `AIMeter/Sources/App/PopoverView.swift`

### Step 1: Add @AppStorage properties to InlineSettingsView

At the top of `InlineSettingsView`, after the existing `@AppStorage` and `@State` declarations, add:

```swift
@AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
@AppStorage("notifyWarning") private var notifyWarning: Int = 80
@AppStorage("notifyCritical") private var notifyCritical: Int = 90
```

### Step 2: Add notifications section to the body VStack

Add this block **before** the `Toggle("Launch at login", ...)` block:

```swift
VStack(alignment: .leading, spacing: 8) {
    Toggle("Enable notifications", isOn: $notificationsEnabled)
        .font(.system(size: 12))
        .onChange(of: notificationsEnabled) { _, newValue in
            if newValue {
                NotificationManager.shared.requestPermission()
            }
        }

    if notificationsEnabled {
        Text("Warning threshold")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        Picker("", selection: $notifyWarning) {
            Text("50%").tag(50)
            Text("75%").tag(75)
            Text("80%").tag(80)
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        Text("Critical threshold")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        Picker("", selection: $notifyCritical) {
            Text("85%").tag(85)
            Text("90%").tag(90)
            Text("95%").tag(95)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
```

### Step 3: Build to confirm

**Product → Build** (⌘B). Expected: Build succeeded.

### Step 4: Manual test

1. Run the app (AIMeter scheme)
2. Open the popover → tap the gear icon
3. Verify "Enable notifications" toggle appears
4. Enable it — macOS should show a permission dialog
5. Allow notifications
6. Warning/critical threshold pickers should appear
7. Change thresholds, verify they persist after closing and reopening the popover

### Step 5: Commit

```bash
git add AIMeter/Sources/App/PopoverView.swift
git commit -m "feat: add notification settings (enable toggle, warning/critical thresholds)"
```

---

## Task 6: Run all tests and final commit

### Step 1: Run full test suite

**Product → Test** (⌘U).

Expected: All tests pass (should be 19 existing + ~14 new = ~33 total).

### Step 2: Confirm no regressions in the UI

Run the app, open the popover, verify:
- Claude and Copilot sections still show correctly
- Settings panel shows the new notifications section
- Gear/xmark toggle still works

### Step 3: Final commit (if any loose files)

```bash
git status
# Should be clean after all previous commits
```
