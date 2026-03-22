import Foundation

@MainActor
final class GLMService: HTTPPollingService {
    @Published var glmData: GLMUsageData = .empty

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

    override func resolveAPIKey() -> String? {
        GLMService.resolveAPIKey()
    }

    override func buildRequest(apiKey: String) -> URLRequest? {
        guard let url = URL(string: AppConstants.API.glmQuotaURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        return request
    }

    override func loadCachedData(staleThreshold: TimeInterval) {
        if let cached = SharedDefaults.loadGLM() {
            self.glmData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > staleThreshold
        }
    }

    override func parseAndApply(data: Data) throws {
        let decoded = try JSONDecoder().decode(GLMAPIResponse.self, from: data)
        guard decoded.success else { throw URLError(.badServerResponse) }

        let tokensPercent = decoded.data.limits
            .first(where: { $0.type == "TOKENS_LIMIT" })?.percentage ?? 0
        let tier = decoded.data.level

        self.glmData = GLMUsageData(
            tokensPercent: tokensPercent,
            tier: tier,
            fetchedAt: Date()
        )
        SharedDefaults.saveGLM(self.glmData)
        NotificationManager.shared.check(metrics: NotificationManager.metrics(from: self.glmData))
        NotificationManager.shared.checkSessionDepletion(provider: "GLM", usagePercent: Double(self.glmData.tokensPercent))
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
