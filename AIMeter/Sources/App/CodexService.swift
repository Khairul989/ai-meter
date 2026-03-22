import Foundation

@MainActor
final class CodexService: PollingServiceBase {
    @Published var codexData: CodexUsageData = SharedDefaults.loadCodex() ?? .empty
    @Published var isStale: Bool = false
    @Published var error: CodexError? = nil
    @Published var retryDate: Date? = nil

    private var refreshInterval: TimeInterval = 60
    private weak var authManager: CodexAuthManager?
    private var isFetching = false
    private var consecutiveRateLimits = 0

    enum CodexError: Equatable {
        case noToken
        case tokenExpired
        case fetchFailed
        case rateLimited(retryAfter: TimeInterval)
    }

    func start(interval: TimeInterval = 60, authManager: CodexAuthManager? = nil) {
        self.refreshInterval = interval
        self.authManager = authManager
        if let cached = SharedDefaults.loadCodex() {
            self.codexData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > refreshInterval * 2
        }
        super.start(interval: interval)
    }

    override func tick() async { await fetch() }

    func fetch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        guard let token = authManager?.accessToken else {
            self.error = .noToken
            return
        }

        do {
            let data = try await CodexAPIClient.fetchUsage(token: token)
            self.codexData = data
            self.isStale = false
            consecutiveRateLimits = 0
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            self.retryDate = nil
            SharedDefaults.saveCodex(data)
            NotificationManager.shared.checkSessionDepletion(provider: "Codex", usagePercent: Double(data.primaryPercent))
        } catch let apiError as CodexAPIError {
            self.isStale = true
            if case .rateLimited(let retryAfter) = apiError {
                consecutiveRateLimits += 1
                let backoff = retryAfter * pow(1.5, Double(min(consecutiveRateLimits - 1, 4)))
                let jitter = Double.random(in: 0...5)
                let delay = backoff + jitter
                self.error = .rateLimited(retryAfter: delay)
                self.retryDate = Date().addingTimeInterval(delay)
                rescheduleTimer(interval: delay)
            } else if case .unauthorized = apiError {
                self.error = .tokenExpired
                self.retryDate = nil
            } else {
                self.error = .fetchFailed
                self.retryDate = nil
            }
        } catch {
            self.isStale = true
            self.error = .fetchFailed
            self.retryDate = nil
        }
    }
}
