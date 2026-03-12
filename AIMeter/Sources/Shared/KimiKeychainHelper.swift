import Foundation

enum KimiKeychainHelper {
    private static let helper = APIKeyKeychainHelper(serviceName: "kimi-api-key")

    static func readAPIKey() -> String? {
        helper.readAPIKey()
    }

    static func saveAPIKey(_ key: String) {
        helper.saveAPIKey(key)
    }

    static func deleteAPIKey() {
        helper.deleteAPIKey()
    }
}
