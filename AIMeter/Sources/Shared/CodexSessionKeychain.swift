import Foundation

enum CodexSessionKeychain {
    private static let prefix = "codex:"

    enum Account: String, CaseIterable {
        case accessToken, email, planType, idToken, refreshToken, expiresAt, chatGPTAccountId
        // OAuth PKCE credentials — stored separately from the web-session token.
        // oauthAccessTokenCache stores a JSON blob { "token": "…", "expiresAt": "ISO8601" }
        // so we avoid a second keychain entry just for the expiry date.
        case oauthRefreshToken, oauthAccessTokenCache
    }

    // MARK: - Un-namespaced (legacy, used for migration check)

    static func save(account: Account, value: String) {
        AppKeychain.set("\(prefix)\(account.rawValue)", value: value)
    }

    static func read(account: Account) -> String? {
        AppKeychain.get("\(prefix)\(account.rawValue)")
    }

    static func delete(account: Account) {
        AppKeychain.set("\(prefix)\(account.rawValue)", value: nil)
    }

    static func deleteAll() {
        for account in Account.allCases { delete(account: account) }
    }

    // MARK: - Account-scoped

    static func save(account: Account, accountId: String, value: String) {
        AppKeychain.set("\(prefix)\(account.rawValue):\(accountId)", value: value)
    }

    static func read(account: Account, accountId: String) -> String? {
        AppKeychain.get("\(prefix)\(account.rawValue):\(accountId)")
    }

    static func delete(account: Account, accountId: String) {
        AppKeychain.set("\(prefix)\(account.rawValue):\(accountId)", value: nil)
    }

    static func deleteAll(accountId: String) {
        for account in Account.allCases { delete(account: account, accountId: accountId) }
    }

    // MARK: - Account ID registry

    static func savedAccountIds() -> [String] {
        guard let json = AppKeychain.get("\(prefix)accountIds"),
              let data = json.data(using: .utf8),
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

    private static func saveAccountIds(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8)
        else { return }
        AppKeychain.set("\(prefix)accountIds", value: json)
    }
}
