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
            MenuBarLabel(
                provider: MenuBarProvider(rawValue: menuBarProvider) ?? .claude,
                displayMode: MenuBarDisplayMode(rawValue: menuBarDisplayMode) ?? .percent,
                usageData: service.usageData,
                copilotData: copilotService.copilotData,
                glmData: glmService.glmData,
                kimiData: kimiService.kimiData,
                codexData: codexService.codexData,
                isRefreshing: isRefreshing
            )
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let provider: MenuBarProvider
    let displayMode: MenuBarDisplayMode
    let usageData: UsageData
    let copilotData: CopilotUsageData
    let glmData: GLMUsageData
    let kimiData: KimiUsageData
    let codexData: CodexUsageData
    let isRefreshing: Bool

    @AppStorage("loadingPattern") private var loadingPatternRaw: String = LoadingPattern.fade.rawValue
    // Cycle duration in seconds — fast enough to feel smooth, slow enough to be subtle
    private let cycleDuration: Double = 2.0

    private var loadingPattern: LoadingPattern {
        LoadingPattern(rawValue: loadingPatternRaw) ?? .fade
    }

    // Format pace delta as "+5%", "-3%", or "0%"
    private func paceString(from delta: Double) -> String {
        let rounded = Int(delta.rounded())
        if rounded > 0 { return "+\(rounded)%" }
        return "\(rounded)%"
    }

    // Returns pace delta string for Claude only; nil if unavailable
    private var claudePaceText: String? {
        guard let result = UsagePace.calculate(
            usagePercent: usageData.fiveHour.utilization,
            resetsAt: usageData.fiveHour.resetsAt,
            windowDurationHours: 5.0
        ) else { return nil }
        return paceString(from: result.deltaPercent)
    }

    private func resetTimeString(_ date: Date?) -> String? {
        guard let date else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mma"
        fmt.amSymbol = "am"
        fmt.pmSymbol = "pm"
        return fmt.string(from: date)
    }

    private var labelText: String {
        switch provider {
        case .claude:
            let pct = "\(usageData.fiveHour.utilization)%"
            switch displayMode {
            case .classic:
                let base = "5h \(pct)"
                if let reset = resetTimeString(usageData.fiveHour.resetsAt) {
                    return "\(base) · \(reset)"
                }
                return base
            case .percent:
                return pct
            case .pace:
                return claudePaceText ?? pct
            case .both:
                if let pace = claudePaceText {
                    return "\(pct) · \(pace)"
                }
                return pct
            }
        case .copilot:
            return "\(copilotData.premiumInteractions.utilization)%"
        case .glm:
            return "\(glmData.tokensPercent)%"
        case .kimi:
            return String(format: "¥%.2f", kimiData.totalBalance)
        case .codex:
            return "\(codexData.primaryPercent)%"
        }
    }

    private var highestUtilization: Int {
        switch provider {
        case .claude:
            usageData.fiveHour.utilization
        case .copilot:
            copilotData.premiumInteractions.utilization
        case .glm:
            glmData.tokensPercent
        case .kimi:
            // Balance-based: green when positive, red when zero
            kimiData.totalBalance > 0 ? 10 : 100
        case .codex:
            codexData.highestUtilization
        }
    }

    private var usageColor: Color {
        UsageColor.forUtilization(highestUtilization)
    }

    var body: some View {
        if isRefreshing {
            TimelineView(.animation(minimumInterval: 0.1, paused: false)) { context in
                menuBarImage(at: context.date)
            }
        } else {
            menuBarImage(at: nil)
        }
    }

    private func opacity(at date: Date?) -> Double {
        guard let date else { return 1.0 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return loadingPattern.opacity(at: phase)
    }

    @ViewBuilder
    private func menuBarImage(at date: Date?) -> some View {
        let content = MenuBarLabelContent(labelText: labelText, color: usageColor, opacity: opacity(at: date))
        if let img = MenuBarImageRenderer.render(content) {
            Image(nsImage: img)
        } else {
            Image(systemName: "sparkles")
        }
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
