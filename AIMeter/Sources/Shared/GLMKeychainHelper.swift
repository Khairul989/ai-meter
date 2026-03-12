import Foundation

enum GLMKeychainHelper {
    private static let helper = APIKeyKeychainHelper(serviceName: "glm-api-key")

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
