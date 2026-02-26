import XCTest
@testable import AIMeter

final class GitHubKeychainHelperTests: XCTestCase {
    // "gho_test123" base64-encoded is "Z2hvX3Rlc3QxMjM="
    func testDecodeValidToken() {
        let raw = "go-keyring-base64:Z2hvX3Rlc3QxMjM="
        let token = GitHubKeychainHelper.extractToken(from: raw)
        XCTAssertEqual(token, "gho_test123")
    }

    func testHandleInvalidBase64() {
        let raw = "go-keyring-base64:!!!not-valid-base64!!!"
        let token = GitHubKeychainHelper.extractToken(from: raw)
        XCTAssertNil(token)
    }

    func testHandleMissingPrefix() {
        let raw = "Z2hvX3Rlc3QxMjM="
        let token = GitHubKeychainHelper.extractToken(from: raw)
        XCTAssertNil(token)
    }

    func testHandleEmptyString() {
        let token = GitHubKeychainHelper.extractToken(from: "")
        XCTAssertNil(token)
    }

    func testHandlePrefixOnly() {
        let raw = "go-keyring-base64:"
        let token = GitHubKeychainHelper.extractToken(from: raw)
        XCTAssertNil(token)
    }
}
