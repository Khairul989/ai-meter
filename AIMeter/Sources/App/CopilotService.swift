import Foundation
import Combine
import WidgetKit

@MainActor
final class CopilotService: ObservableObject {
    @Published var copilotData: CopilotUsageData = SharedDefaults.loadCopilot() ?? .empty
    @Published var isStale: Bool = false
    @Published var error: CopilotError? = nil

    private var timer: Timer?
    private var refreshInterval: TimeInterval = 60

    enum CopilotError: Equatable {
        case noToken
        case fetchFailed
    }

    func start(interval: TimeInterval = 60) {
        self.refreshInterval = interval
        // Load cached data immediately
        if let cached = SharedDefaults.loadCopilot() {
            self.copilotData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > refreshInterval * 2
        }
        // Fetch immediately then on timer
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
        guard let token = GitHubKeychainHelper.readAccessToken() else {
            self.error = .noToken
            return
        }

        do {
            let data = try await CopilotAPIClient.fetchUsage(token: token)
            self.copilotData = data
            self.isStale = false
            self.error = nil
            SharedDefaults.saveCopilot(data)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.shared.check(metrics: NotificationManager.metrics(from: data))
        } catch {
            self.isStale = true
            self.error = .fetchFailed
        }
    }
}
