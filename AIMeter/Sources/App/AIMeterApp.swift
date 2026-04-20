import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let category = response.notification.request.content.categoryIdentifier
        NotificationManager.shared.handleNotificationAction(response.actionIdentifier, for: category)
        completionHandler()
    }
}

enum MenuBarDisplayMode: String, CaseIterable {
    case classic = "classic"
    case percent = "percent"
    case pace = "pace"
    case both = "both"

    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .percent: "Percent"
        case .pace: "Pace"
        case .both: "Both"
        }
    }
}

enum MenuBarProvider: String, CaseIterable {
    case claude = "claude"
    case copilot = "copilot"
    case glm = "glm"
    case kimi = "kimi"
    case codex = "codex"
    case minimax = "minimax"

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .copilot: "Copilot"
        case .glm: "GLM"
        case .kimi: "Kimi"
        case .codex: "Codex"
        case .minimax: "MiniMax"
        }
    }

    var menuBarIconName: String {
        switch self {
        case .claude: return "claude-small"
        case .copilot: return "copilot-small"
        case .glm: return "glm-small"
        case .kimi: return "kimi-small"
        case .codex: return "codex-small"
        case .minimax: return "minimax-small"
        }
    }
}

@main
struct AIMeterApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var copilotService = CopilotService()
    @StateObject private var copilotHistoryService = CopilotHistoryService()
    @StateObject private var glmHistoryService = GLMHistoryService()
    @StateObject private var kimiHistoryService = KimiHistoryService()
    @StateObject private var codexHistoryService = CodexHistoryService()
    @StateObject private var glmService = GLMService()
    @StateObject private var kimiService = KimiService()
    @StateObject private var glmAuthManager: APIKeyAuthManager
    @StateObject private var kimiAuthManager: APIKeyAuthManager
    @StateObject private var codexService = CodexService()
    @StateObject private var codexAuthManager: CodexAuthManager
    @StateObject private var claudeProxyRoutingManager: ClaudeProxyRoutingManager
    @StateObject private var codexStatsService = CodexSessionStatsService()
    @StateObject private var claudeSessionStatsService = ClaudeSessionStatsService()
    @StateObject private var minimaxService = MinimaxService()
    @StateObject private var minimaxAuthManager: APIKeyAuthManager
    @StateObject private var apiKeyAuthManagers: APIKeyAuthManagers
    @StateObject private var minimaxHistoryService = MinimaxHistoryService()
    @StateObject private var updaterManager = UpdaterManager()
    @StateObject private var authManager = SessionAuthManager()
    @StateObject private var historyService = QuotaHistoryService()
    @StateObject private var statsService = ClaudeCodeStatsService()
    @StateObject private var providerStatusService = ProviderStatusService()
    @AppStorage("checkProviderStatus") private var checkProviderStatus: Bool = true
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("menuBarProvider") private var menuBarProvider: String = MenuBarProvider.claude.rawValue
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayMode: String = MenuBarDisplayMode.classic.rawValue
    @AppStorage("perProviderRefresh") private var perProviderRefresh: Bool = false
    @AppStorage("refreshClaude") private var refreshClaude: Double = 60
    @AppStorage("refreshCopilot") private var refreshCopilot: Double = 60
    @AppStorage("refreshGLM") private var refreshGLM: Double = 120
    @AppStorage("refreshKimi") private var refreshKimi: Double = 300
    @AppStorage("refreshCodex") private var refreshCodex: Double = 300
    @AppStorage("refreshMinimax") private var refreshMinimax: Double = 120
    @State private var isRefreshing = false
    @State private var recapService: RecapService?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("keychainUpgradedV2") private var keychainUpgraded = false

    init() {
        let codexAuthManager = CodexAuthManager()
        let glmAuthManager = APIKeyAuthManager(keychain: .glm)
        let kimiAuthManager = APIKeyAuthManager(keychain: .kimi)
        let minimaxAuthManager = APIKeyAuthManager(keychain: .minimax)
        _codexAuthManager = StateObject(wrappedValue: codexAuthManager)
        _claudeProxyRoutingManager = StateObject(wrappedValue: ClaudeProxyRoutingManager(codexAuthManager: codexAuthManager))
        _glmAuthManager = StateObject(wrappedValue: glmAuthManager)
        _kimiAuthManager = StateObject(wrappedValue: kimiAuthManager)
        _minimaxAuthManager = StateObject(wrappedValue: minimaxAuthManager)
        _apiKeyAuthManagers = StateObject(
            wrappedValue: APIKeyAuthManagers(
                glm: glmAuthManager,
                kimi: kimiAuthManager,
                minimax: minimaxAuthManager
            )
        )
    }

    private func showKeychainUpgradeAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Credential Storage Upgraded"
            alert.informativeText = "AIMeter has upgraded its secure storage to eliminate repeated keychain permission dialogs.\n\nPlease re-enter your API keys and sign in again to your accounts. This is a one-time change — you won't be asked again."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func interval(for provider: MenuBarProvider) -> Double {
        guard perProviderRefresh else { return refreshInterval }
        switch provider {
        case .claude: return refreshClaude
        case .copilot: return refreshCopilot
        case .glm: return refreshGLM
        case .kimi: return refreshKimi
        case .codex: return refreshCodex
        case .minimax: return refreshMinimax
        }
    }

    private func refreshAllProviders() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await service.fetch() }
                group.addTask { await copilotService.fetch() }
                group.addTask { await glmService.fetch() }
                group.addTask { await kimiService.fetch() }
                group.addTask { await codexService.fetch() }
                group.addTask { await minimaxService.fetch() }
            }
            statsService.load()
            try? await Task.sleep(for: .milliseconds(600))
            isRefreshing = false
        }
    }

    private func restartAllProviders() {
        service.stop()
        service.start(interval: interval(for: .claude), authManager: authManager, historyService: historyService)
        copilotService.stop()
        copilotService.start(interval: interval(for: .copilot), historyService: copilotHistoryService)
        glmService.stop()
        glmService.start(interval: interval(for: .glm), authManager: glmAuthManager, historyService: glmHistoryService)
        kimiService.stop()
        kimiService.start(interval: interval(for: .kimi), authManager: kimiAuthManager, historyService: kimiHistoryService)
        codexService.stop()
        codexService.start(interval: interval(for: .codex), authManager: codexAuthManager, historyService: codexHistoryService)
        minimaxService.stop()
        minimaxService.start(interval: interval(for: .minimax), authManager: minimaxAuthManager, historyService: minimaxHistoryService)
        statsService.stop()
        statsService.start(interval: interval(for: .claude))
    }

    private func handleProviderStatusChange(enabled: Bool) {
        if enabled {
            providerStatusService.start()
        } else {
            providerStatusService.stop()
        }
    }

    private func handleClaudeAuthenticationChange(isAuthenticated: Bool) {
        if isAuthenticated {
            Task { await service.fetch() }
        }
    }

    private func handleCodexAuthenticationChange(isAuthenticated: Bool) {
        if isAuthenticated {
            Task { await codexService.fetch() }
        }
    }

    private func handlePopoverAppear() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationManager.shared.requestPermission()
        if !keychainUpgraded {
            keychainUpgraded = true
            if hasCompletedOnboarding {
                showKeychainUpgradeAlert()
            }
        }

        service.start(interval: interval(for: .claude), authManager: authManager, historyService: historyService)
        copilotService.start(interval: interval(for: .copilot), historyService: copilotHistoryService)
        glmService.start(interval: interval(for: .glm), authManager: glmAuthManager, historyService: glmHistoryService)
        kimiService.start(interval: interval(for: .kimi), authManager: kimiAuthManager, historyService: kimiHistoryService)
        codexService.start(interval: interval(for: .codex), authManager: codexAuthManager, historyService: codexHistoryService)
        minimaxService.start(interval: interval(for: .minimax), authManager: minimaxAuthManager, historyService: minimaxHistoryService)
        statsService.start(interval: interval(for: .claude))
        if checkProviderStatus {
            providerStatusService.start()
        }

        if recapService == nil {
            recapService = RecapService(quotaHistoryService: historyService, copilotHistoryService: copilotHistoryService)
        }
        recapService?.checkAndGenerateRecap(notificationManager: NotificationManager.shared)
        GlobalHotKeyManager.shared.start()
    }

    private func handleOpenLatestRecap() {
        guard let recapService else { return }
        let recaps = recapService.loadSavedRecaps()
        if let latest = recaps.last {
            RecapWindowController.show(recap: latest)
        }
    }

    private func popoverContent() -> some View {
        let baseView = AnyView(
            PopoverView(onRefresh: refreshAllProviders)
                .environmentObject(service)
                .environmentObject(copilotService)
                .environmentObject(copilotHistoryService)
                .environmentObject(glmHistoryService)
                .environmentObject(kimiHistoryService)
                .environmentObject(codexHistoryService)
                .environmentObject(glmService)
                .environmentObject(kimiService)
                .environmentObject(codexService)
                .environmentObject(codexAuthManager)
                .environmentObject(claudeProxyRoutingManager)
                .environmentObject(codexStatsService)
                .environmentObject(apiKeyAuthManagers)
                .environmentObject(minimaxService)
                .environmentObject(minimaxHistoryService)
                .environmentObject(updaterManager)
                .environmentObject(authManager)
                .environmentObject(statsService)
                .environmentObject(claudeSessionStatsService)
                .environmentObject(historyService)
                .environmentObject(providerStatusService)
        )

        let appearedView = AnyView(baseView.onAppear(perform: handlePopoverAppear))
        let latestRecapView = AnyView(appearedView.onReceive(NotificationCenter.default.publisher(for: .openLatestRecap)) { _ in
            handleOpenLatestRecap()
        })
        let forceRefreshView = AnyView(latestRecapView.onReceive(NotificationCenter.default.publisher(for: .forceRefreshAll)) { _ in
            refreshAllProviders()
        })
        let refreshIntervalView = AnyView(forceRefreshView.onChange(of: refreshInterval) { _, _ in
            restartAllProviders()
        })
        let perProviderRefreshView = AnyView(refreshIntervalView.onChange(of: perProviderRefresh) { _, _ in
            restartAllProviders()
        })
        let refreshClaudeView = AnyView(perProviderRefreshView.onChange(of: refreshClaude) { _, _ in
            restartAllProviders()
        })
        let refreshCopilotView = AnyView(refreshClaudeView.onChange(of: refreshCopilot) { _, _ in
            restartAllProviders()
        })
        let refreshGLMView = AnyView(refreshCopilotView.onChange(of: refreshGLM) { _, _ in
            restartAllProviders()
        })
        let refreshKimiView = AnyView(refreshGLMView.onChange(of: refreshKimi) { _, _ in
            restartAllProviders()
        })
        let refreshCodexView = AnyView(refreshKimiView.onChange(of: refreshCodex) { _, _ in
            restartAllProviders()
        })
        let refreshMinimaxView = AnyView(refreshCodexView.onChange(of: refreshMinimax) { _, _ in
            restartAllProviders()
        })
        let providerStatusView = AnyView(refreshMinimaxView.onChange(of: checkProviderStatus) { _, enabled in
            handleProviderStatusChange(enabled: enabled)
        })
        let claudeAuthView = AnyView(providerStatusView.onChange(of: authManager.isAuthenticated) { _, isAuth in
            handleClaudeAuthenticationChange(isAuthenticated: isAuth)
        })
        let claudeAccountView = AnyView(claudeAuthView.onChange(of: authManager.activeAccountId) { _, _ in
            Task { await service.fetch() }
        })
        let glmAccountView = AnyView(claudeAccountView.onChange(of: glmAuthManager.activeAccountId) { _, _ in
            Task { await glmService.fetch() }
        })
        let kimiAccountView = AnyView(glmAccountView.onChange(of: kimiAuthManager.activeAccountId) { _, _ in
            Task { await kimiService.fetch() }
        })
        let codexAuthView = AnyView(kimiAccountView.onChange(of: codexAuthManager.isAuthenticated) { _, isAuth in
            handleCodexAuthenticationChange(isAuthenticated: isAuth)
        })
        let codexAccountView = AnyView(codexAuthView.onChange(of: codexAuthManager.activeAccountId) { _, _ in
            Task { await codexService.fetch() }
        })
        return AnyView(codexAccountView.onChange(of: minimaxAuthManager.activeAccountId) { _, _ in
            Task { await minimaxService.fetch() }
        })
    }

    var body: some Scene {
        MenuBarExtra {
            if !hasCompletedOnboarding {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            } else {
                popoverContent()
            }
        } label: {
            let selected = MenuBarProvider(rawValue: menuBarProvider) ?? .claude
            let mode = MenuBarDisplayMode(rawValue: menuBarDisplayMode) ?? .classic
            let labelInfo = MenuBarLabel.extractLabelInfo(
                provider: selected, displayMode: mode,
                usageData: service.usageData, copilotData: copilotService.copilotData,
                glmData: glmService.glmData, kimiData: kimiService.kimiData,
                codexData: codexService.codexData, minimaxData: minimaxService.minimaxData
            )
            MenuBarLabel(
                labelText: labelInfo.text,
                utilization: labelInfo.utilization,
                provider: selected,
                isRefreshing: isRefreshing
            )
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
@Observable
final class MenuBarLabelState {
    private(set) var cachedImage: NSImage?
    private(set) var loadingImage: NSImage?
    private var lastText: String = ""
    private var lastUtilization: Int = -1
    private var lastProvider: MenuBarProvider = .claude

    func updateIfNeeded(labelText: String, utilization: Int, provider: MenuBarProvider) {
        guard labelText != lastText || utilization != lastUtilization || provider != lastProvider else { return }
        lastText = labelText
        lastUtilization = utilization
        lastProvider = provider
        let color = UsageColor.forUtilization(utilization)
        cachedImage = MenuBarImageRenderer.render(MenuBarLabelContent(labelText: labelText, provider: provider, color: color, opacity: 1.0))
        loadingImage = MenuBarImageRenderer.render(MenuBarLabelContent(labelText: labelText, provider: provider, color: color, opacity: 0.4))
    }
}

struct MenuBarLabel: View {
    let labelText: String
    let utilization: Int
    let provider: MenuBarProvider
    let isRefreshing: Bool

    @State private var state = MenuBarLabelState()

    var body: some View {
        let _ = state.updateIfNeeded(labelText: labelText, utilization: utilization, provider: provider)
        if isRefreshing, let img = state.loadingImage {
            Image(nsImage: img)
        } else if let img = state.cachedImage {
            Image(nsImage: img)
        } else {
            Image(provider.menuBarIconName)
                .renderingMode(.template)
        }
    }

    struct LabelInfo: Equatable {
        let text: String
        let utilization: Int
    }

    static func extractLabelInfo(
        provider: MenuBarProvider, displayMode: MenuBarDisplayMode,
        usageData: UsageData, copilotData: CopilotUsageData,
        glmData: GLMUsageData, kimiData: KimiUsageData, codexData: CodexUsageData,
        minimaxData: MinimaxUsageData
    ) -> LabelInfo {
        let text: String
        let utilization: Int

        switch provider {
        case .claude:
            let pct = "\(usageData.fiveHour.utilization)%"
            utilization = usageData.fiveHour.utilization
            switch displayMode {
            case .classic:
                let base = "5h \(pct)"
                if let resetsAt = usageData.fiveHour.resetsAt {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "h:mma"
                    fmt.amSymbol = "am"
                    fmt.pmSymbol = "pm"
                    text = "\(base) · \(fmt.string(from: resetsAt))"
                } else {
                    text = base
                }
            case .percent:
                text = pct
            case .pace:
                if let result = UsagePace.calculate(
                    usagePercent: usageData.fiveHour.utilization,
                    resetsAt: usageData.fiveHour.resetsAt,
                    windowDurationHours: 5.0
                ) {
                    let rounded = Int(result.deltaPercent.rounded())
                    text = rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
                } else {
                    text = pct
                }
            case .both:
                if let result = UsagePace.calculate(
                    usagePercent: usageData.fiveHour.utilization,
                    resetsAt: usageData.fiveHour.resetsAt,
                    windowDurationHours: 5.0
                ) {
                    let rounded = Int(result.deltaPercent.rounded())
                    let pace = rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
                    text = "\(pct) · \(pace)"
                } else {
                    text = pct
                }
            }
        case .copilot:
            text = "\(copilotData.premiumInteractions.utilization)%"
            utilization = copilotData.premiumInteractions.utilization
        case .glm:
            text = "\(glmData.tokensPercent)%"
            utilization = glmData.tokensPercent
        case .kimi:
            text = String(format: "¥%.2f", kimiData.totalBalance)
            utilization = kimiData.totalBalance > 0 ? 10 : 100
        case .codex:
            text = "\(codexData.primaryPercent)%"
            utilization = codexData.highestUtilization
        case .minimax:
            let pct = "\(minimaxData.highestIntervalPercent)%"
            utilization = minimaxData.highestIntervalPercent
            switch displayMode {
            case .classic:
                let base = "5h \(pct)"
                if let resetsAt = minimaxData.nextResetAt {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "h:mma"
                    fmt.amSymbol = "am"
                    fmt.pmSymbol = "pm"
                    text = "\(base) · \(fmt.string(from: resetsAt))"
                } else {
                    text = base
                }
            case .percent:
                text = pct
            case .pace:
                text = pct
            case .both:
                text = pct
            }
        }

        return LabelInfo(text: text, utilization: utilization)
    }
}

private struct MenuBarLabelContent: View {
    let labelText: String
    let provider: MenuBarProvider
    let color: Color
    let opacity: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(provider.menuBarIconName)
                .renderingMode(.template)
                .foregroundStyle(color)
                .opacity(opacity)
            Text(labelText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(color)
                .opacity(opacity)
        }
        .fixedSize()
    }
}
