import XCTest
@testable import AIMeter

@MainActor
final class ClaudeCodeStatsServiceTests: XCTestCase {
    func testShortNameOpus() {
        XCTAssertEqual(ClaudeCodeStatsService.shortName("claude-opus-4-6"), "Opus 4.6")
    }

    func testShortNameOpus47() {
        XCTAssertEqual(ClaudeCodeStatsService.shortName("claude-opus-4-7"), "Opus 4.7")
    }

    func testShortNameSonnet() {
        XCTAssertEqual(ClaudeCodeStatsService.shortName("claude-sonnet-4-6"), "Sonnet 4.6")
    }

    func testShortNameHaikuWithDateSuffix() {
        XCTAssertEqual(ClaudeCodeStatsService.shortName("claude-haiku-4-5-20251001"), "Haiku 4.5")
    }

    func testShortNameLegacyClaude3Format() {
        XCTAssertEqual(ClaudeCodeStatsService.shortName("claude-3-7-sonnet-20250219"), "Sonnet 3.7")
    }

    func testShortNamePreservesMeaningfulSuffixes() {
        XCTAssertEqual(ClaudeCodeStatsService.shortName("claude-opus-4-5-thinking"), "Opus 4.5 Thinking")
    }

    func testShortNameNoPrefix() {
        XCTAssertEqual(ClaudeCodeStatsService.shortName("some-model"), "Some Model")
    }

    func testClaudeModelSupportsNewOpusRelease() {
        XCTAssertTrue(ClaudeCodeStatsService.isClaudeModel("claude-opus-4-7"))
    }

    func testClaudeModelSupportsOlderSnapshotsAndLegacyFamilies() {
        XCTAssertTrue(ClaudeCodeStatsService.isClaudeModel("claude-sonnet-4-20250514"))
        XCTAssertTrue(ClaudeCodeStatsService.isClaudeModel("claude-opus-4-5-thinking"))
        XCTAssertTrue(ClaudeCodeStatsService.isClaudeModel("claude-3-7-sonnet-20250219"))
    }

    func testClaudeModelSupportsUnknownFutureFamilyWithoutCodeChanges() {
        XCTAssertTrue(ClaudeCodeStatsService.isClaudeModel("claude-sonata-5-0"))
    }

    func testClaudeModelRejectsNonClaudePrefix() {
        XCTAssertFalse(ClaudeCodeStatsService.isClaudeModel("gpt-5"))
    }
}
