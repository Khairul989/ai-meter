import Foundation
import Security
import os

struct APIKeyKeychainHelper {
    let serviceName: String
    private static let logger = Logger(subsystem: "com.khairul.aimeter", category: "APIKeyKeychain")

    static let glm = APIKeyKeychainHelper(serviceName: "glm-api-key")
    static let kimi = APIKeyKeychainHelper(serviceName: "kimi-api-key")
    static let minimax = APIKeyKeychainHelper(serviceName: "minimax-api-key")

    /// Read API key from Keychain
    func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    /// Save API key to Keychain, replacing any existing value
    func saveAPIKey(_ key: String) {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let data = Data(key.utf8)
        // Delete existing first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            Self.logger.error("Failed to save API key for service \(self.serviceName), status \(status)")
        }
    }

    /// Delete API key from Keychain
    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }
}
