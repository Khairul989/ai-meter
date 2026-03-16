import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        NotificationManager.shared.handleSnoozeAction(response.actionIdentifier)
        completionHandler()
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
    @StateObject private var glmService = GLMService()
    @StateObject private var kimiService = KimiService()
    @StateObject private var codexService = CodexService()
    @StateObject private var codexAuthManager = CodexAuthManager()
    @StateObject private var updaterManager = UpdaterManager()
    @StateObject private var authManager = SessionAuthManager()
    @StateObject private var historyService = QuotaHistoryService()
    @StateObject private var statsService = ClaudeCodeStatsService()
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("menuBarProvider") private var menuBarProvider: String = MenuBarProvider.claude.rawValue
    @AppStorage("perProviderRefresh") private var perProviderRefresh: Bool = false
    @AppStorage("refreshClaude") private var refreshClaude: Double = 60
    @AppStorage("refreshCopilot") private var refreshCopilot: Double = 60
    @AppStorage("refreshGLM") private var refreshGLM: Double = 120
    @AppStorage("refreshKimi") private var refreshKimi: Double = 300
    @AppStorage("refreshCodex") private var refreshCodex: Double = 300
    @State private var isRefreshing = false
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
            glmService.start(interval: interval(for: .glm))
            kimiService.stop()
            kimiService.start(interval: interval(for: .kimi))
            codexService.stop()
            codexService.start(interval: interval(for: .codex), authManager: codexAuthManager)
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
                    .environmentObject(glmService)
                    .environmentObject(kimiService)
                    .environmentObject(codexService)
                    .environmentObject(codexAuthManager)
                    .environmentObject(updaterManager)
                    .environmentObject(authManager)
                    .environmentObject(statsService)
                    .environmentObject(historyService)
                    .task {
                        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
                        service.start(interval: interval(for: .claude), authManager: authManager, historyService: historyService)
                        copilotService.start(interval: interval(for: .copilot), historyService: copilotHistoryService)
                        glmService.start(interval: interval(for: .glm))
                        kimiService.start(interval: interval(for: .kimi))
                        codexService.start(interval: interval(for: .codex), authManager: codexAuthManager)
                        statsService.start(interval: interval(for: .claude))
                    }
                    .onChange(of: refreshInterval) { _, _ in restartAll() }
                    .onChange(of: perProviderRefresh) { _, _ in restartAll() }
                    .onChange(of: refreshClaude) { _, _ in restartAll() }
                    .onChange(of: refreshCopilot) { _, _ in restartAll() }
                    .onChange(of: refreshGLM) { _, _ in restartAll() }
                    .onChange(of: refreshKimi) { _, _ in restartAll() }
                    .onChange(of: refreshCodex) { _, _ in restartAll() }
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
    let usageData: UsageData
    let copilotData: CopilotUsageData
    let glmData: GLMUsageData
    let kimiData: KimiUsageData
    let codexData: CodexUsageData
    let isRefreshing: Bool

    private var labelText: String {
        switch provider {
        case .claude:
            let pct = "5h \(usageData.fiveHour.utilization)%"
            if let reset = usageData.fiveHour.resetsAt {
                let fmt = DateFormatter()
                fmt.dateFormat = "h:mma"
                fmt.amSymbol = "am"
                fmt.pmSymbol = "pm"
                return "\(pct) · \(fmt.string(from: reset))"
            }
            return pct
        case .copilot:
            return "Premium \(copilotData.premiumInteractions.utilization)%"
        case .glm:
            return "GLM \(glmData.tokensPercent)%"
        case .kimi:
            return String(format: "Kimi ¥%.2f", kimiData.totalBalance)
        case .codex:
            return "Codex \(codexData.primaryPercent)%"
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

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .foregroundStyle(UsageColor.forUtilization(highestUtilization))
                .opacity(isRefreshing ? 0.3 : 1.0)
                .animation(
                    isRefreshing
                        ? .easeInOut(duration: 0.3).repeatForever(autoreverses: true)
                        : .linear(duration: 0),
                    value: isRefreshing
                )
            Text(labelText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(UsageColor.forUtilization(highestUtilization))
        }
    }
}
