import Foundation

enum AppConstants {
    /// App Group identifier for sharing data with widgets
    static let appGroupId = "group.com.khairul.aimeter"

    /// Bundle identifier
    static let bundleId = "com.khairul.aimeter"

    enum Paths {
        /// Config directory for history and cache files
        static let configDir: URL = {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/aimeter", isDirectory: true)
        }()

        static let quotaHistoryFile = configDir.appendingPathComponent("history.json")
        static let copilotHistoryFile = configDir.appendingPathComponent("copilot-history.json")
        static let glmHistoryFile = configDir.appendingPathComponent("glm-history.json")
        static let codexHistoryFile = configDir.appendingPathComponent("codex-history.json")
        static let kimiHistoryFile = configDir.appendingPathComponent("kimi-history.json")
        static let minimaxHistoryFile = configDir.appendingPathComponent("minimax-history.json")
        static let tokenCacheFile = configDir.appendingPathComponent("daily-token-cache.json")
    }

    enum API {
        static let claudeBaseURL = "https://claude.ai"
        static let glmQuotaURL = "https://api.z.ai/api/monitor/usage/quota/limit"
        static let kimiBalanceURL = "https://api.moonshot.cn/v1/users/me/balance"
        static let kimiUsagesURL = "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages"
        static let copilotUserURL = "https://api.github.com/copilot_internal/user"
        static let codexUsageURL = "https://chatgpt.com/backend-api/wham/usage"
        static let codexSessionURL = "https://chatgpt.com/api/auth/session"
        static let minimaxQuotaURL = "https://www.minimax.io/v1/api/openplatform/coding_plan/remains"
    }

    enum Defaults {
        static let refreshInterval: TimeInterval = 60
        static let requestTimeout: TimeInterval = 10
        static let staleMultiplier: Double = 2.0
    }
}
