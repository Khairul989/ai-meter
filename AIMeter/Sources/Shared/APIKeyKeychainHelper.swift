import Foundation

struct APIKeyKeychainHelper {
    let serviceName: String

    static let glm = APIKeyKeychainHelper(serviceName: "glm-api-key")
    static let kimi = APIKeyKeychainHelper(serviceName: "kimi-api-key")
    static let minimax = APIKeyKeychainHelper(serviceName: "minimax-api-key")

    func readAPIKey() -> String? {
        AppKeychain.get("apikey:\(serviceName)")
    }

    func saveAPIKey(_ key: String) {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        AppKeychain.set("apikey:\(serviceName)", value: key)
    }

    func deleteAPIKey() {
        AppKeychain.set("apikey:\(serviceName)", value: nil)
    }

    func readAPIKey(accountId: String) -> String? {
        AppKeychain.get("apikey:\(serviceName):\(accountId)")
    }

    func saveAPIKey(_ key: String, accountId: String) {
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        AppKeychain.set("apikey:\(serviceName):\(accountId)", value: key)
    }

    func deleteAPIKey(accountId: String) {
        AppKeychain.set("apikey:\(serviceName):\(accountId)", value: nil)
    }

    func deleteAll(accountId: String) {
        deleteAPIKey(accountId: accountId)
    }

    func savedAccountIds() -> [String] {
        guard let json = AppKeychain.get("apikey:\(serviceName):accountIds"),
              let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return ids
    }

    func addAccountId(_ id: String) {
        var ids = savedAccountIds()
        guard !ids.contains(id) else { return }
        ids.append(id)
        saveAccountIds(ids)
    }

    func removeAccountId(_ id: String) {
        var ids = savedAccountIds()
        ids.removeAll { $0 == id }
        saveAccountIds(ids)
    }

    private func saveAccountIds(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8)
        else { return }
        AppKeychain.set("apikey:\(serviceName):accountIds", value: json)
    }
}
