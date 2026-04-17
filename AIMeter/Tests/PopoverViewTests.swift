import XCTest
@testable import AIMeter

final class PopoverViewTests: XCTestCase {
    func testDecodedProviderOrderPreservesStoredOrderAndAppendsMissingTabs() {
        let order = decodedProviderOrder("claude,codex")

        XCTAssertEqual(order, [.claude, .codex, .copilot, .glm, .kimi, .minimax])
    }

    func testShortcutDigitUsesStoredProviderOrder() {
        let order: [Tab] = [.claude, .codex, .copilot, .glm, .kimi, .minimax]

        XCTAssertEqual(tabForShortcutDigit("2", providerOrder: order), .codex)
        XCTAssertEqual(tabForShortcutDigit("3", providerOrder: order), .copilot)
    }

    func testShortcutDigitReturnsNilOutsideProviderRange() {
        XCTAssertNil(tabForShortcutDigit("0", providerOrder: Tab.defaultOrder))
        XCTAssertNil(tabForShortcutDigit("7", providerOrder: Tab.defaultOrder))
        XCTAssertNil(tabForShortcutDigit("x", providerOrder: Tab.defaultOrder))
    }
}
