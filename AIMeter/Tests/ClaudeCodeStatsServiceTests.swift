import XCTest
@testable import AIMeter

@MainActor
final class ClaudeCodeStatsServiceTests: XCTestCase {
    func testShortNameOpus() {
        XCTAssertEqual(ClaudeCodeStatsService.shortName("claude-opus-4-6"), "opus-4-6")
    }

    func testShortNameSonnet() {
        XCTAssertEqual(ClaudeCodeStatsService.shortName("claude-sonnet-4-6"), "sonnet-4-6")
    }

    func testShortNameHaikuWithDateSuffix() {
        XCTAssertEqual(ClaudeCodeStatsService.shortName("claude-haiku-4-5-20251001"), "haiku-4-5")
    }

    func testShortNameNoPrefix() {
        // Edge case: no "claude-" prefix
        XCTAssertEqual(ClaudeCodeStatsService.shortName("some-model"), "some-model")
    }
}
