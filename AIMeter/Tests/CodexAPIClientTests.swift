import XCTest
@testable import AIMeter

final class CodexAPIClientTests: XCTestCase {
    // MARK: - parseResponse

    func testParseFullResponse() throws {
        let json = """
        {
          "plan_type": "team",
          "rate_limit": {
            "primary_window": {
              "used_percent": 42,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 16787,
              "reset_at": 1773652210
            },
            "secondary_window": {
              "used_percent": 15,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 603587,
              "reset_at": 1774239010
            }
          },
          "code_review_rate_limit": {
            "primary_window": {
              "used_percent": 7,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 604801,
              "reset_at": 1774240223
            }
          }
        }
        """.data(using: .utf8)!

        let data = try CodexAPIClient.parseResponse(json)
        XCTAssertEqual(data.planType, "team")
        XCTAssertEqual(data.primaryPercent, 42)
        XCTAssertEqual(data.secondaryPercent, 15)
        XCTAssertEqual(data.codeReviewPercent, 7)
        XCTAssertNotNil(data.primaryResetAt)
        XCTAssertNotNil(data.secondaryResetAt)
        XCTAssertEqual(data.primaryResetAt, Date(timeIntervalSince1970: 1773652210))
        XCTAssertEqual(data.secondaryResetAt, Date(timeIntervalSince1970: 1774239010))
    }

    func testParseNullSecondaryWindow() throws {
        let json = """
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 80,
              "reset_at": 1773652210
            },
            "secondary_window": null
          }
        }
        """.data(using: .utf8)!

        let data = try CodexAPIClient.parseResponse(json)
        XCTAssertEqual(data.planType, "pro")
        XCTAssertEqual(data.primaryPercent, 80)
        XCTAssertEqual(data.secondaryPercent, 0)
        XCTAssertEqual(data.codeReviewPercent, 0)
        XCTAssertNil(data.secondaryResetAt)
    }

    func testParseMissingCodeReviewRateLimit() throws {
        let json = """
        {
          "plan_type": "free",
          "rate_limit": {
            "primary_window": { "used_percent": 5, "reset_at": 1773652210 },
            "secondary_window": { "used_percent": 2, "reset_at": 1774239010 }
          }
        }
        """.data(using: .utf8)!

        let data = try CodexAPIClient.parseResponse(json)
        XCTAssertEqual(data.codeReviewPercent, 0)
        XCTAssertEqual(data.primaryPercent, 5)
        XCTAssertEqual(data.secondaryPercent, 2)
    }

    func testParseMinimalResponse() throws {
        let json = """
        {}
        """.data(using: .utf8)!

        let data = try CodexAPIClient.parseResponse(json)
        XCTAssertEqual(data.planType, "")
        XCTAssertEqual(data.primaryPercent, 0)
        XCTAssertEqual(data.secondaryPercent, 0)
        XCTAssertEqual(data.codeReviewPercent, 0)
        XCTAssertNil(data.primaryResetAt)
        XCTAssertNil(data.secondaryResetAt)
    }

    // MARK: - CodexUsageData model

    func testCodexUsageDataEmpty() {
        let empty = CodexUsageData.empty
        XCTAssertEqual(empty.planType, "")
        XCTAssertEqual(empty.primaryPercent, 0)
        XCTAssertEqual(empty.secondaryPercent, 0)
        XCTAssertEqual(empty.codeReviewPercent, 0)
        XCTAssertNil(empty.primaryResetAt)
        XCTAssertNil(empty.secondaryResetAt)
        XCTAssertEqual(empty.fetchedAt, .distantPast)
    }

    func testHighestUtilization() {
        let data = CodexUsageData(
            planType: "team",
            primaryPercent: 30,
            secondaryPercent: 75,
            codeReviewPercent: 10,
            primaryResetAt: nil,
            secondaryResetAt: nil,
            fetchedAt: .distantPast
        )
        XCTAssertEqual(data.highestUtilization, 75)
    }

    func testHighestUtilizationPrimaryHigher() {
        let data = CodexUsageData(
            planType: "pro",
            primaryPercent: 90,
            secondaryPercent: 20,
            codeReviewPercent: 5,
            primaryResetAt: nil,
            secondaryResetAt: nil,
            fetchedAt: .distantPast
        )
        XCTAssertEqual(data.highestUtilization, 90)
    }

    func testEquatable() {
        let a = CodexUsageData(
            planType: "team", primaryPercent: 50, secondaryPercent: 10,
            codeReviewPercent: 0, primaryResetAt: nil, secondaryResetAt: nil,
            fetchedAt: .distantPast
        )
        let b = CodexUsageData(
            planType: "team", primaryPercent: 50, secondaryPercent: 10,
            codeReviewPercent: 0, primaryResetAt: nil, secondaryResetAt: nil,
            fetchedAt: .distantPast
        )
        XCTAssertEqual(a, b)
    }
}
