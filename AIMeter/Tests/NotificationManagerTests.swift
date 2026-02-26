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
