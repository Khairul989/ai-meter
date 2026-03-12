import Foundation
import WidgetKit

@MainActor
final class CopilotService: PollingServiceBase {
    @Published var copilotData: CopilotUsageData = SharedDefaults.loadCopilot() ?? .empty
    @Published var isStale: Bool = false
    @Published var error: CopilotError? = nil

    private var refreshInterval: TimeInterval = 60
    // Caller must retain the CopilotHistoryService instance; this service holds only a weak reference
    private weak var copilotHistoryService: CopilotHistoryService?

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
        guard let token = GitHubKeychainHelper.readAccessToken() else {
            self.error = .noToken
            return
        }

        do {
            let data = try await CopilotAPIClient.fetchUsage(token: token)
            self.copilotData = data
            self.isStale = false
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            SharedDefaults.saveCopilot(data)
            copilotHistoryService?.recordSnapshot(data)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.shared.check(metrics: NotificationManager.metrics(from: data))
        } catch let apiError as CopilotAPIError {
            self.isStale = true
            if case .rateLimited(let retryAfter) = apiError {
                self.error = .rateLimited(retryAfter: retryAfter)
                rescheduleTimer(interval: retryAfter + 5)
            } else {
                self.error = .fetchFailed
            }
        } catch {
            self.isStale = true
            self.error = .fetchFailed
        }
    }
}
