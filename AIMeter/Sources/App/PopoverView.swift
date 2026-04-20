import SwiftUI

// MARK: - Tab

enum Tab: String {
    case claude, copilot, glm, kimi, codex, minimax, settings

    static let defaultOrder: [Tab] = [.claude, .copilot, .glm, .kimi, .codex, .minimax]
    static let defaultOrderString = "claude,copilot,glm,kimi,codex,minimax"

    var displayName: String {
        switch self {
        case .claude:   return "Claude"
        case .copilot:  return "Copilot"
        case .glm:      return "GLM"
        case .kimi:     return "Kimi"
        case .codex:    return "Codex"
        case .minimax:  return "MiniMax"
        case .settings: return "Settings"
        }
    }

    var icon: TabIcon {
        switch self {
        case .claude:   return .asset("claude")
        case .copilot:  return .asset("copilot")
        case .glm:      return .asset("glm")
        case .kimi:     return .asset("kimi")
        case .codex:    return .asset("codex")
        case .minimax:  return .asset("minimax")
        case .settings: return .system("gear")
        }
    }

    var smallImageName: String {
        switch self {
        case .claude:   return "claude-small"
        case .copilot:  return "copilot-small"
        case .glm:      return "glm-small"
        case .kimi:     return "kimi-small"
        case .codex:    return "codex-small"
        case .minimax:  return "minimax-small"
        case .settings: return ""
        }
    }

    var index: Int {
        switch self {
        case .claude:   return 0
        case .copilot:  return 1
        case .glm:      return 2
        case .kimi:     return 3
        case .codex:    return 4
        case .minimax:  return 5
        case .settings: return 6
        }
    }
}

// Decode the comma-separated providerTabOrder string into an ordered [Tab] array
func decodedProviderOrder(_ stored: String) -> [Tab] {
    let parsed = stored.split(separator: ",").compactMap { Tab(rawValue: String($0)) }
    // Fill in any missing providers so we never lose a tab
    let all = Tab.defaultOrder
    let missing = all.filter { !parsed.contains($0) }
    return parsed + missing
}

func tabForShortcutDigit(_ digit: String, providerOrder: [Tab]) -> Tab? {
    guard let shortcutIndex = Int(digit), shortcutIndex >= 1, shortcutIndex <= providerOrder.count else {
        return nil
    }
    return providerOrder[shortcutIndex - 1]
}

// MARK: - TabIcon

enum TabIcon {
    case system(String)
    case asset(String)
}

private enum ProviderNavTheme {
    static let rail = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let plate = Color(red: 0.22, green: 0.22, blue: 0.23)
    static let edge = Color.white.opacity(0.08)
    static let strongEdge = Color.white.opacity(0.14)
    static let inactive = Color(red: 0.66, green: 0.66, blue: 0.64)
    static let activeText = Color.white
}

// MARK: - TabBarView

struct TabBarView: View {
    @Binding var selectedTab: Tab
    var onSettingsTap: (() -> Void)? = nil
    @AppStorage("providerTabOrder") private var providerTabOrder: String = Tab.defaultOrderString

