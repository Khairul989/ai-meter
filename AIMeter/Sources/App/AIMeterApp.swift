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

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .copilot: "Copilot"
        case .glm: "GLM"
        case .kimi: "Kimi"
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
    @StateObject private var updaterManager = UpdaterManager()
    @StateObject private var authManager = SessionAuthManager()
    @StateObject private var historyService = QuotaHistoryService()
    @StateObject private var statsService = ClaudeCodeStatsService()
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("menuBarProvider") private var menuBarProvider: String = MenuBarProvider.claude.rawValue
    @State private var isRefreshing = false

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
                }
                statsService.load()
                try? await Task.sleep(for: .milliseconds(600))
                isRefreshing = false
            }
        }
        MenuBarExtra {
            PopoverView(onRefresh: refreshAll)
                .environmentObject(service)
                .environmentObject(copilotService)
                .environmentObject(copilotHistoryService)
                .environmentObject(glmService)
                .environmentObject(kimiService)
                .environmentObject(updaterManager)
                .environmentObject(authManager)
                .environmentObject(statsService)
                .task {
                    UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
                    service.start(interval: refreshInterval, authManager: authManager, historyService: historyService)
                    copilotService.start(interval: refreshInterval, historyService: copilotHistoryService)
                    glmService.start(interval: refreshInterval)
                    kimiService.start(interval: refreshInterval)
                    statsService.start(interval: refreshInterval)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    service.stop()
                    service.start(interval: newValue, authManager: authManager, historyService: historyService)
                    copilotService.stop()
                    copilotService.start(interval: newValue, historyService: copilotHistoryService)
                    glmService.stop()
                    glmService.start(interval: newValue)
                    kimiService.stop()
                    kimiService.start(interval: newValue)
                    statsService.stop()
                    statsService.start(interval: newValue)
                }
                .onChange(of: authManager.isAuthenticated) { _, isAuth in
                    if isAuth {
                        Task { await service.fetch() }
                    }
                }
        } label: {
            MenuBarLabel(
                provider: MenuBarProvider(rawValue: menuBarProvider) ?? .claude,
                usageData: service.usageData,
                copilotData: copilotService.copilotData,
                glmData: glmService.glmData,
                kimiData: kimiService.kimiData,
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
