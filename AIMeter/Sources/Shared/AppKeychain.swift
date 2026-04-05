import Foundation
import Security
import os

enum AppKeychain {
    private static let serviceName = "com.khairul.aimeter"
    private static let accountName = "app-data"
    private static let logger = Logger(subsystem: "com.khairul.aimeter", category: "AppKeychain")

    // In-memory cache — loaded once from keychain, written back on changes
    private static var cache: [String: String] = [:]
    private static var loaded = false

    /// Get a value by key
    static func get(_ key: String) -> String? {
        loadIfNeeded()
        return cache[key]
    }

    /// Set a value (nil to delete)
    static func set(_ key: String, value: String?) {
        loadIfNeeded()
        if let value {
            cache[key] = value
        } else {
            cache.removeValue(forKey: key)
        }
        persist()
    }

    /// Get all keys matching a prefix
    static func keys(withPrefix prefix: String) -> [String] {
        loadIfNeeded()
        return cache.keys.filter { $0.hasPrefix(prefix) }
    }

    /// Remove all keys matching a prefix
    static func removeAll(withPrefix prefix: String) {
        loadIfNeeded()
        let matching = cache.keys.filter { $0.hasPrefix(prefix) }
        for key in matching {
            cache.removeValue(forKey: key)
        }
        if !matching.isEmpty {
            persist()
        }
    }

    /// Check if any data exists in the keychain
    static func isEmpty() -> Bool {
        loadIfNeeded()
        return cache.isEmpty
    }

    // MARK: - Private

    private static func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            cache = [:]
            return
        }

        cache = dict
    }

    private static func persist() {
        guard let data = try? JSONEncoder().encode(cache) else {
            logger.error("Failed to encode keychain cache")
            return
        }

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to persist keychain cache, status \(status)")
        }
    }
}
