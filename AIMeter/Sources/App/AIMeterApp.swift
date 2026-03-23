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

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .copilot: "Copilot"
        case .glm: "GLM"
        case .kimi: "Kimi"
        case .codex: "Codex"
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
    @StateObject private var codexService = CodexService()
    @StateObject private var codexAuthManager = CodexAuthManager()
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
    @State private var isRefreshing = false
    @State private var recapService: RecapService?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private func interval(for provider: MenuBarProvider) -> Double {
        guard perProviderRefresh else { return refreshInterval }
        switch provider {
        case .claude: return refreshClaude
        case .copilot: return refreshCopilot
        case .glm: return refreshGLM
        case .kimi: return refreshKimi
        case .codex: return refreshCodex
        }
    }

    var body: some Scene {
        let refreshAll: () -> Void = {
            guard !isRefreshing else { return }
            isRefreshing = true
            Task { @MainActor in
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await service.fetch() }
                    group.addTask { await copilotService.fetch() }
                    group.addTask { await glmService.fetch() }
                    group.addTask { await kimiService.fetch() }
                    group.addTask { await codexService.fetch() }
                }
                statsService.load()
                try? await Task.sleep(for: .milliseconds(600))
                isRefreshing = false
            }
        }
        let restartAll: () -> Void = {
            service.stop()
            service.start(interval: interval(for: .claude), authManager: authManager, historyService: historyService)
            copilotService.stop()
            copilotService.start(interval: interval(for: .copilot), historyService: copilotHistoryService)
            glmService.stop()
            glmService.start(interval: interval(for: .glm), historyService: glmHistoryService)
            kimiService.stop()
            kimiService.start(interval: interval(for: .kimi), historyService: kimiHistoryService)
            codexService.stop()
            codexService.start(interval: interval(for: .codex), authManager: codexAuthManager, historyService: codexHistoryService)
            statsService.stop()
            statsService.start(interval: interval(for: .claude))
        }
        MenuBarExtra {
            if !hasCompletedOnboarding {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            } else {
                PopoverView(onRefresh: refreshAll)
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
                    .environmentObject(updaterManager)
                    .environmentObject(authManager)
                    .environmentObject(statsService)
                    .environmentObject(historyService)
                    .environmentObject(providerStatusService)
                    .task {
                        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
                        NotificationManager.shared.requestPermission()
                        service.start(interval: interval(for: .claude), authManager: authManager, historyService: historyService)
                        copilotService.start(interval: interval(for: .copilot), historyService: copilotHistoryService)
                        glmService.start(interval: interval(for: .glm), historyService: glmHistoryService)
                        kimiService.start(interval: interval(for: .kimi), historyService: kimiHistoryService)
                        codexService.start(interval: interval(for: .codex), authManager: codexAuthManager, historyService: codexHistoryService)
                        statsService.start(interval: interval(for: .claude))
                        if checkProviderStatus { providerStatusService.start() }

                        if recapService == nil {
                            recapService = RecapService(quotaHistoryService: historyService, copilotHistoryService: copilotHistoryService)
                        }
                        let recapSvc = recapService!
                        recapSvc.checkAndGenerateRecap(notificationManager: NotificationManager.shared)

                        GlobalHotKeyManager.shared.start()

                        for await _ in NotificationCenter.default.notifications(named: .openLatestRecap) {
                            let recaps = recapSvc.loadSavedRecaps()
                            if let latest = recaps.last {
                                RecapWindowController.show(recap: latest)
                            }
                        }
                    }
                    .task {
                        for await _ in NotificationCenter.default.notifications(named: .forceRefreshAll) {
                            refreshAll()
                        }
                    }
                    .onChange(of: refreshInterval) { _, _ in restartAll() }
                    .onChange(of: perProviderRefresh) { _, _ in restartAll() }
                    .onChange(of: refreshClaude) { _, _ in restartAll() }
                    .onChange(of: refreshCopilot) { _, _ in restartAll() }
                    .onChange(of: refreshGLM) { _, _ in restartAll() }
                    .onChange(of: refreshKimi) { _, _ in restartAll() }
                    .onChange(of: refreshCodex) { _, _ in restartAll() }
                    .onChange(of: checkProviderStatus) { _, enabled in
                        if enabled { providerStatusService.start() } else { providerStatusService.stop() }
                    }
                    .onChange(of: authManager.isAuthenticated) { _, isAuth in
                        if isAuth {
                            Task { await service.fetch() }
                        }
                    }
                    .onChange(of: codexAuthManager.isAuthenticated) { _, isAuth in
                        if isAuth {
                            Task { await codexService.fetch() }
                        }
                    }
            }
        } label: {
            let selected = MenuBarProvider(rawValue: menuBarProvider) ?? .claude
            let mode = MenuBarDisplayMode(rawValue: menuBarDisplayMode) ?? .classic
            let labelInfo = MenuBarLabel.extractLabelInfo(
                provider: selected, displayMode: mode,
                usageData: service.usageData, copilotData: copilotService.copilotData,
                glmData: glmService.glmData, kimiData: kimiService.kimiData,
                codexData: codexService.codexData
            )
            MenuBarLabel(
                labelText: labelInfo.text,
                utilization: labelInfo.utilization,
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

    func updateIfNeeded(labelText: String, utilization: Int) {
        guard labelText != lastText || utilization != lastUtilization else { return }
        lastText = labelText
        lastUtilization = utilization
        let color = UsageColor.forUtilization(utilization)
        cachedImage = MenuBarImageRenderer.render(MenuBarLabelContent(labelText: labelText, color: color, opacity: 1.0))
        loadingImage = MenuBarImageRenderer.render(MenuBarLabelContent(labelText: labelText, color: color, opacity: 0.4))
    }
}

struct MenuBarLabel: View {
    let labelText: String
    let utilization: Int
    let isRefreshing: Bool

    @State private var state = MenuBarLabelState()

    var body: some View {
        let _ = state.updateIfNeeded(labelText: labelText, utilization: utilization)
        if isRefreshing, let img = state.loadingImage {
            Image(nsImage: img)
        } else if let img = state.cachedImage {
            Image(nsImage: img)
        } else {
            Image(systemName: "sparkles")
        }
    }

    struct LabelInfo: Equatable {
        let text: String
        let utilization: Int
    }

    static func extractLabelInfo(
        provider: MenuBarProvider, displayMode: MenuBarDisplayMode,
        usageData: UsageData, copilotData: CopilotUsageData,
        glmData: GLMUsageData, kimiData: KimiUsageData, codexData: CodexUsageData
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
        }

        return LabelInfo(text: text, utilization: utilization)
    }
}

private struct MenuBarLabelContent: View {
    let labelText: String
    let color: Color
    let opacity: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
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
