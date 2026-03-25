import Foundation

@MainActor
final class MinimaxService: HTTPPollingService {
    @Published var minimaxData: MinimaxUsageData = .empty
    // Caller must retain the MinimaxHistoryService instance; this service holds only a weak reference
    private weak var minimaxHistoryService: MinimaxHistoryService?

    func start(interval: TimeInterval = 60, historyService: MinimaxHistoryService? = nil) {
        self.minimaxHistoryService = historyService
        super.start(interval: interval)
    }

    /// Resolve API key: Keychain first, env var fallback
    static func resolveAPIKey() -> String? {
        if let keychainKey = APIKeyKeychainHelper.minimax.readAPIKey() {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return nil
    }

    /// True if key comes from env var (read-only in Settings)
    static var keyIsFromEnvironment: Bool {
        if APIKeyKeychainHelper.minimax.readAPIKey() != nil { return false }
        if let envKey = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"], !envKey.isEmpty {
            return true
        }
        return false
    }

    override func resolveAPIKey() -> String? {
        MinimaxService.resolveAPIKey()
    }

    override func buildRequest(apiKey: String) -> URLRequest? {
        guard let url = URL(string: AppConstants.API.minimaxQuotaURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        return request
    }

    override func loadCachedData(staleThreshold: TimeInterval) {
        if let cached = SharedDefaults.loadMinimax() {
            self.minimaxData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > staleThreshold
        }
    }

    override func parseAndApply(data: Data) throws {
        let decoded = try JSONDecoder().decode(MinimaxAPIResponse.self, from: data)
        guard decoded.base_resp.status_code == 0 else { throw URLError(.badServerResponse) }

        let models: [MinimaxModelQuota] = decoded.model_remains
            .filter { $0.current_interval_total_count > 0 || $0.current_weekly_total_count > 0 }
            .map { remain in
                // API fields represent REMAINING counts, so used = total - remaining
                let intervalUsed = remain.current_interval_total_count - remain.current_interval_usage_count
                let weeklyUsed = remain.current_weekly_total_count - remain.current_weekly_usage_count
                let intervalPercent = percentOf(used: intervalUsed, total: remain.current_interval_total_count)
                let weeklyPercent = percentOf(used: weeklyUsed, total: remain.current_weekly_total_count)
                let resetsAt = remain.end_time > 0 ? Date(timeIntervalSince1970: Double(remain.end_time) / 1000.0) : nil
                let weeklyResetsAt = remain.weekly_end_time > 0 ? Date(timeIntervalSince1970: Double(remain.weekly_end_time) / 1000.0) : nil
                return MinimaxModelQuota(
                    modelName: remain.model_name,
                    intervalPercent: intervalPercent,
                    weeklyPercent: weeklyPercent,
                    intervalUsed: intervalUsed,
                    intervalTotal: remain.current_interval_total_count,
                    weeklyUsed: weeklyUsed,
                    weeklyTotal: remain.current_weekly_total_count,
                    resetsAt: resetsAt,
                    weeklyResetsAt: weeklyResetsAt
                )
            }

        self.minimaxData = MinimaxUsageData(models: models, fetchedAt: Date())
        SharedDefaults.saveMinimax(self.minimaxData)
        minimaxHistoryService?.recordDataPoint(intervalPercent: self.minimaxData.highestIntervalPercent)
        NotificationManager.shared.checkSessionDepletion(provider: "MiniMax", usagePercent: Double(self.minimaxData.highestIntervalPercent))
    }

    private func percentOf(used: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(used) / Double(total)) * 100)
    }
}

// MARK: - API response models (private, only used for decoding)

private struct MinimaxAPIResponse: Decodable {
    let model_remains: [MinimaxModelRemain]
    let base_resp: MinimaxBaseResp
}

private struct MinimaxBaseResp: Decodable {
    let status_code: Int
    let status_msg: String
}

private struct MinimaxModelRemain: Decodable {
    let model_name: String
    let current_interval_total_count: Int
    let current_interval_usage_count: Int
    let start_time: Int64
    let end_time: Int64
    let remains_time: Int64
    let current_weekly_total_count: Int
    let current_weekly_usage_count: Int
    let weekly_start_time: Int64
    let weekly_end_time: Int64
    let weekly_remains_time: Int64
}
