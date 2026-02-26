import Foundation

enum SharedDefaults {
    static let suiteName = "group.com.khairul.aimeter"

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func save(_ data: UsageData) {
        guard let encoded = try? JSONEncoder.appEncoder.encode(data) else { return }
        suite?.set(encoded, forKey: "usageData")
    }

    static func load() -> UsageData? {
        guard let data = suite?.data(forKey: "usageData"),
              let decoded = try? JSONDecoder.appDecoder.decode(UsageData.self, from: data)
        else { return nil }
        return decoded
    }
}
