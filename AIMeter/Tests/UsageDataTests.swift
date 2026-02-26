import XCTest
@testable import AIMeter

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
