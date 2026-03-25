import Foundation
import WidgetKit

@MainActor
final class KimiService: ObservableObject {
    @Published var kimiData: KimiUsageData = .empty
    @Published var isStale: Bool = false
    @Published var isFetching: Bool = false
    @Published var error: KimiServiceError? = nil
    @Published var retryDate: Date? = nil

    private weak var authManager: KimiAuthManager?
    private weak var kimiHistoryService: KimiHistoryService?
    private var timer: Timer?
    private var consecutiveRateLimits = 0
    private(set) var refreshInterval: TimeInterval = 300

    enum KimiServiceError: Error, Equatable {
        case notAuthenticated
        case fetchFailed
        case rateLimited(retryAfter: TimeInterval)
        case invalidResponse
    }

    func start(interval: TimeInterval = 300, authManager: KimiAuthManager, historyService: KimiHistoryService? = nil) {
        stop()
        self.refreshInterval = interval
        self.authManager = authManager
        self.kimiHistoryService = historyService
        loadCachedData(staleThreshold: interval * 2)
        Task { await fetch() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                guard NetworkMonitor.shared.isConnected else { return }
                await self?.fetch()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func rescheduleTimer(interval: TimeInterval) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.fetch() }
        }
    }

    func fetch() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        guard let auth = authManager,
              let jwtToken = auth.jwtToken else {
            self.error = .notAuthenticated
            return
        }

        do {
            let data = try await fetchUsages(jwtToken: jwtToken)
            self.kimiData = data
            self.isStale = false
            consecutiveRateLimits = 0
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            self.retryDate = nil
            SharedDefaults.saveKimi(self.kimiData)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.shared.check(metrics: NotificationManager.metrics(from: self.kimiData))
            kimiHistoryService?.recordDataPoint(utilization: self.kimiData.utilizationPercent)
        } catch let serviceError as KimiServiceError {
            self.isStale = true
            self.error = serviceError
            if case .rateLimited(let retryAfter) = serviceError {
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

    private func fetchUsages(jwtToken: String) async throws -> KimiUsageData {
        let url = URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.timeoutInterval = 15

        let body: [String: Any] = ["scope": ["FEATURE_CODING"]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                    .flatMap { TimeInterval($0) } ?? 60
                throw KimiServiceError.rateLimited(retryAfter: retryAfter)
            }
            guard (200...299).contains(http.statusCode) else {
                throw KimiServiceError.fetchFailed
            }
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usages = json["usages"] as? [[String: Any]],
              let firstUsage = usages.first else {
            throw KimiServiceError.invalidResponse
        }

        return parseUsageResponse(firstUsage)
    }

    private func parseUsageResponse(_ json: [String: Any]) -> KimiUsageData {
        let scope = json["scope"] as? String ?? "FEATURE_CODING"

        let detail: KimiUsageDetail
        if let detailJson = json["detail"] as? [String: Any] {
            let limit = Int(detailJson["limit"] as? String ?? "0") ?? 0
            let used = Int(detailJson["used"] as? String ?? "0") ?? 0
            let remaining = Int(detailJson["remaining"] as? String ?? "0") ?? 0
            let resetTime = (detailJson["resetTime"] as? String)?.toISO8601Date()
            detail = KimiUsageDetail(limit: limit, used: used, remaining: remaining, resetTime: resetTime)
        } else {
            detail = KimiUsageDetail(limit: 0, used: 0, remaining: 0, resetTime: nil)
        }

        var limits: [KimiLimitWindow] = []
        if let limitsJson = json["limits"] as? [[String: Any]] {
            limits = limitsJson.compactMap { limitJson in
                guard let windowJson = limitJson["window"] as? [String: Any],
                      let duration = windowJson["duration"] as? Int,
                      let timeUnit = windowJson["timeUnit"] as? String,
                      let windowDetailJson = limitJson["detail"] as? [String: Any] else {
                    return nil
                }
                let window = KimiWindowConfig(duration: duration, timeUnit: timeUnit)
                let windowLimit = Int(windowDetailJson["limit"] as? String ?? "0") ?? 0
                let windowUsed = Int(windowDetailJson["used"] as? String ?? "0") ?? 0
                let windowRemaining = Int(windowDetailJson["remaining"] as? String ?? "0") ?? 0
                let windowResetTime = (windowDetailJson["resetTime"] as? String)?.toISO8601Date()
                let windowDetail = KimiUsageDetail(limit: windowLimit, used: windowUsed, remaining: windowRemaining, resetTime: windowResetTime)
                return KimiLimitWindow(window: window, detail: windowDetail)
            }
        }

        return KimiUsageData(scope: scope, detail: detail, limits: limits, fetchedAt: Date())
    }

    private func loadCachedData(staleThreshold: TimeInterval) {
        if let cached = SharedDefaults.loadKimi() {
            self.kimiData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > staleThreshold
        }
    }
}
