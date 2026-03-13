import Foundation

@MainActor
final class KimiService: PollingServiceBase {
    @Published var kimiData: KimiUsageData = .empty
    @Published var isStale: Bool = false
    @Published var error: KimiError? = nil

    private var refreshInterval: TimeInterval = 60

    enum KimiError: Equatable {
        case noKey
        case fetchFailed
        case rateLimited(retryAfter: TimeInterval)
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
        if let envKey = ProcessInfo.processInfo.environment["KIMI_API_KEY"], !envKey.isEmpty {
            return true
        }
        return false
    }

    override func start(interval: TimeInterval = 60) {
        self.refreshInterval = interval
        if let cached = SharedDefaults.loadKimi() {
            self.kimiData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > interval * 2
        }
        super.start(interval: interval)
    }

    override func tick() async {
        await fetch()
    }

    func fetch() async {
        guard let apiKey = KimiService.resolveAPIKey() else {
            self.error = .noKey
            return
        }

        guard let url = URL(string: "https://api.moonshot.cn/v1/users/me/balance") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // HTTP status check
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 {
                    let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                        .flatMap { TimeInterval($0) } ?? 60
                    self.error = .rateLimited(retryAfter: retryAfter)
                    self.isStale = true
                    rescheduleTimer(interval: retryAfter + 5)
                    return
                }
                guard (200...299).contains(http.statusCode) else {
                    self.isStale = true
                    self.error = .fetchFailed
                    return
                }
            }

            let decoded = try JSONDecoder().decode(KimiBalanceResponse.self, from: data)
            guard decoded.code == 0 else {
                self.isStale = true
                self.error = .fetchFailed
                return
            }

            let cashBalance = decoded.data.cashBalance
            let voucherBalance = decoded.data.voucherBalance
            let totalBalance = cashBalance + voucherBalance

            self.kimiData = KimiUsageData(
                cashBalance: cashBalance,
                voucherBalance: voucherBalance,
                totalBalance: totalBalance,
                fetchedAt: Date()
            )
            self.isStale = false
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            SharedDefaults.saveKimi(self.kimiData)
            NotificationManager.shared.check(metrics: NotificationManager.metrics(from: self.kimiData))
        } catch {
            self.isStale = true
            self.error = .fetchFailed
        }
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
