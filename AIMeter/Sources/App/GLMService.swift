import Foundation
import Combine

@MainActor
final class GLMService: ObservableObject {
    @Published var glmData: GLMUsageData = .empty
    @Published var isStale: Bool = false
    @Published var error: GLMError? = nil

    private var timer: Timer?
    private var refreshInterval: TimeInterval = 60

    enum GLMError: Equatable {
        case noKey
        case fetchFailed
    }

    /// Resolve API key: env var first, Keychain fallback
    static func resolveAPIKey() -> String? {
        if let envKey = ProcessInfo.processInfo.environment["GLM_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return GLMKeychainHelper.readAPIKey()
    }

    /// True if key comes from env var (read-only in Settings)
    static var keyIsFromEnvironment: Bool {
        if let envKey = ProcessInfo.processInfo.environment["GLM_API_KEY"], !envKey.isEmpty {
            return true
        }
        return false
    }

    func start(interval: TimeInterval = 60) {
        self.refreshInterval = interval
        if let cached = SharedDefaults.loadGLM() {
            self.glmData = cached
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
        guard let apiKey = GLMService.resolveAPIKey() else {
            self.error = .noKey
            return
        }

        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit") else { return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
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
