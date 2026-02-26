import XCTest
@testable import AIMeter

final class APIClientTests: XCTestCase {
    func testParseAPIResponse() throws {
        let json = """
        {
            "five_hour": {"utilization": 37, "resets_at": "2026-02-26T10:00:00.000Z"},
            "seven_day": {"utilization": 54, "resets_at": "2026-02-27T03:00:00.000Z"},
            "seven_day_sonnet": {"utilization": 3, "resets_at": "2026-02-27T04:00:00.000Z"},
            "extra_usage": {
                "is_enabled": true,
                "monthly_limit": 20.0,
                "used_credits": 2.4,
                "utilization": 12
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
            "five_hour": {"utilization": 10, "resets_at": "2026-02-26T10:00:00.000Z"},
            "seven_day": {"utilization": 20, "resets_at": "2026-02-27T03:00:00.000Z"},
            "extra_usage": {"is_enabled": false}
        }
        """.data(using: .utf8)!
        let usage = try APIClient.parseResponse(json)
        XCTAssertEqual(usage.fiveHour.utilization, 10)
        XCTAssertNil(usage.sevenDaySonnet)
        XCTAssertNil(usage.extraCredits)
    }
}
