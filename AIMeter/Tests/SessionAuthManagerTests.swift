import XCTest
@testable import AIMeter

@MainActor
final class SessionAuthManagerTests: XCTestCase {
    func testParseMax5x() {
        XCTAssertEqual(SessionAuthManager.parsePlanName(rateLimitTier: "default_claude_max_5x"), "Max 5×")
    }

    func testParseMax() {
        XCTAssertEqual(SessionAuthManager.parsePlanName(rateLimitTier: "default_claude_max"), "Max")
    }

    func testParsePro() {
        XCTAssertEqual(SessionAuthManager.parsePlanName(rateLimitTier: "default_claude_pro"), "Pro")
    }

    func testParseTeam() {
        XCTAssertEqual(SessionAuthManager.parsePlanName(rateLimitTier: "some_team_tier"), "Team")
    }

    func testParseEnterprise() {
        XCTAssertEqual(SessionAuthManager.parsePlanName(rateLimitTier: "enterprise_plan"), "Enterprise")
    }

    func testParseFree() {
        XCTAssertEqual(SessionAuthManager.parsePlanName(rateLimitTier: "free_tier"), "Free")
    }

    func testParseUnknown() {
        XCTAssertNil(SessionAuthManager.parsePlanName(rateLimitTier: "something_unknown"))
    }
}
