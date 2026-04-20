import XCTest
@testable import AIMeter

final class APIClientTests: XCTestCase {
    func testParseAPIResponse() throws {
        let json = """
        {
            "five_hour": {"utilization": 37, "resets_at": "2026-02-26T10:00:00.000Z"},
            "seven_day": {"utilization": 54, "resets_at": "2026-02-27T03:00:00.000Z"},
            "seven_day_sonnet": {"utilization": 3, "resets_at": "2026-02-27T04:00:00.000Z"},
            "seven_day_omelette": {"utilization": 43, "resets_at": "2026-02-28T04:00:00.000Z"}
        }
        """.data(using: .utf8)!
        let usage = try APIClient.parseResponse(json)
        XCTAssertEqual(usage.fiveHour.utilization, 37)
        XCTAssertEqual(usage.sevenDay.utilization, 54)
        XCTAssertEqual(usage.sevenDaySonnet?.utilization, 3)
        XCTAssertEqual(usage.sevenDayDesign?.utilization, 43)
        XCTAssertNil(usage.extraCredits) // fetched separately
    }

    func testParseResponseWithoutOptionals() throws {
        let json = """
        {
            "five_hour": {"utilization": 10, "resets_at": "2026-02-26T10:00:00.000Z"},
            "seven_day": {"utilization": 20, "resets_at": "2026-02-27T03:00:00.000Z"}
        }
        """.data(using: .utf8)!
        let usage = try APIClient.parseResponse(json)
        XCTAssertEqual(usage.fiveHour.utilization, 10)
        XCTAssertNil(usage.sevenDaySonnet)
        XCTAssertNil(usage.sevenDayDesign)
        XCTAssertNil(usage.extraCredits)
    }

    func testParsePermissionError() {
        let json = """
        {"error": {"type": "permission_error", "message": "Invalid session"}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try APIClient.parseResponse(json)) { error in
            XCTAssertEqual(error as? APIError, .sessionExpired)
        }
    }

    func testParseExtraUsageCredits() {
        let json = """
        {
            "spend_limit_amount_cents": 2500,
            "balance_cents": 1250
        }
        """.data(using: .utf8)!

        let credits = APIClient.parseExtraUsage(json)
        XCTAssertEqual(credits?.limit, 25.0)
        XCTAssertEqual(credits?.used, 12.5)
        XCTAssertEqual(credits?.utilization, 50)
    }

    func testParsePlanNameFromBootstrapTier() {
        XCTAssertEqual(SessionAuthManager.parsePlanName(rateLimitTier: "default_claude_max_20x"), "Max 20×")
        XCTAssertEqual(SessionAuthManager.parsePlanName(rateLimitTier: "default_claude_pro"), "Pro")
        XCTAssertNil(SessionAuthManager.parsePlanName(rateLimitTier: "auto_api_evaluation"))
    }
}
