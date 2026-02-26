import Foundation

struct UsageData: Codable, Equatable {
    let fiveHour: RateLimit
    let sevenDay: RateLimit
    let sevenDaySonnet: RateLimit?
    let extraCredits: ExtraCredits?
    let fetchedAt: Date

    var highestUtilization: Int {
        var values = [fiveHour.utilization, sevenDay.utilization]
        if let sonnet = sevenDaySonnet { values.append(sonnet.utilization) }
        if let credits = extraCredits { values.append(credits.utilization) }
        return values.max() ?? 0
    }

    static let empty = UsageData(
        fiveHour: RateLimit(utilization: 0, resetsAt: nil),
        sevenDay: RateLimit(utilization: 0, resetsAt: nil),
        sevenDaySonnet: nil,
        extraCredits: nil,
        fetchedAt: .distantPast
    )
}

struct RateLimit: Codable, Equatable {
    let utilization: Int
    let resetsAt: Date?
}

struct ExtraCredits: Codable, Equatable {
    let utilization: Int
    let used: Double
    let limit: Double
}

extension JSONDecoder {
    static let appDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let appEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
