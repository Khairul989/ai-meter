import Foundation
import Combine

@MainActor
final class KimiService: ObservableObject {
    @Published var kimiData: KimiUsageData = .empty
    @Published var isStale: Bool = false
    @Published var error: KimiError? = nil

    private var timer: Timer?
    private var refreshInterval: TimeInterval = 60

    enum KimiError: Equatable {
        case noKey
        case fetchFailed
    }

    /// Resolve API key: env var first, Keychain fallback
    static func resolveAPIKey() -> String? {
        if let envKey = ProcessInfo.processInfo.environment["KIMI_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return KimiKeychainHelper.readAPIKey()
    }

    /// True if key comes from env var (read-only in Settings)
    static var keyIsFromEnvironment: Bool {
        if let envKey = ProcessInfo.processInfo.environment["KIMI_API_KEY"], !envKey.isEmpty {
            return true
        }
        return false
    }

    func start(interval: TimeInterval = 60) {
        self.refreshInterval = interval
        if let cached = SharedDefaults.loadKimi() {
            self.kimiData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > interval * 2
        }
        Task { await fetch() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.fetch() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
            let (data, _) = try await URLSession.shared.data(for: request)
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

    enum CodingKeys: String, CodingKey {
        case code
        case data
    }
}

private struct KimiBalanceData: Decodable {
    let cashBalance: Double
    let voucherBalance: Double

    enum CodingKeys: String, CodingKey {
        case cashBalance = "cash_balance"
        case voucherBalance = "voucher_balance"
    }
}
