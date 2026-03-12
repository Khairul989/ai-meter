import Foundation
import WidgetKit

@MainActor
final class UsageService: PollingServiceBase {
    @Published var usageData: UsageData = SharedDefaults.load() ?? .empty
    @Published var isStale: Bool = false
    @Published var error: APIError? = nil

    private var refreshInterval: TimeInterval = 60
    private weak var authManager: SessionAuthManager?
    private weak var historyService: QuotaHistoryService?

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

            // Merge extra usage and plan name
            if extra.credits != nil || extra.planName != nil {
                data = UsageData(
                    fiveHour: data.fiveHour,
                    sevenDay: data.sevenDay,
                    sevenDaySonnet: data.sevenDaySonnet,
                    extraCredits: extra.credits,
                    planName: extra.planName,
                    fetchedAt: data.fetchedAt
                )
            }

            self.usageData = data
            self.isStale = false
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            SharedDefaults.save(data)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.shared.check(metrics: NotificationManager.metrics(from: data))
            historyService?.recordDataPoint(
                session: Double(data.fiveHour.utilization) / 100.0,
                weekly: Double(data.sevenDay.utilization) / 100.0
            )
        } catch let apiError as APIError {
            self.isStale = true
            self.error = apiError
            if case .rateLimited(let retryAfter) = apiError {
                rescheduleTimer(interval: retryAfter + 5)
            }
        } catch {
            self.isStale = true
            self.error = .fetchFailed
        }
    }
}
