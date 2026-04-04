import XCTest
@testable import AIMeter

final class KimiUsageDataTests: XCTestCase {
    func testUtilizationPercentClampsValuesAboveOneHundred() {
        let data = KimiUsageData(
            scope: "FEATURE_CODING",
            detail: KimiUsageDetail(limit: 100, used: 180, remaining: 0, resetTime: nil),
            limits: [],
            fetchedAt: Date()
        )

        XCTAssertEqual(data.utilizationPercent, 100)
    }

    func testUtilizationPercentReturnsZeroWhenLimitIsZero() {
        let data = KimiUsageData(
            scope: "FEATURE_CODING",
            detail: KimiUsageDetail(limit: 0, used: 50, remaining: 0, resetTime: nil),
            limits: [],
            fetchedAt: Date()
        )

        XCTAssertEqual(data.utilizationPercent, 0)
    }
}
