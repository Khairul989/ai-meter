import SwiftUI

// MARK: - Tab

enum Tab {
    case claude, copilot, glm, kimi, settings

    var displayName: String {
        switch self {
        case .claude:   return "Claude"
        case .copilot:  return "Copilot"
        case .glm:      return "GLM"
        case .kimi:     return "Kimi"
        case .settings: return "Settings"
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
            tabButton(.glm,      icon: .system("z.square"), label: "GLM")
            tabButton(.kimi,     icon: .system("k.square"), label: "Kimi")
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
                if let label = label {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundColor(selectedTab == tab ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PopoverView

struct PopoverView: View {
    @EnvironmentObject var service: UsageService
    @EnvironmentObject var copilotService: CopilotService
    @EnvironmentObject var copilotHistoryService: CopilotHistoryService
    @EnvironmentObject var glmService: GLMService
    @EnvironmentObject var kimiService: KimiService
    @EnvironmentObject var updaterManager: UpdaterManager
    @EnvironmentObject var authManager: SessionAuthManager
    @EnvironmentObject var statsService: ClaudeCodeStatsService
    var onRefresh: () -> Void
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @AppStorage("navigationStyle") private var navigationStyle: String = "tabbar"
    @State private var selectedTab: Tab = .claude
    @State private var previousTab: Tab = .claude
    @State private var eventMonitor: Any?

    private var useTabBar: Bool { navigationStyle == "tabbar" }

    private var configuredTimeZone: TimeZone {
        TimeZone(secondsFromGMT: timezoneOffset * 3600) ?? .current
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
                            Button { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .claude } }   label: { Label { Text("Claude") } icon: { Image("claude-small").renderingMode(.template) } }
                            Button { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .copilot } }  label: { Label { Text("Copilot") } icon: { Image("copilot-small").renderingMode(.template) } }
                            Button { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .glm } }      label: { Label("GLM",     systemImage: "z.square") }
                            Button { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .kimi } }     label: { Label("Kimi",    systemImage: "k.square") }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedTab.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    // Settings icon / Back button (dropdown mode only)
                    if selectedTab == .settings {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = previousTab }
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
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            previousTab = selectedTab
                            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .settings }
                        } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .padding(6)
                                .background(Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, useTabBar ? 4 : 12)

            // Tab bar (when enabled)
            if useTabBar {
                TabBarView(selectedTab: $selectedTab)
                    .padding(.bottom, 8)
            }

            // Content
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
            case .settings:
                InlineSettingsView(updaterManager: updaterManager, authManager: authManager, selectedTab: $selectedTab)
            }

            Spacer(minLength: 0)
            Divider().background(Color.gray.opacity(0.3))

            // Footer — hidden on Settings tab, auto-refreshes every 30s
            if selectedTab != .settings {
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
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.modifierFlags.contains(.command) else { return event }
                switch event.charactersIgnoringModifiers {
                case "r":
                    onRefresh()
                    return nil
                case "1":
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .claude }
                    return nil
                case "2":
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .copilot }
                    return nil
                case "3":
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .glm }
                    return nil
                case "4":
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = .kimi }
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
        case .settings: return ""
        }
        if fetchedAt == .distantPast { return "" }
        let seconds = Int(Date().timeIntervalSince(fetchedAt))
        if seconds < 60 { return "Updated less than a minute ago" }
        return "Updated \(seconds / 60)m ago"
    }

    private var signInPromptView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("Not signed in")
                .font(.headline)
                .foregroundColor(.white)
            Text("Sign in to view your Claude usage")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button("Sign in with Claude") {
                authManager.openLoginWindow()
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
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
