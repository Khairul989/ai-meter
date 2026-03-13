import Foundation

@MainActor
final class GLMService: PollingServiceBase {
    @Published var glmData: GLMUsageData = .empty
    @Published var isStale: Bool = false
    @Published var error: GLMError? = nil

    private var refreshInterval: TimeInterval = 60

    enum GLMError: Equatable {
        case noKey
        case fetchFailed
        case rateLimited(retryAfter: TimeInterval)
    }

    /// Resolve API key: Keychain first, env var fallback
    static func resolveAPIKey() -> String? {
        if let keychainKey = APIKeyKeychainHelper.glm.readAPIKey() {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["GLM_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return nil
    }

    /// True if key comes from env var (read-only in Settings)
    static var keyIsFromEnvironment: Bool {
        if APIKeyKeychainHelper.glm.readAPIKey() != nil { return false }
        if let envKey = ProcessInfo.processInfo.environment["GLM_API_KEY"], !envKey.isEmpty {
            return true
        }
        return false
    }

    override func start(interval: TimeInterval = 60) {
        self.refreshInterval = interval
        if let cached = SharedDefaults.loadGLM() {
            self.glmData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > interval * 2
        }
        super.start(interval: interval)
    }

    override func tick() async {
        await fetch()
    }

    func fetch() async {
        guard let apiKey = GLMService.resolveAPIKey() else {
            self.error = .noKey
            return
        }

        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit") else { return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
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

            let decoded = try JSONDecoder().decode(GLMAPIResponse.self, from: data)
            guard decoded.success else {
                self.isStale = true
                self.error = .fetchFailed
                return
            }

            let tokensPercent = decoded.data.limits
                .first(where: { $0.type == "TOKENS_LIMIT" })?.percentage ?? 0
            let tier = decoded.data.level

            self.glmData = GLMUsageData(
                tokensPercent: tokensPercent,
                tier: tier,
                fetchedAt: Date()
            )
            self.isStale = false
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            SharedDefaults.saveGLM(self.glmData)
            NotificationManager.shared.check(metrics: NotificationManager.metrics(from: self.glmData))
        } catch {
            self.isStale = true
            self.error = .fetchFailed
        }
    }
}

// MARK: - API response models (private, only used for decoding)

private struct GLMAPIResponse: Decodable {
    let success: Bool
    let data: GLMAPIData
}

private struct GLMAPIData: Decodable {
    let limits: [GLMLimit]
    let level: String
}

private struct GLMLimit: Decodable {
    let type: String
    let percentage: Int?
}
