import Foundation
import Security
import os

enum CodexSessionKeychain {
    private static let serviceName = "com.khairul.aimeter.codex"
    private static let logger = Logger(subsystem: "com.khairul.aimeter", category: "CodexKeychain")

    enum Account: String, CaseIterable {
        case accessToken
        case email
        case planType
        case idToken
        case refreshToken
        case expiresAt
        case chatGPTAccountId
    }

    static func save(account: Account, value: String) {
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save keychain item for account \(account.rawValue), status \(status)")
        }
    }

    static func read(account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty
        else { return nil }
        return str
    }

    static func delete(account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        for account in Account.allCases {
            delete(account: account)
        }
    }

    // MARK: - Account-scoped methods (namespaced by accountId/email)

    static func save(account: Account, accountId: String, value: String) {
        let key = "\(account.rawValue):\(accountId)"
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save keychain item for account \(key), status \(status)")
        }
    }

    static func read(account: Account, accountId: String) -> String? {
        let key = "\(account.rawValue):\(accountId)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty
        else { return nil }
        return str
    }

    static func delete(account: Account, accountId: String) {
        let key = "\(account.rawValue):\(accountId)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll(accountId: String) {
        for account in Account.allCases {
            delete(account: account, accountId: accountId)
        }
    }

    // MARK: - Account ID registry

    static func savedAccountIds() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "accountIds",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return ids
    }

    static func addAccountId(_ id: String) {
        var ids = savedAccountIds()
        guard !ids.contains(id) else { return }
        ids.append(id)
        saveAccountIds(ids)
    }

    static func removeAccountId(_ id: String) {
        var ids = savedAccountIds()
        ids.removeAll { $0 == id }
        saveAccountIds(ids)
    }

    // Persists the accountIds list to keychain as JSON
    private static func saveAccountIds(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "accountIds"
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "accountIds",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save accountIds to keychain, status \(status)")
        }
    }
}