    private var orderedTabs: [Tab] { decodedProviderOrder(providerTabOrder) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(orderedTabs, id: \.self) { tab in
                tabButton(tab, icon: tab.icon, label: tab.displayName)
            }
            Spacer(minLength: 2)
            // Gear opens the settings window directly instead of a settings tab
            Button {
                onSettingsTap?()
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ProviderNavTheme.inactive)
                    .frame(width: 30, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(ProviderNavTheme.edge, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings tab")
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ProviderNavTheme.rail)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ProviderNavTheme.edge, lineWidth: 1)
        )
    }

    private func tabButton(_ tab: Tab, icon: TabIcon, label: String?) -> some View {
        let isSelected = selectedTab == tab
        let accent = accentColor(for: tab)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            HStack(spacing: 5) {
                switch icon {
                case .system(let name):
                    Image(systemName: name)
                        .font(.system(size: 11, weight: .semibold))
                case .asset(let name):
                    Image(name)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                }
                if let label = label, isSelected {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundColor(isSelected ? ProviderNavTheme.activeText : ProviderNavTheme.inactive)
            .padding(.horizontal, isSelected ? 10 : 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? ProviderNavTheme.plate : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if isSelected {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)
                        .padding(.leading, 6)
                }
            }
            .shadow(color: isSelected ? Color.black.opacity(0.18) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.displayName) tab")
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func accentColor(for tab: Tab) -> Color {
        switch tab {
        case .claude: return ProviderTheme.claude.accentColor
        case .copilot: return ProviderTheme.copilot.accentColor
        case .glm: return ProviderTheme.glm.accentColor
        case .kimi: return ProviderTheme.kimi.accentColor
        case .codex: return ProviderTheme.codex.accentColor
        case .minimax: return ProviderTheme.minimax.accentColor
        case .settings: return ProviderNavTheme.inactive
        }
    }
}

// MARK: - SummaryStripView

struct SummaryStripView: View {
    @Binding var selectedTab: Tab
    let claudeUtilization: Int?
    let copilotUtilization: Int?
    let glmUtilization: Int?
    let kimiBalance: Double?
    let codexUtilization: Int?
    let minimaxUtilization: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if selectedTab != .claude, let util = claudeUtilization {
                    pill(tab: .claude, theme: .claude, text: "\(util)%", utilization: util)
                }
                if selectedTab != .copilot, let util = copilotUtilization {
                    pill(tab: .copilot, theme: .copilot, text: "\(util)%", utilization: util)
                }
                if selectedTab != .glm, let util = glmUtilization {
                    pill(tab: .glm, theme: .glm, text: "\(util)%", utilization: util)
                }
                if selectedTab != .kimi, let balance = kimiBalance {
                    pill(tab: .kimi, theme: .kimi, text: String(format: "¥%.2f", balance), utilization: balance > 0 ? 10 : 100)
                }
                if selectedTab != .codex, let util = codexUtilization {
                    pill(tab: .codex, theme: .codex, text: "\(util)%", utilization: util)
                }
                if selectedTab != .minimax, let util = minimaxUtilization {
                    pill(tab: .minimax, theme: .minimax, text: "\(util)%", utilization: util)
                }
            }
        }
    }

    private func pill(tab: Tab, theme: ProviderTheme, text: String, utilization: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(UsageColor.forUtilization(utilization))
                    .frame(width: 5, height: 5)
                Text(theme.displayName)
                    .font(.system(size: AppTypeScale.micro))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(text)
                    .font(.system(size: AppTypeScale.micro, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(theme.accentColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName): \(text). \(UsageColor.levelDescription(utilization))")
    }
}

// MARK: - ProviderDemoTabView

private struct ProviderDemoTabView: View {
    let tab: Tab
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    private var accent: Color {
        switch tab {
        case .claude: return ProviderTheme.claude.accentColor
        case .copilot: return ProviderTheme.copilot.accentColor
        case .glm: return ProviderTheme.glm.accentColor
        case .kimi: return ProviderTheme.kimi.accentColor
        case .codex: return ProviderTheme.codex.accentColor
        case .minimax: return ProviderTheme.minimax.accentColor
        case .settings: return .gray
        }
    }

    private var metricLabel: String {
        switch tab {
        case .kimi: return "Wallet"
        case .codex: return "Primary"
        case .minimax: return "Interval"
        default: return "Usage"
        }
    }

    private var metricValue: String {
        switch tab {
        case .claude: return "72%"
        case .copilot: return "58%"
        case .glm: return "64%"
        case .kimi: return "¥36.30"
        case .codex: return "41%"
        case .minimax: return "67%"
        case .settings: return "--"
        }
    }

    private var laneRows: [(String, String)] {
        switch tab {
        case .claude:
            return [("Session", "72%"), ("Weekly", "49%")]
        case .copilot:
            return [("Chat", "32%"), ("Premium", "58%")]
        case .glm:
            return [("Tokens", "64%"), ("Tier", "Pro")]
        case .kimi:
            return [("Cash", "¥24.88"), ("Voucher", "¥11.42")]
        case .codex:
            return [("5h", "41%"), ("7d", "33%")]
        case .minimax:
            return [("Top Model", "67%"), ("Weekly", "44%")]
        case .settings:
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.displayName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Demo Preview")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(accent.opacity(0.9))
                        .textCase(.uppercase)
                }
                Spacer()
                Text("Demo")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(metricLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Text(metricValue)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Live calls are bypassed while demo toggle is enabled.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )

            VStack(spacing: 0) {
                ForEach(Array(laneRows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Text(row.0)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(row.1)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 8)

                    if index < laneRows.count - 1 {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))

            HStack {
                Text("Demo mode active")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Settings", action: onOpenSettings)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - PopoverView

struct PopoverView: View {
    @EnvironmentObject var service: UsageService
    @EnvironmentObject var copilotService: CopilotService
    @EnvironmentObject var copilotHistoryService: CopilotHistoryService
    @EnvironmentObject var glmHistoryService: GLMHistoryService
    @EnvironmentObject var kimiHistoryService: KimiHistoryService
    @EnvironmentObject var codexHistoryService: CodexHistoryService
    @EnvironmentObject var glmService: GLMService
    @EnvironmentObject var kimiService: KimiService
    @EnvironmentObject var codexService: CodexService
    @EnvironmentObject var codexAuthManager: CodexAuthManager
    @EnvironmentObject var codexStatsService: CodexSessionStatsService
    @EnvironmentObject var apiKeyAuthManagers: APIKeyAuthManagers
    @EnvironmentObject var minimaxService: MinimaxService
    @EnvironmentObject var minimaxHistoryService: MinimaxHistoryService
    @EnvironmentObject var updaterManager: UpdaterManager
    @EnvironmentObject var authManager: SessionAuthManager
    @EnvironmentObject var statsService: ClaudeCodeStatsService
    @EnvironmentObject var claudeSessionStatsService: ClaudeSessionStatsService
    @EnvironmentObject var historyService: QuotaHistoryService
    @EnvironmentObject var providerStatusService: ProviderStatusService
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    var onRefresh: () -> Void
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @AppStorage("navigationStyle") private var navigationStyle: String = "tabbar"
    @AppStorage("hasSeenRefreshHint") private var hasSeenRefreshHint = false
    @AppStorage("providerTabOrder") private var providerTabOrder: String = Tab.defaultOrderString
    @AppStorage("demoUIClaude") private var demoUIClaude: Bool = false
    @AppStorage("demoUICopilot") private var demoUICopilot: Bool = false
    @AppStorage("demoUIGLM") private var demoUIGLM: Bool = false
    @AppStorage("demoUIKimi") private var demoUIKimi: Bool = false
    @AppStorage("demoUICodex") private var demoUICodex: Bool = false
    @AppStorage("demoUIMiniMax") private var demoUIMiniMax: Bool = false
    @AppStorage("forceEmptyStatesAllProviders") private var forceEmptyStatesAllProviders: Bool = false
    @State private var selectedTab: Tab = .claude
    @State private var slideDirection: Edge = .trailing
    @State private var eventMonitor: Any?

    private var useTabBar: Bool { navigationStyle == "tabbar" }

    private var configuredTimeZone: TimeZone {
        TimeZone(secondsFromGMT: timezoneOffset * 3600) ?? .current
    }

    private func switchTab(to newTab: Tab) {
        // Use visual order from stored provider order for slide direction
        let order = decodedProviderOrder(providerTabOrder)
        let currentPos = order.firstIndex(of: selectedTab) ?? selectedTab.index
        let newPos = order.firstIndex(of: newTab) ?? newTab.index
        slideDirection = newPos > currentPos ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = newTab }
    }

    private func showSettingsWindow() {
        SettingsWindowController.show(
            updaterManager: updaterManager,
            authManager: authManager,
            codexAuthManager: codexAuthManager,
            glmAuthManager: apiKeyAuthManagers.glm,
            kimiAuthManager: apiKeyAuthManagers.kimi,
            minimaxAuthManager: apiKeyAuthManagers.minimax,
            historyService: historyService,
            copilotHistoryService: copilotHistoryService
        )
    }

    private func showClaudeAnalyticsWindow() {
        ClaudeSessionAnalyticsWindowController.show(statsService: claudeSessionStatsService)
    }

    private func showCodexAnalyticsWindow() {
        CodexAnalyticsWindowController.show(statsService: codexStatsService)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Text("AI Meter")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                if !useTabBar {
                    // Dropdown navigation — respects stored provider order
                    Menu {
                        ForEach(decodedProviderOrder(providerTabOrder), id: \.self) { tab in
                            Button { switchTab(to: tab) } label: {
                                Label {
                                    Text(tab.displayName)
                                } icon: {
                                    Image(tab.smallImageName).renderingMode(.template)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedTab.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    // Settings icon (dropdown mode only) — opens dedicated window
                    Button {
                        showSettingsWindow()
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
            }
            .padding(.bottom, useTabBar ? 4 : 12)

            // Tab bar (when enabled)
            if useTabBar {
                TabBarView(selectedTab: $selectedTab, onSettingsTap: showSettingsWindow)
                    .padding(.bottom, 8)
            }

            // Usage chips — show on all provider tabs except Settings, excluding current selected provider.
            if selectedTab != .settings {
                SummaryStripView(
                    selectedTab: $selectedTab,
                    claudeUtilization: isDemoEnabled(for: .claude) ? 72 : (authManager.isAuthenticated ? service.usageData.fiveHour.utilization : nil),
                    copilotUtilization: isDemoEnabled(for: .copilot) ? 58 : (copilotService.error != .noToken ? copilotService.copilotData.premiumInteractions.utilization : nil),
                    glmUtilization: isDemoEnabled(for: .glm) ? 64 : (glmService.error != .noKey ? glmService.glmData.tokensPercent : nil),
                    kimiBalance: isDemoEnabled(for: .kimi) ? 36.30 : (kimiService.error != .noKey ? kimiService.kimiData.totalBalance : nil),
                    codexUtilization: isDemoEnabled(for: .codex) ? 41 : (codexAuthManager.isAuthenticated ? codexService.codexData.primaryPercent : nil),
                    minimaxUtilization: isDemoEnabled(for: .minimax) ? 67 : (minimaxService.error != .noKey ? minimaxService.minimaxData.highestIntervalPercent : nil)
                )
                .padding(.bottom, 6)
            }

            // Content
            Group {
                switch selectedTab {
                case .claude:
                    if isDemoEnabled(for: .claude) && !isEmptyStateForced(for: .claude) {
                        ProviderDemoTabView(tab: .claude, onRefresh: onRefresh, onOpenSettings: showSettingsWindow)
                    } else if isEmptyStateForced(for: .claude) || !authManager.isAuthenticated {
                        signInPromptView
                    } else {
                        ClaudeTabView(
                            service: service,
                            statsService: statsService,
                            timeZone: configuredTimeZone,
                            planName: resolvedPlanName,
                            providerStatus: providerStatusService.statuses["Claude"],
                            onOpenAnalytics: showClaudeAnalyticsWindow,
                            onRefresh: onRefresh,
                            onOpenSettings: showSettingsWindow
                        )
                    }
                case .copilot:
                    if isDemoEnabled(for: .copilot) && !isEmptyStateForced(for: .copilot) {
                        ProviderDemoTabView(tab: .copilot, onRefresh: onRefresh, onOpenSettings: showSettingsWindow)
                    } else {
                        CopilotTabView(
                            copilotService: copilotService,
                            historyService: copilotHistoryService,
                            timeZone: configuredTimeZone,
                            providerStatus: providerStatusService.statuses["Copilot"],
                            forceEmptyState: isEmptyStateForced(for: .copilot),
                            onRefresh: onRefresh,
                            onOpenSettings: showSettingsWindow
                        )
                    }
                case .glm:
                    GLMTabView(
                        glmService: glmService,
                        historyService: glmHistoryService,
                        providerStatus: providerStatusService.statuses["GLM"],
                        forceDemo: isDemoEnabled(for: .glm) && !isEmptyStateForced(for: .glm),
                        forceEmptyState: isEmptyStateForced(for: .glm),
                        onKeySaved: {
                            Task { await glmService.fetch() }
                        },
                        onRefresh: onRefresh,
                        onOpenSettings: showSettingsWindow
                    )
                case .kimi:
                    KimiTabView(
                        kimiService: kimiService,
                        historyService: kimiHistoryService,
                        providerStatus: providerStatusService.statuses["Kimi"],
                        forceDemo: isDemoEnabled(for: .kimi) && !isEmptyStateForced(for: .kimi),
                        forceEmptyState: isEmptyStateForced(for: .kimi),
                        onKeySaved: {
                            Task { await kimiService.fetch() }
                        },
                        onRefresh: onRefresh,
                        onOpenSettings: showSettingsWindow
                    )
                case .codex:
                    if isDemoEnabled(for: .codex) && !isEmptyStateForced(for: .codex) {
                        ProviderDemoTabView(tab: .codex, onRefresh: onRefresh, onOpenSettings: showSettingsWindow)
                    } else {
                        CodexTabView(
                            codexService: codexService,
                            codexAuthManager: codexAuthManager,
                            historyService: codexHistoryService,
                            statsService: codexStatsService,
                            timeZone: configuredTimeZone,
                            providerStatus: providerStatusService.statuses["Codex"],
                            forceEmptyState: isEmptyStateForced(for: .codex),
                            onOpenAnalytics: showCodexAnalyticsWindow,
                            onRefresh: onRefresh,
                            onOpenSettings: showSettingsWindow
                        )
                    }
                case .minimax:
                    if isDemoEnabled(for: .minimax) && !isEmptyStateForced(for: .minimax) {
                        ProviderDemoTabView(tab: .minimax, onRefresh: onRefresh, onOpenSettings: showSettingsWindow)
                    } else {
                        MinimaxTabView(
                            minimaxService: minimaxService,
                            historyService: minimaxHistoryService,
                            forceEmptyState: isEmptyStateForced(for: .minimax),
                            onKeySaved: {
                                Task { await minimaxService.fetch() }
                            },
                            onRefresh: onRefresh,
                            onOpenSettings: showSettingsWindow
                        )
                    }
                case .settings:
                    EmptyView()
                }
            }
            .id(selectedTab)
            .transition(.push(from: slideDirection))
            .animation(.easeInOut(duration: 0.2), value: selectedTab)

            if selectedTab != .settings {
                Spacer(minLength: 0)
                if ((selectedTab != .claude && selectedTab != .codex && selectedTab != .copilot && selectedTab != .minimax && selectedTab != .kimi && selectedTab != .glm) || !networkMonitor.isConnected) && !isDemoEnabled(for: selectedTab) {
                    Divider().background(Color.gray.opacity(0.3))
                }

                // Footer — redesigned providers own local footers; others keep the generic footer.
                if !networkMonitor.isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("Offline — updates paused")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                        .padding(.top, 4)
                }

                if selectedTab != .claude && selectedTab != .codex && selectedTab != .copilot && selectedTab != .minimax && selectedTab != .kimi && selectedTab != .glm && !isDemoEnabled(for: selectedTab) {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        HStack {
                            if !updatedText.isEmpty {
                                Text(updatedText)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                if isStale {
                                    Text("(stale)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                }
                            }
                            Spacer()
                            Button {
                                if let url = URL(string: "https://claude.ai") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Image(systemName: "globe")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Open claude.ai")

                            Button(action: onRefresh) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Refresh (⌘R)")
                        }
                    }
                    .padding(.top, 8)

                    if !hasSeenRefreshHint {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text("Tip: Press ⌘R to refresh")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Got it") {
                                hasSeenRefreshHint = true
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Arrow keys — navigate between provider tabs in stored order (no modifier needed)
                if event.keyCode == 123 { // left arrow
                    let tabs = decodedProviderOrder(providerTabOrder)
                    if let idx = tabs.firstIndex(of: selectedTab), idx > 0 {
                        switchTab(to: tabs[idx - 1])
                    }
                    return nil
                }
                if event.keyCode == 124 { // right arrow
                    let tabs = decodedProviderOrder(providerTabOrder)
                    if let idx = tabs.firstIndex(of: selectedTab), idx < tabs.count - 1 {
                        switchTab(to: tabs[idx + 1])
                    }
                    return nil
                }

                guard event.modifierFlags.contains(.command) else { return event }
                let key = event.charactersIgnoringModifiers ?? ""
                let tabs = decodedProviderOrder(providerTabOrder)

                if let tab = tabForShortcutDigit(key, providerOrder: tabs) {
                    switchTab(to: tab)
                    return nil
                }

                switch key {
                case "r":
                    onRefresh()
                    return nil
                case String(tabs.count + 1), ",":
                    showSettingsWindow()
                    return nil
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        .onOpenURL { url in
            guard url.scheme == "aimeter",
                  url.host == "tab",
                  let tabName = url.pathComponents.dropFirst().first else { return }
            switch tabName {
            case "claude": selectedTab = .claude
            case "copilot": selectedTab = .copilot
            case "glm": selectedTab = .glm
            case "kimi": selectedTab = .kimi
            case "codex": selectedTab = .codex
            case "minimax": selectedTab = .minimax
            default: break
            }
        }
    }

    /// Plan name from login (rate_limit_tier) or API (seat_tier)
    private var resolvedPlanName: String? {
        if let plan = service.usageData.planName { return plan }
        if let plan = authManager.planName { return plan }
        return nil
    }

    private func isDemoEnabled(for tab: Tab) -> Bool {
        switch tab {
        case .claude: return demoUIClaude
        case .copilot: return demoUICopilot
        case .glm: return demoUIGLM
        case .kimi: return demoUIKimi
        case .codex: return demoUICodex
        case .minimax: return demoUIMiniMax
        case .settings: return false
        }
    }

    private func isEmptyStateForced(for tab: Tab) -> Bool {
        guard tab != .settings else { return false }
        return forceEmptyStatesAllProviders
    }

    private var isStale: Bool {
        switch selectedTab {
        case .claude: return service.isStale
        case .copilot: return copilotService.isStale
        case .glm: return glmService.isStale
        case .kimi: return kimiService.isStale
        case .codex: return codexService.isStale
        case .minimax: return minimaxService.isStale
        case .settings: return false
        }
    }

    private var updatedText: String {
        let fetchedAt: Date
        switch selectedTab {
        case .claude: fetchedAt = service.usageData.fetchedAt
        case .copilot: fetchedAt = copilotService.copilotData.fetchedAt
        case .glm: fetchedAt = glmService.glmData.fetchedAt
        case .kimi: fetchedAt = kimiService.kimiData.fetchedAt
        case .codex: fetchedAt = codexService.codexData.fetchedAt
        case .minimax: fetchedAt = minimaxService.minimaxData.fetchedAt
        case .settings: return ""
        }
        if fetchedAt == .distantPast { return "" }
        let seconds = Int(Date().timeIntervalSince(fetchedAt))
        if seconds < 60 { return "Updated just now" }
        return "Updated \(seconds / 60)m ago"
    }

    private var signInPromptView: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ProviderTheme.claude.accentColor.opacity(0.14))
                    .frame(width: 68, height: 68)
                Image("claude")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundColor(ProviderTheme.claude.accentColor)
            }

            VStack(spacing: 4) {
                Text("Claude control plane offline")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Sign in to track session and weekly quota telemetry.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                authManager.openLoginWindow()
            } label: {
                Text("Sign in with Claude")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.black.opacity(0.82))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(ProviderTheme.claude.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(authManager.isLoggingIn)

            if authManager.isLoggingIn {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                    Text("Waiting for login...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            if let error = authManager.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ProviderTheme.claude.accentColor.opacity(0.28), lineWidth: 1)
        )
    }
}
