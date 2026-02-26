import XCTest
@testable import AIMeter

final class KeychainHelperTests: XCTestCase {
    func testParseCredentialJSON() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"sk-ant-test-123","refreshToken":"rt-456"}}
        """
        let token = KeychainHelper.extractToken(from: json)
        XCTAssertEqual(token, "sk-ant-test-123")
    }

    func testParseInvalidJSON() {
        let token = KeychainHelper.extractToken(from: "not json")
        XCTAssertNil(token)
    }

    func testParseMissingToken() {
        let json = """
        {"claudeAiOauth":{}}
        """
        let token = KeychainHelper.extractToken(from: json)
        XCTAssertNil(token)
    }
}
