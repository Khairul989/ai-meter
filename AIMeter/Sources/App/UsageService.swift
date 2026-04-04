import Foundation
import WidgetKit

@MainActor
final class UsageService: PollingServiceBase {
    @Published var usageData: UsageData = SharedDefaults.load() ?? .empty
    @Published var isStale: Bool = false
    @Published var error: APIError? = nil
    @Published var retryDate: Date? = nil

    private var refreshInterval: TimeInterval = 60
    private weak var authManager: SessionAuthManager?
    private weak var historyService: QuotaHistoryService?
    private var isFetching = false
    private var consecutiveRateLimits = 0

    func start(interval: TimeInterval = 60, authManager: SessionAuthManager, historyService: QuotaHistoryService? = nil) {
        self.refreshInterval = interval
        self.authManager = authManager
        self.historyService = historyService
        if let cached = SharedDefaults.load() {
            self.usageData = cached
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

        guard let auth = authManager,
              let sessionKey = auth.sessionKey,
              let orgId = auth.organizationId else {
            self.error = .noCredentials
            return
        }

        do {
            // Fetch main usage + extra usage in parallel
            async let mainUsage = APIClient.fetchUsage(sessionKey: sessionKey, orgId: orgId)
            async let extraUsage = APIClient.fetchExtraUsage(sessionKey: sessionKey, orgId: orgId)

            var data = try await mainUsage
            let extra = await extraUsage

            // Merge plan name; use inline extra_usage if already parsed, otherwise fall back to overage endpoint credits
            let mergedCredits = data.extraCredits ?? extra.credits
            if mergedCredits != nil || extra.planName != nil {
                data = UsageData(
                    fiveHour: data.fiveHour,
                    sevenDay: data.sevenDay,
                    sevenDaySonnet: data.sevenDaySonnet,
                    extraCredits: mergedCredits,
                    planName: extra.planName,
                    fetchedAt: data.fetchedAt
                )
            }

            self.usageData = data
            self.isStale = false
            consecutiveRateLimits = 0  // Reset on success
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            self.retryDate = nil
            SharedDefaults.save(data)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.shared.check(metrics: NotificationManager.metrics(from: data))
            NotificationManager.shared.checkSessionDepletion(provider: "Claude", usagePercent: Double(data.fiveHour.utilization))
            historyService?.recordDataPoint(
                session: Double(data.fiveHour.utilization) / 100.0,
                weekly: Double(data.sevenDay.utilization) / 100.0
            )
        } catch let apiError as APIError {
            self.isStale = true
            self.error = apiError
            if case .rateLimited(let retryAfter) = apiError {
                consecutiveRateLimits += 1
                let backoff = retryAfter * pow(1.5, Double(min(consecutiveRateLimits - 1, 4)))
                let jitter = Double.random(in: 0...5)
                let delay = backoff + jitter
                self.retryDate = Date().addingTimeInterval(delay)
                rescheduleTimer(interval: delay)
            } else {
                self.retryDate = nil
            }
        } catch {
            self.isStale = true
            self.error = .fetchFailed
            self.retryDate = nil
        }
    }
}
