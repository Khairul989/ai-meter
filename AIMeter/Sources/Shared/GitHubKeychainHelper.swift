import Foundation
import Security

enum GitHubKeychainHelper {
    private static let serviceName = "gh:github.com"
    private static let base64Prefix = "go-keyring-base64:"

    /// Read the GitHub OAuth token from the gh CLI Keychain entry
    static func readAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let rawValue = String(data: data, encoding: .utf8)
        else { return nil }

        return extractToken(from: rawValue)
    }

    /// Decode a go-keyring-base64 encoded value to extract the gho_* token (testable)
    static func extractToken(from rawValue: String) -> String? {
        guard rawValue.hasPrefix(base64Prefix) else { return nil }

        let encoded = String(rawValue.dropFirst(base64Prefix.count))
        guard !encoded.isEmpty,
              let data = Data(base64Encoded: encoded),
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }

        return token
    }
}
