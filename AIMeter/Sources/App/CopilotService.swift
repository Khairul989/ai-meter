import Foundation
import WidgetKit

@MainActor
final class CopilotService: PollingServiceBase {
    @Published var copilotData: CopilotUsageData = SharedDefaults.loadCopilot() ?? .empty
    @Published var isStale: Bool = false
    @Published var error: CopilotError? = nil
    @Published var retryDate: Date? = nil

    private var refreshInterval: TimeInterval = 60
    // Caller must retain the CopilotHistoryService instance; this service holds only a weak reference
    private weak var copilotHistoryService: CopilotHistoryService?
    private var isFetching = false
    private var consecutiveRateLimits = 0

    enum CopilotError: Equatable {
        case noToken
        case fetchFailed
        case rateLimited(retryAfter: TimeInterval)
    }

    func start(interval: TimeInterval = 60, historyService: CopilotHistoryService? = nil) {
        self.refreshInterval = interval
        self.copilotHistoryService = historyService
        // Load cached data immediately
        if let cached = SharedDefaults.loadCopilot() {
            self.copilotData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > refreshInterval * 2
        }
        super.start(interval: interval)
    }

    override func tick() async {
        await fetch()
    }

    func fetch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        guard let token = GitHubKeychainHelper.readAccessToken() else {
            self.error = .noToken
            return
        }

        do {
            let data = try await CopilotAPIClient.fetchUsage(token: token)
            self.copilotData = data
            self.isStale = false
            consecutiveRateLimits = 0  // Reset on success
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            self.retryDate = nil
            SharedDefaults.saveCopilot(data)
            copilotHistoryService?.recordSnapshot(data)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.shared.check(metrics: NotificationManager.metrics(from: data))
            if !data.premiumInteractions.unlimited {
                NotificationManager.shared.checkSessionDepletion(provider: "Copilot", usagePercent: Double(data.premiumInteractions.utilization))
            }
        } catch let apiError as CopilotAPIError {
            self.isStale = true
            if case .rateLimited(let retryAfter) = apiError {
                consecutiveRateLimits += 1
                let backoff = retryAfter * pow(1.5, Double(min(consecutiveRateLimits - 1, 4)))
                let jitter = Double.random(in: 0...5)
                let delay = backoff + jitter
                self.error = .rateLimited(retryAfter: delay)
                self.retryDate = Date().addingTimeInterval(delay)
                rescheduleTimer(interval: delay)
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
