import Foundation
import Security

enum ClaudeProfileKeychainError: Error {
    case unhandled(OSStatus)
    case unexpectedData
}

/// Discrete per-profile Keychain helper.
/// Each profile = one kSecClassGenericPassword entry keyed by service "claude-<slug>".
/// Separate from AppKeychain (which stores all credentials in one JSON blob) so that
/// `security find-generic-password -s claude-<slug> -w` resolves from shell scripts.
enum ClaudeProfileKeychain {

    // Account name is the current OS user — scopes entries to the running user.
    private static var accountName: String { NSUserName() }

    private static func serviceName(for slug: String) -> String {
        "claude-\(slug)"
    }

    /// Store `token` for the given slug. Creates or overwrites the existing entry.
    /// Verifies by reading back before returning — throws `unexpectedData` if the
    /// round-trip value doesn't match.
    static func set(slug: String, token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw ClaudeProfileKeychainError.unexpectedData
        }

        // Delete-then-add (same pattern as AppKeychain.persist()) keeps the logic simple.
        try delete(slug: slug)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: slug),
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            // AfterFirstUnlock so direnv can read from background shells post-reboot.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ClaudeProfileKeychainError.unhandled(status)
        }

        // Verify by reading back — errSecSuccess from Add alone is insufficient.
        guard let verified = try get(slug: slug), verified == token else {
            throw ClaudeProfileKeychainError.unexpectedData
        }
    }

    /// Read the token for the given slug. Returns nil if no entry exists.
    static func get(slug: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: slug),
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ClaudeProfileKeychainError.unhandled(status)
        }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw ClaudeProfileKeychainError.unexpectedData
        }
        return token
    }

    /// Delete the Keychain entry for the given slug. No-op if the entry does not exist.
    static func delete(slug: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName(for: slug),
            kSecAttrAccount as String: accountName
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ClaudeProfileKeychainError.unhandled(status)
        }
    }

    /// Returns true if an entry for the given slug is present (does not throw).
    static func exists(slug: String) -> Bool {
        (try? get(slug: slug)) != nil
    }
}
