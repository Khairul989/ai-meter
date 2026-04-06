import XCTest
@testable import AIMeter

final class CodexProxyRoutingTests: XCTestCase {
    func testPreferredAccountWinsWhenReady() {
        let now = Date(timeIntervalSince1970: 1_000)
        let states = [
            "primary": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil),
            "fallback": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil)
        ]

        let ordered = CodexAccountRouting.orderedAccountIDs(
            accountIds: ["primary", "fallback"],
            preferredAccountId: "primary",
            lastRoutedAccountId: "fallback",
            states: states,
            now: now
        )

        XCTAssertEqual(ordered, ["primary", "fallback"])
    }

    func testRateLimitedPreferredFallsBackToNextReadyAccount() {
        let now = Date(timeIntervalSince1970: 1_000)
        let states = [
            "primary": CodexAccountRouting.rateLimitedState(retryAfter: 120, now: now, message: nil),
            "fallback": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil)
        ]

        let ordered = CodexAccountRouting.orderedAccountIDs(
            accountIds: ["primary", "fallback"],
            preferredAccountId: "primary",
            lastRoutedAccountId: nil,
            states: states,
            now: now
        )

        XCTAssertEqual(ordered, ["fallback"])
    }

    func testExpiredRateLimitBecomesEligibleAgain() {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = CodexAccountState(
            status: .rateLimited,
            resetAt: now.addingTimeInterval(-5),
            updatedAt: now.addingTimeInterval(-10),
            message: "Retry after 5s"
        )

        let normalized = CodexAccountRouting.normalizedState(state, now: now)

        XCTAssertEqual(normalized.status, .ready)
        XCTAssertNil(normalized.resetAt)
    }

    func testUnavailableCooldownBlocksImmediateReuse() {
        let now = Date(timeIntervalSince1970: 1_000)
        let states = [
            "a": CodexAccountState(status: .unavailable, resetAt: nil, updatedAt: now, message: "timeout"),
            "b": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil)
        ]

        let ordered = CodexAccountRouting.orderedAccountIDs(
            accountIds: ["a", "b"],
            preferredAccountId: nil,
            lastRoutedAccountId: nil,
            states: states,
            now: now
        )

        XCTAssertEqual(ordered, ["b"])
    }

    func testFallbackAccountsRotateAfterLastRoutedAccount() {
        let now = Date(timeIntervalSince1970: 1_000)
        let states = [
            "a": CodexAccountState(status: .rateLimited, resetAt: now.addingTimeInterval(60), updatedAt: now, message: nil),
            "b": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil),
            "c": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil)
        ]

        let ordered = CodexAccountRouting.orderedAccountIDs(
            accountIds: ["a", "b", "c"],
            preferredAccountId: "a",
            lastRoutedAccountId: "b",
            states: states,
            now: now
        )

        XCTAssertEqual(ordered, ["c", "b"])
    }

    func testUnauthorizedAccountsAreSkipped() {
        let now = Date(timeIntervalSince1970: 1_000)
        let states = [
            "a": CodexAccountState(status: .unauthorized, resetAt: nil, updatedAt: now, message: nil),
            "b": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil)
        ]

        let ordered = CodexAccountRouting.orderedAccountIDs(
            accountIds: ["a", "b"],
            preferredAccountId: "a",
            lastRoutedAccountId: nil,
            states: states,
            now: now
        )

        XCTAssertEqual(ordered, ["b"])
    }

    func testRotateReturnsUnchangedWhenAnchorIsLastElement() {
        let now = Date(timeIntervalSince1970: 1_000)
        let states = [
            "a": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil),
            "b": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil),
            "c": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil)
        ]

        let ordered = CodexAccountRouting.orderedAccountIDs(
            accountIds: ["a", "b", "c"],
            preferredAccountId: nil,
            lastRoutedAccountId: "c",
            states: states,
            now: now
        )

        XCTAssertEqual(ordered, ["a", "b", "c"])
    }

    func testNewAccountWithNoStateIsTreatedAsEligible() {
        let now = Date(timeIntervalSince1970: 1_000)
        let states: [String: CodexAccountState] = [:]

        let ordered = CodexAccountRouting.orderedAccountIDs(
            accountIds: ["new-account"],
            preferredAccountId: nil,
            lastRoutedAccountId: nil,
            states: states,
            now: now
        )

        XCTAssertEqual(ordered, ["new-account"])
    }

    func testAllAccountsExcludedReturnsEmpty() {
        let now = Date(timeIntervalSince1970: 1_000)
        let states = [
            "a": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil),
            "b": CodexAccountState(status: .ready, resetAt: nil, updatedAt: now, message: nil)
        ]

        let ordered = CodexAccountRouting.orderedAccountIDs(
            accountIds: ["a", "b"],
            preferredAccountId: nil,
            lastRoutedAccountId: nil,
            states: states,
            excluding: ["a", "b"],
            now: now
        )

        XCTAssertEqual(ordered, [])
    }
}
