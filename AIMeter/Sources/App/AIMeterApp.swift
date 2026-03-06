import SwiftUI

enum MenuBarProvider: String, CaseIterable {
    case claude = "claude"
    case copilot = "copilot"
    case glm = "glm"

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .copilot: "Copilot"
        case .glm: "GLM"
        }
    }
}

@main
struct AIMeterApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var copilotService = CopilotService()
    @StateObject private var glmService = GLMService()
    @StateObject private var updaterManager = UpdaterManager()
    @StateObject private var authManager = SessionAuthManager()
    @StateObject private var historyService = QuotaHistoryService()
    @StateObject private var statsService = ClaudeCodeStatsService()
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("menuBarProvider") private var menuBarProvider: String = MenuBarProvider.claude.rawValue

    var body: some Scene {
        MenuBarExtra {
            PopoverView(service: service, copilotService: copilotService, glmService: glmService, updaterManager: updaterManager, authManager: authManager, statsService: statsService)
                .task {
                    service.start(interval: refreshInterval, authManager: authManager, historyService: historyService)
                    copilotService.start(interval: refreshInterval)
                    glmService.start(interval: refreshInterval)
                    statsService.start(interval: refreshInterval)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    service.stop()
                    service.start(interval: newValue, authManager: authManager, historyService: historyService)
                    copilotService.stop()
                    copilotService.start(interval: newValue)
                    glmService.stop()
                    glmService.start(interval: newValue)
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
                glmData: glmService.glmData
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
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .foregroundStyle(UsageColor.forUtilization(highestUtilization))
            Text(labelText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
    }
}
