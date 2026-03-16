import SwiftUI

// MARK: - Tab

enum Tab {
    case claude, copilot, glm, kimi, codex, settings

    var displayName: String {
        switch self {
        case .claude:   return "Claude"
        case .copilot:  return "Copilot"
        case .glm:      return "GLM"
        case .kimi:     return "Kimi"
        case .codex:    return "Codex"
        case .settings: return "Settings"
        }
    }

    var index: Int {
        switch self {
        case .claude:   return 0
        case .copilot:  return 1
        case .glm:      return 2
        case .kimi:     return 3
        case .codex:    return 4
        case .settings: return 5
        }
    }
}

// MARK: - TabIcon

enum TabIcon {
    case system(String)
    case asset(String)
}

// MARK: - TabBarView

struct TabBarView: View {
    @Binding var selectedTab: Tab

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.claude,   icon: .asset("claude"),    label: "Claude")
            tabButton(.copilot,  icon: .asset("copilot"),   label: "Copilot")
            tabButton(.glm,      icon: .asset("glm"),       label: "GLM")
            tabButton(.kimi,     icon: .asset("kimi"),      label: "Kimi")
            tabButton(.codex,    icon: .asset("codex"),     label: "Codex")
            Spacer()
            tabButton(.settings, icon: .system("gear"),     label: nil)
        }
    }

    private func tabButton(_ tab: Tab, icon: TabIcon, label: String?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        } label: {
            HStack(spacing: 4) {
                switch icon {
                case .system(let name):
                    Image(systemName: name)
                        .font(.system(size: 11))
                case .asset(let name):
                    Image(name)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                }
                if let label = label, selectedTab == tab {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundColor(selectedTab == tab ? .white : .secondary)
            .padding(.horizontal, selectedTab == tab ? 8 : 6)
            .padding(.vertical, 5)
            .background(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.displayName) tab")
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
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

    var body: some View {
        HStack(spacing: 4) {
            if let util = claudeUtilization {
                pill(tab: .claude, theme: .claude, text: "\(util)%", utilization: util)
            }
            if let util = copilotUtilization {
                pill(tab: .copilot, theme: .copilot, text: "\(util)%", utilization: util)
            }
            if let util = glmUtilization {
                pill(tab: .glm, theme: .glm, text: "\(util)%", utilization: util)
            }
            if let balance = kimiBalance {
                pill(tab: .kimi, theme: .kimi, text: String(format: "¥%.2f", balance), utilization: balance > 0 ? 10 : 100)
            }
            if let util = codexUtilization {
                pill(tab: .codex, theme: .codex, text: "\(util)%", utilization: util)
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
                Text(text)
                    .font(.system(size: AppTypeScale.micro, weight: .bold))
                    .foregroundColor(.white)
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

// MARK: - PopoverView

struct PopoverView: View {
    @EnvironmentObject var service: UsageService
    @EnvironmentObject var copilotService: CopilotService
    @EnvironmentObject var copilotHistoryService: CopilotHistoryService
    @EnvironmentObject var glmService: GLMService
    @EnvironmentObject var kimiService: KimiService
    @EnvironmentObject var codexService: CodexService
    @EnvironmentObject var codexAuthManager: CodexAuthManager
    @EnvironmentObject var updaterManager: UpdaterManager
    @EnvironmentObject var authManager: SessionAuthManager
    @EnvironmentObject var statsService: ClaudeCodeStatsService
    @EnvironmentObject var historyService: QuotaHistoryService
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    var onRefresh: () -> Void
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @AppStorage("navigationStyle") private var navigationStyle: String = "tabbar"
    @AppStorage("hasSeenRefreshHint") private var hasSeenRefreshHint = false
    @State private var selectedTab: Tab = .claude
    @State private var previousTab: Tab = .claude
    @State private var slideDirection: Edge = .trailing
    @State private var eventMonitor: Any?

    private var useTabBar: Bool { navigationStyle == "tabbar" }

    private var configuredTimeZone: TimeZone {
        TimeZone(secondsFromGMT: timezoneOffset * 3600) ?? .current
    }

    private func switchTab(to newTab: Tab) {
        slideDirection = newTab.index > selectedTab.index ? .trailing : .leading
        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = newTab }
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
                    // Dropdown navigation
                    if selectedTab != .settings {
                        Menu {
                            Button { switchTab(to: .claude) }   label: { Label { Text("Claude") } icon: { Image("claude-small").renderingMode(.template) } }
                            Button { switchTab(to: .copilot) }  label: { Label { Text("Copilot") } icon: { Image("copilot-small").renderingMode(.template) } }
                            Button { switchTab(to: .glm) }      label: { Label { Text("GLM") } icon: { Image("glm-small").renderingMode(.template) } }
                            Button { switchTab(to: .kimi) }     label: { Label { Text("Kimi") } icon: { Image("kimi-small").renderingMode(.template) } }
                            Button { switchTab(to: .codex) }    label: { Label { Text("Codex") } icon: { Image("codex-small").renderingMode(.template) } }
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
                    }

                    // Settings icon / Back button (dropdown mode only)
                    if selectedTab == .settings {
                        Button {
                            switchTab(to: previousTab)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Back")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.button))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            previousTab = selectedTab
                            switchTab(to: .settings)
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
            }
            .padding(.bottom, useTabBar ? 4 : 12)

            // Tab bar (when enabled)
            if useTabBar {
                TabBarView(selectedTab: $selectedTab)
                    .padding(.bottom, 8)
            }

            // Summary strip — shown on all tabs except Settings
            if selectedTab != .settings {
                SummaryStripView(
                    selectedTab: $selectedTab,
                    claudeUtilization: authManager.isAuthenticated ? service.usageData.fiveHour.utilization : nil,
                    copilotUtilization: copilotService.error != .noToken ? copilotService.copilotData.premiumInteractions.utilization : nil,
                    glmUtilization: glmService.error != .noKey ? glmService.glmData.tokensPercent : nil,
                    kimiBalance: kimiService.error != .noKey ? kimiService.kimiData.totalBalance : nil,
                    codexUtilization: codexAuthManager.isAuthenticated ? codexService.codexData.primaryPercent : nil
                )
                .padding(.bottom, 6)
            }

            // Content
            Group {
                switch selectedTab {
                case .claude:
                    if !authManager.isAuthenticated {
                        signInPromptView
                    } else {
                        ClaudeTabView(service: service, statsService: statsService, timeZone: configuredTimeZone, planName: resolvedPlanName)
                    }
                case .copilot:
                    CopilotTabView(copilotService: copilotService, historyService: copilotHistoryService, timeZone: configuredTimeZone)
                case .glm:
                    GLMTabView(glmService: glmService, onKeySaved: {
                        Task { await glmService.fetch() }
                    })
                case .kimi:
                    KimiTabView(kimiService: kimiService, onKeySaved: {
                        Task { await kimiService.fetch() }
                    })
                case .codex:
                    CodexTabView(codexService: codexService, codexAuthManager: codexAuthManager, timeZone: configuredTimeZone)
                case .settings:
                    InlineSettingsView(updaterManager: updaterManager, authManager: authManager, codexAuthManager: codexAuthManager, selectedTab: $selectedTab)
                }
            }
            .id(selectedTab)
            .transition(.push(from: slideDirection))
            .animation(.easeInOut(duration: 0.2), value: selectedTab)

            Spacer(minLength: 0)
            Divider().background(Color.gray.opacity(0.3))

            // Footer — hidden on Settings tab, auto-refreshes every 30s
            if selectedTab != .settings {
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
        .padding(20)
        .frame(width: 360)
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Escape — return from Settings to previous tab
                if event.keyCode == 53 {
                    if selectedTab == .settings {
                        switchTab(to: previousTab)
                        return nil
                    }
                }

                // Arrow keys — navigate between provider tabs (no modifier needed)
                if event.keyCode == 123 { // left arrow
                    let tabs: [Tab] = [.claude, .copilot, .glm, .kimi, .codex]
                    if let idx = tabs.firstIndex(of: selectedTab), idx > 0 {
                        switchTab(to: tabs[idx - 1])
                    }
                    return nil
                }
                if event.keyCode == 124 { // right arrow
                    let tabs: [Tab] = [.claude, .copilot, .glm, .kimi, .codex]
                    if let idx = tabs.firstIndex(of: selectedTab), idx < tabs.count - 1 {
                        switchTab(to: tabs[idx + 1])
                    }
                    return nil
                }

                guard event.modifierFlags.contains(.command) else { return event }
                switch event.charactersIgnoringModifiers {
                case "r":
                    onRefresh()
                    return nil
                case "1":
                    switchTab(to: .claude)
                    return nil
                case "2":
                    switchTab(to: .copilot)
                    return nil
                case "3":
                    switchTab(to: .glm)
                    return nil
                case "4":
                    switchTab(to: .kimi)
                    return nil
                case "5":
                    switchTab(to: .codex)
                    return nil
                case "6":
                    previousTab = selectedTab
                    switchTab(to: .settings)
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
            default: break
            }
        }
    }

    /// Plan name from login (rate_limit_tier) or API (seat_tier)
    private var resolvedPlanName: String? {
        if let plan = authManager.planName { return plan }
        if let plan = service.usageData.planName { return plan }
        return nil
    }

    private var isStale: Bool {
        switch selectedTab {
        case .claude: return service.isStale
        case .copilot: return copilotService.isStale
        case .glm: return glmService.isStale
        case .kimi: return kimiService.isStale
        case .codex: return codexService.isStale
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
        case .settings: return ""
        }
        if fetchedAt == .distantPast { return "" }
        let seconds = Int(Date().timeIntervalSince(fetchedAt))
        if seconds < 60 { return "Updated just now" }
        return "Updated \(seconds / 60)m ago"
    }

    private var signInPromptView: some View {
        VStack(spacing: 12) {
            Image("claude")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundColor(.secondary.opacity(0.5))
            Text("Not signed in")
                .font(.headline)
                .foregroundColor(.white)
            Text("Monitor your Claude usage in real time")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button {
                authManager.openLoginWindow()
            } label: {
                Text("Sign in with Claude")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
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
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
