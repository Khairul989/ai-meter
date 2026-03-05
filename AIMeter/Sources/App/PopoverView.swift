import SwiftUI
import ServiceManagement

// MARK: - Tab

enum Tab {
    case claude, copilot, glm, settings
}

// MARK: - PopoverView

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var copilotService: CopilotService
    @ObservedObject var glmService: GLMService
    @ObservedObject var updaterManager: UpdaterManager
    @ObservedObject var authManager: SessionAuthManager
    @ObservedObject var historyService: QuotaHistoryService
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @State private var selectedTab: Tab = .claude

    private var configuredTimeZone: TimeZone {
        TimeZone(secondsFromGMT: timezoneOffset * 3600) ?? .current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Text("AI Meter")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.bottom, 4)

            // Tab bar
            TabBarView(selectedTab: $selectedTab)
                .padding(.bottom, 8)

            // Content
            switch selectedTab {
            case .claude:
                if !authManager.isAuthenticated {
                    signInPromptView
                } else {
                    ClaudeTabView(service: service, historyService: historyService, timeZone: configuredTimeZone, planName: resolvedPlanName)
                }
            case .copilot:
                CopilotTabView(copilotService: copilotService, timeZone: configuredTimeZone)
            case .glm:
                GLMTabView(glmService: glmService)
            case .settings:
                InlineSettingsView(updaterManager: updaterManager, authManager: authManager)
            }

            Spacer(minLength: 0)
            Divider().background(Color.gray.opacity(0.3))

            // Footer — hidden on Settings tab
            if selectedTab != .settings {
                HStack {
                    Text(updatedText)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if isStale {
                        Text("(stale)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    /// Plan name from login (rate_limit_tier) or API (seat_tier)
    private var resolvedPlanName: String? {
        // First: from organizations endpoint (rate_limit_tier, parsed at login)
        if let plan = authManager.planName { return plan }
        // Fallback: from overage_spend_limit API (seat_tier)
        if let plan = service.usageData.planName { return plan }
        return nil
    }

    private var isStale: Bool {
        switch selectedTab {
        case .claude: return service.isStale
        case .copilot: return copilotService.isStale
        case .glm: return glmService.isStale
        case .settings: return false
        }
    }

    private var updatedText: String {
        let fetchedAt: Date
        switch selectedTab {
        case .claude: fetchedAt = service.usageData.fetchedAt
        case .copilot: fetchedAt = copilotService.copilotData.fetchedAt
        case .glm: fetchedAt = glmService.glmData.fetchedAt
        case .settings: return ""
        }
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
            Spacer()
            tabButton(.settings, icon: .system("gear"),      label: nil)
        }
    }

    private func tabButton(_ tab: Tab, icon: TabIcon, label: String?) -> some View {
        Button {
            selectedTab = tab
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
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ClaudeTabView

struct ClaudeTabView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var historyService: QuotaHistoryService
    let timeZone: TimeZone
    var planName: String?

    var body: some View {
        let data = service.usageData
        VStack(spacing: 6) {
            // Plan badge + breakdown bar
            HStack {
                Text("Claude")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                if let plan = planName {
                    Text(plan)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                }
                Spacer()
            }

            BreakdownBarView(
                segments: breakdownSegments(from: data),
                height: 8
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)

            // Session card: live countdown ticking every second
            TimelineView(.periodic(from: .now, by: 1)) { context in
                UsageCardView(
                    icon: "timer",
                    title: "Session",
                    subtitle: "5h sliding window",
                    percentage: data.fiveHour.utilization,
                    resetText: ResetTimeFormatter.format(
                        data.fiveHour.resetsAt,
                        style: .countdown,
                        timeZone: timeZone,
                        now: context.date
                    )
                )
            }
            UsageCardView(
                icon: "chart.bar.fill",
                title: "Weekly",
                subtitle: "Opus + Sonnet + Haiku",
                percentage: data.sevenDay.utilization,
                resetText: ResetTimeFormatter.format(data.sevenDay.resetsAt, style: .dayTime, timeZone: timeZone)
            )
            if let sonnet = data.sevenDaySonnet {
                UsageCardView(
                    icon: "sparkles",
                    title: "Sonnet",
                    subtitle: "Dedicated limit",
                    percentage: sonnet.utilization,
                    resetText: ResetTimeFormatter.format(sonnet.resetsAt, style: .dayTime, timeZone: timeZone)
                )
            }
            if let credits = data.extraCredits {
                UsageCardView(
                    icon: "creditcard.fill",
                    title: "Extra Credits",
                    subtitle: String(format: "$%.2f / $%.2f", credits.used / 100, credits.limit / 100),
                    percentage: credits.utilization,
                    resetText: nil
                )
            }

            // Historical trend chart
            QuotaChartView(historyService: historyService)
        }
    }

    private func breakdownSegments(from data: UsageData) -> [(label: String, value: Int, color: Color)] {
        var segments: [(label: String, value: Int, color: Color)] = [
            ("Session", data.fiveHour.utilization, .blue),
            ("Weekly", data.sevenDay.utilization, .orange),
        ]
        if let sonnet = data.sevenDaySonnet {
            segments.append(("Sonnet", sonnet.utilization, .purple))
        }
        return segments
    }
}

// MARK: - CopilotTabView

struct CopilotTabView: View {
    @ObservedObject var copilotService: CopilotService
    let timeZone: TimeZone

    var body: some View {
        if copilotService.error == .noToken {
            connectGitHubView
        } else {
            let copilot = copilotService.copilotData
            VStack(alignment: .leading, spacing: 6) {
                if let resetText = ResetTimeFormatter.format(copilot.resetDate, style: .dayTime, timeZone: timeZone) {
                    Text("Reset \(resetText)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)
                }
                copilotQuotaRow(title: "Chat", quota: copilot.chat)
                copilotQuotaRow(title: "Completions", quota: copilot.completions)
                copilotQuotaRow(title: "Premium", quota: copilot.premiumInteractions)
            }
        }
    }

    private var connectGitHubView: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            Text("Connect GitHub CLI to see Copilot usage")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func copilotQuotaRow(title: String, quota: CopilotQuota) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            if quota.unlimited {
                Text("Unlimited")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(quota.utilization)%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(UsageColor.forUtilization(quota.utilization))
                    Text("\(quota.remaining)/\(quota.entitlement) remaining")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

// MARK: - GLMTabView

struct GLMTabView: View {
    @ObservedObject var glmService: GLMService

    var body: some View {
        if glmService.error == .noKey {
            noKeyView
        } else {
            VStack(spacing: 8) {
                UsageCardView(
                    icon: "z.square",
                    title: "5hr Token Quota",
                    subtitle: "5h sliding window",
                    percentage: glmService.glmData.tokensPercent,
                    resetText: nil
                )
                if !glmService.glmData.tier.isEmpty {
                    HStack {
                        Text("Account")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(glmService.glmData.tier.capitalized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
    }

    private var noKeyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No API key found")
                .font(.headline)
                .foregroundColor(.white)
            Text("Add your GLM_API_KEY in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - InlineSettingsView

struct InlineSettingsView: View {
    @ObservedObject var updaterManager: UpdaterManager
    @ObservedObject var authManager: SessionAuthManager
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @State private var launchAtLogin = false
    @State private var glmKeyInput: String = ""
    @State private var glmKeySaved: Bool = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("notifyWarning") private var notifyWarning: Int = 80
    @AppStorage("notifyCritical") private var notifyCritical: Int = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Claude Account")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                if authManager.isAuthenticated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Signed in")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            if let name = authManager.organizationName {
                                Text(name)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button("Sign Out") {
                            authManager.signOut()
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                } else {
                    Button("Sign in with Claude") {
                        authManager.openLoginWindow()
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .disabled(authManager.isLoggingIn)
                }

                if let error = authManager.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Refresh interval")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Picker("", selection: $refreshInterval) {
                    Text("1m").tag(60.0)
                    Text("2m").tag(120.0)
                    Text("3m").tag(180.0)
                    Text("5m").tag(300.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Timezone")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Picker("", selection: $timezoneOffset) {
                    Text("PST").tag(-8)
                    Text("EST").tag(-5)
                    Text("GMT").tag(0)
                    Text("CET").tag(1)
                    Text("MYT").tag(8)
                    Text("JST").tag(9)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                    .font(.system(size: 12))
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue {
                            NotificationManager.shared.requestPermission()
                        }
                    }

                if notificationsEnabled {
                    Text("Warning threshold")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Picker("", selection: $notifyWarning) {
                        Text("50%").tag(50)
                        Text("75%").tag(75)
                        Text("80%").tag(80)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("Critical threshold")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Picker("", selection: $notifyCritical) {
                        Text("85%").tag(85)
                        Text("90%").tag(90)
                        Text("95%").tag(95)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .font(.system(size: 12))
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }

            Button("Check for Updates...") {
                updaterManager.checkForUpdates()
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 8) {
                Text("GLM API Key")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if GLMService.keyIsFromEnvironment {
                    Text("Using GLM_API_KEY from environment")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .italic()
                } else if GLMKeychainHelper.readAPIKey() != nil && glmKeyInput.isEmpty {
                    HStack {
                        Text("••••••••")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear") {
                            GLMKeychainHelper.deleteAPIKey()
                            glmKeySaved = false
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                } else {
                    HStack {
                        SecureField("Paste API key…", text: $glmKeyInput)
                            .font(.system(size: 12))
                            .textFieldStyle(.plain)
                        if !glmKeyInput.isEmpty {
                            Button(glmKeySaved ? "Saved ✓" : "Save") {
                                GLMKeychainHelper.saveAPIKey(glmKeyInput)
                                glmKeySaved = true
                                glmKeyInput = ""
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundColor(glmKeySaved ? .green : .accentColor)
                        }
                    }
                }
            }

            Button("Quit AIMeter") {
                NSApp.terminate(nil)
            }
            .font(.system(size: 12))
            .foregroundColor(.red)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
