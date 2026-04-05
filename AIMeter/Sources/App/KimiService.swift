import Foundation

@MainActor
final class KimiService: HTTPPollingService {
    @Published var kimiData: KimiUsageData = .empty
    // Caller must retain the KimiHistoryService instance; this service holds only a weak reference
    private weak var kimiHistoryService: KimiHistoryService?
    private weak var authManager: APIKeyAuthManager?

    func start(interval: TimeInterval = 60, authManager: APIKeyAuthManager, historyService: KimiHistoryService? = nil) {
        self.authManager = authManager
        self.kimiHistoryService = historyService
        super.start(interval: interval)
    }

    /// Resolve API key: Keychain first, env var fallback
    static func resolveAPIKey() -> String? {
        if let keychainKey = APIKeyKeychainHelper.kimi.readAPIKey() {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["KIMI_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return nil
    }

    /// True if key comes from env var (read-only in Settings)
    static var keyIsFromEnvironment: Bool {
        if APIKeyKeychainHelper.kimi.readAPIKey() != nil { return false }
        for accountId in APIKeyKeychainHelper.kimi.savedAccountIds() {
            if APIKeyKeychainHelper.kimi.readAPIKey(accountId: accountId) != nil { return false }
        }
        if let envKey = ProcessInfo.processInfo.environment["KIMI_API_KEY"], !envKey.isEmpty {
            return true
        }
        return false
    }

    override func resolveAPIKey() -> String? {
        authManager?.activeAPIKey ?? KimiService.resolveAPIKey()
    }

    override func buildRequest(apiKey: String) -> URLRequest? {
        guard let url = URL(string: AppConstants.API.kimiBalanceURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        return request
    }

    override func loadCachedData(staleThreshold: TimeInterval) {
        if let cached = SharedDefaults.loadKimi() {
            self.kimiData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > staleThreshold
        }
    }

    override func parseAndApply(data: Data) throws {
        let decoded = try JSONDecoder().decode(KimiBalanceResponse.self, from: data)
        guard decoded.code == 0 else { throw URLError(.badServerResponse) }

        let cashBalance = decoded.data.cashBalance
        let voucherBalance = decoded.data.voucherBalance
        let totalBalance = cashBalance + voucherBalance

        self.kimiData = KimiUsageData(
            cashBalance: cashBalance,
            voucherBalance: voucherBalance,
            totalBalance: totalBalance,
            fetchedAt: Date()
        )
        SharedDefaults.saveKimi(self.kimiData)
        kimiHistoryService?.recordDataPoint(totalBalance: self.kimiData.totalBalance)
        NotificationManager.shared.check(metrics: NotificationManager.metrics(from: self.kimiData))
    }
}

// MARK: - API response models (private, only used for decoding)

private struct KimiBalanceResponse: Decodable {
    let code: Int
    let data: KimiBalanceData
}

private struct KimiBalanceData: Decodable {
    let cashBalance: Double
    let voucherBalance: Double

    enum CodingKeys: String, CodingKey {
        case cashBalance = "cash_balance"
        case voucherBalance = "voucher_balance"
    }
}
