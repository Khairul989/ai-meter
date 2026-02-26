import XCTest
@testable import AIMeter

final class CopilotAPIClientTests: XCTestCase {
    // Real response with unlimited chat/completions and 11.72% premium remaining
    private let fullResponseJSON = """
    {
      "copilot_plan": "individual",
      "quota_reset_date_utc": "2026-03-01T00:00:00.000Z",
      "quota_snapshots": {
        "chat": {"entitlement": 0, "remaining": 0, "percent_remaining": 100.0, "unlimited": true},
        "completions": {"entitlement": 0, "remaining": 0, "percent_remaining": 100.0, "unlimited": true},
        "premium_interactions": {"entitlement": 300, "remaining": 35, "percent_remaining": 11.72, "unlimited": false}
      }
    }
    """.data(using: .utf8)!

    func testParseFullResponse() throws {
        let usage = try CopilotAPIClient.parseResponse(fullResponseJSON)

        XCTAssertEqual(usage.plan, "individual")
        XCTAssertNotNil(usage.resetDate)

        // chat: unlimited
        XCTAssertTrue(usage.chat.unlimited)
        XCTAssertEqual(usage.chat.utilization, 0)

        // completions: unlimited
        XCTAssertTrue(usage.completions.unlimited)
        XCTAssertEqual(usage.completions.utilization, 0)

        // premium_interactions: 11.72% remaining → 88% used
        XCTAssertFalse(usage.premiumInteractions.unlimited)
        XCTAssertEqual(usage.premiumInteractions.utilization, 88)
        XCTAssertEqual(usage.premiumInteractions.remaining, 35)
        XCTAssertEqual(usage.premiumInteractions.entitlement, 300)
    }

    func testUnlimitedQuotasHaveZeroUtilization() throws {
        let usage = try CopilotAPIClient.parseResponse(fullResponseJSON)

        XCTAssertEqual(usage.chat.utilization, 0)
        XCTAssertEqual(usage.completions.utilization, 0)
    }

    func testHighestUtilizationExcludesUnlimited() throws {
        let usage = try CopilotAPIClient.parseResponse(fullResponseJSON)

        // chat and completions are unlimited — only premium_interactions (88%) counts
        XCTAssertEqual(usage.highestUtilization, 88)
    }

    func testHighestUtilizationWhenAllUnlimited() {
        let allUnlimited = CopilotUsageData(
            plan: "business",
            chat: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            completions: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            premiumInteractions: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            resetDate: nil,
            fetchedAt: Date()
        )
        // No non-unlimited quotas → returns 0
        XCTAssertEqual(allUnlimited.highestUtilization, 0)
    }

    func testEmptyDefaults() {
        let empty = CopilotUsageData.empty
        XCTAssertEqual(empty.plan, "")
        XCTAssertEqual(empty.highestUtilization, 0)
        XCTAssertNil(empty.resetDate)
        XCTAssertEqual(empty.fetchedAt, .distantPast)
    }
}
