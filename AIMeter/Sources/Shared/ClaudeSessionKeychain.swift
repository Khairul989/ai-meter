import Foundation

enum ClaudeSessionKeychain {
    private static let prefix = "claude:"

    enum Account: String, CaseIterable {
        case sessionKey, organizationId, orgName, planName, capabilities
    }

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
}
