import XCTest
@testable import AIMeter

final class ResetTimeFormatterTests: XCTestCase {
    func testCountdownFormat() {
        let now = Date()
        let future = now.addingTimeInterval(3 * 3600 + 15 * 60) // 3h 15m
        let result = ResetTimeFormatter.format(future, style: .countdown, now: now)
        XCTAssertEqual(result, "3h 15m")
    }

    func testCountdownZero() {
        let now = Date()
        let result = ResetTimeFormatter.format(now, style: .countdown, now: now)
        XCTAssertEqual(result, "0h 0m")
    }

    func testNilDate() {
        let result = ResetTimeFormatter.format(nil, style: .countdown)
        XCTAssertNil(result)
    }

    func testPastDateCountdown() {
        let now = Date()
        let past = now.addingTimeInterval(-60)
        let result = ResetTimeFormatter.format(past, style: .countdown, now: now)
        XCTAssertNil(result) // negative values return nil
    }

    func testDayTimeFormat() {
        // Create a known date: Thursday 11:00 AM UTC
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: 2026, month: 3, day: 12, hour: 11, minute: 0)
        let date = cal.date(from: components)!
        let result = ResetTimeFormatter.format(date, style: .dayTime, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertNotNil(result)
        // Should contain "11:00am" in some day format
        XCTAssertTrue(result!.contains("11:00am"))
    }
}
