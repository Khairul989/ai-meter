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
}
