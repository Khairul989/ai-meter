import SwiftUI
import ServiceManagement

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

// MARK: - PopoverView

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var copilotService: CopilotService
    @ObservedObject var copilotHistoryService: CopilotHistoryService
    @ObservedObject var glmService: GLMService
    @ObservedObject var kimiService: KimiService
    @ObservedObject var updaterManager: UpdaterManager
    @ObservedObject var authManager: SessionAuthManager
    @ObservedObject var statsService: ClaudeCodeStatsService
    var onRefresh: () -> Void
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @State private var selectedTab: Tab = .claude
    @State private var previousTab: Tab = .claude
    @State private var eventMonitor: Any?

    private var configuredTimeZone: TimeZone {
        TimeZone(secondsFromGMT: timezoneOffset * 3600) ?? .current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: provider dropdown + settings gear
            HStack(alignment: .center, spacing: 8) {
                Text("AI Meter")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                // Provider dropdown — hidden on settings tab
                if selectedTab != .settings {
                    Menu {
                        Button { selectedTab = .claude }   label: { Label("Claude",  systemImage: "sparkles") }
                        Button { selectedTab = .copilot }  label: { Label("Copilot", systemImage: "chevron.left.forwardslash.chevron.right") }
                        Button { selectedTab = .glm }      label: { Label("GLM",     systemImage: "z.square") }
                        Button { selectedTab = .kimi }     label: { Label("Kimi",    systemImage: "k.square") }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedTab.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(7)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                // Settings icon / Back button
                if selectedTab == .settings {
                    Button {
                        selectedTab = previousTab
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
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        previousTab = selectedTab
                        selectedTab = .settings
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)

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
                GLMTabView(glmService: glmService)
            case .kimi:
                KimiTabView(kimiService: kimiService)
            case .settings:
                InlineSettingsView(updaterManager: updaterManager, authManager: authManager, selectedTab: $selectedTab)
            }

            Spacer(minLength: 0)
            Divider().background(Color.gray.opacity(0.3))

            // Footer — hidden on Settings tab
            if selectedTab != .settings {
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
                .padding(.top, 8)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "r" {
                    onRefresh()
                    return nil // consume the event
                }
                return event
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
        // Never fetched — provider not configured
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

// MARK: - ClaudeTabView

struct ClaudeTabView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var statsService: ClaudeCodeStatsService
    let timeZone: TimeZone
    var planName: String?

    var body: some View {
        let data = service.usageData
        VStack(spacing: 6) {
            // Plan badge
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

            // Per-model token usage from Claude Code logs
            ModelUsageView(statsService: statsService)

            // Daily trend chart
            TrendChartView(statsService: statsService)

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
        }
    }

}

// MARK: - CopilotTabView

struct CopilotTabView: View {
    @ObservedObject var copilotService: CopilotService
    @ObservedObject var historyService: CopilotHistoryService
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
                CopilotChartView(historyService: historyService)
                HStack(spacing: 4) {
                    Text("BETA")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                    Text("Trend data is experimental — accuracy may vary.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 2)
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
    @State private var keyInput: String = ""
    @State private var keySaved: Bool = false

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
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No GLM API key found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("Paste your API key below or add it in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                SecureField("GLM_API_KEY…", text: $keyInput)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(6)
                if !keyInput.isEmpty {
                    Button(keySaved ? "Saved ✓" : "Save") {
                        GLMKeychainHelper.saveAPIKey(keyInput)
                        keySaved = true
                        keyInput = ""
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(keySaved ? .green : .accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - KimiTabView

struct KimiTabView: View {
    @ObservedObject var kimiService: KimiService
    @State private var keyInput: String = ""
    @State private var keySaved: Bool = false

    var body: some View {
        if kimiService.error == .noKey {
            noKeyView
        } else {
            VStack(spacing: 8) {
                // Cash balance card
                balanceRow(
                    icon: "yensign.circle.fill",
                    title: "Cash Balance",
                    value: kimiService.kimiData.cashBalance
                )
                // Voucher balance card
                balanceRow(
                    icon: "ticket.fill",
                    title: "Voucher Balance",
                    value: kimiService.kimiData.voucherBalance
                )
                // Total
                HStack {
                    Text("Total Available")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "¥%.4f", kimiService.kimiData.totalBalance))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(kimiService.kimiData.totalBalance > 0 ? .green : .red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)

                if kimiService.error == .fetchFailed {
                    Text("Failed to fetch balance")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func balanceRow(icon: String, title: String, value: Double) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Text(String(format: "¥%.4f", value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(value > 0 ? .white : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }

    private var noKeyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No Kimi API key found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("Paste your API key below or add it in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                SecureField("KIMI_API_KEY…", text: $keyInput)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(6)
                if !keyInput.isEmpty {
                    Button(keySaved ? "Saved ✓" : "Save") {
                        KimiKeychainHelper.saveAPIKey(keyInput)
                        keySaved = true
                        keyInput = ""
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(keySaved ? .green : .accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - InlineSettingsView

struct InlineSettingsView: View {
    @ObservedObject var updaterManager: UpdaterManager
    @ObservedObject var authManager: SessionAuthManager
    @Binding var selectedTab: Tab
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @State private var launchAtLogin = false
    @State private var glmKeyInput: String = ""
    @State private var glmKeySaved: Bool = false
    @State private var kimiKeyInput: String = ""
    @State private var kimiKeySaved: Bool = false
    @AppStorage("menuBarProvider") private var menuBarProvider: String = MenuBarProvider.claude.rawValue
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("notifyWarning") private var notifyWarning: Int = 80
    @AppStorage("notifyCritical") private var notifyCritical: Int = 90

    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 10) {

                // MARK: - Accounts
                settingsSection("Accounts") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("Claude")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

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

                        Divider().opacity(0.3)

                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("GLM API Key")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

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

                        Divider().opacity(0.3)

                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("Kimi API Key")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        if KimiService.keyIsFromEnvironment {
                            Text("Using KIMI_API_KEY from environment")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .italic()
                        } else if KimiKeychainHelper.readAPIKey() != nil && kimiKeyInput.isEmpty {
                            HStack {
                                Text("••••••••")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Clear") {
                                    KimiKeychainHelper.deleteAPIKey()
                                    kimiKeySaved = false
                                }
                                .font(.system(size: 11))
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                            }
                        } else {
                            HStack {
                                SecureField("Paste API key…", text: $kimiKeyInput)
                                    .font(.system(size: 12))
                                    .textFieldStyle(.plain)
                                if !kimiKeyInput.isEmpty {
                                    Button(kimiKeySaved ? "Saved ✓" : "Save") {
                                        KimiKeychainHelper.saveAPIKey(kimiKeyInput)
                                        kimiKeySaved = true
                                        kimiKeyInput = ""
                                    }
                                    .font(.system(size: 11))
                                    .buttonStyle(.plain)
                                    .foregroundColor(kimiKeySaved ? .green : .accentColor)
                                }
                            }
                        }
                    }
                }

                // MARK: - Display
                settingsSection("Display") {
                    VStack(alignment: .leading, spacing: 8) {
                        settingsRow("Menu bar") {
                            Menu {
                                ForEach(MenuBarProvider.allCases, id: \.rawValue) { provider in
                                    Button(provider.displayName) { menuBarProvider = provider.rawValue }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(MenuBarProvider(rawValue: menuBarProvider)?.displayName ?? menuBarProvider)
                                        .font(.system(size: 12))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundColor(.white)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        settingsRow("Timezone") {
                            let tzOptions: [(label: String, value: Int)] = [
                                ("PST", -8), ("EST", -5), ("GMT", 0), ("CET", 1), ("MYT", 8), ("JST", 9)
                            ]
                            Menu {
                                ForEach(tzOptions, id: \.value) { opt in
                                    Button(opt.label) { timezoneOffset = opt.value }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(tzOptions.first(where: { $0.value == timezoneOffset })?.label ?? "\(timezoneOffset >= 0 ? "+" : "")\(timezoneOffset)")
                                        .font(.system(size: 12))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundColor(.white)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        settingsRow("Refresh") {
                            let refreshOptions: [(label: String, value: Double)] = [
                                ("1m", 60), ("2m", 120), ("3m", 180), ("5m", 300)
                            ]
                            Menu {
                                ForEach(refreshOptions, id: \.value) { opt in
                                    Button(opt.label) { refreshInterval = opt.value }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(refreshOptions.first(where: { $0.value == refreshInterval })?.label ?? "\(Int(refreshInterval))s")
                                        .font(.system(size: 12))
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundColor(.white)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                }

                // MARK: - Notifications
                settingsSection("Notifications") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable notifications", isOn: $notificationsEnabled)
                            .font(.system(size: 12))
                            .onChange(of: notificationsEnabled) { _, newValue in
                                if newValue {
                                    NotificationManager.shared.requestPermission()
                                }
                            }

                        if notificationsEnabled {
                            settingsRow("Warning", labelColor: .yellow) {
                                let warningOptions: [(label: String, value: Int)] = [
                                    ("50%", 50), ("75%", 75), ("80%", 80)
                                ]
                                Menu {
                                    ForEach(warningOptions, id: \.value) { opt in
                                        Button(opt.label) { notifyWarning = opt.value }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(warningOptions.first(where: { $0.value == notifyWarning })?.label ?? "\(notifyWarning)%")
                                            .font(.system(size: 12))
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }

                            settingsRow("Critical", labelColor: .red) {
                                let criticalOptions: [(label: String, value: Int)] = [
                                    ("85%", 85), ("90%", 90), ("95%", 95)
                                ]
                                Menu {
                                    ForEach(criticalOptions, id: \.value) { opt in
                                        Button(opt.label) { notifyCritical = opt.value }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(criticalOptions.first(where: { $0.value == notifyCritical })?.label ?? "\(notifyCritical)%")
                                            .font(.system(size: 12))
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                    }
                }

                // MARK: - General
                settingsSection("General") {
                    VStack(alignment: .leading, spacing: 8) {
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

                        Divider().opacity(0.3)

                        Button {
                            updaterManager.checkForUpdates()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11))
                                Text("Check for Updates...")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)

                        Divider().opacity(0.3)

                        Button {
                            NSApp.terminate(nil)
                        } label: {
                            HStack {
                                Image(systemName: "power")
                                    .font(.system(size: 11))
                                Text("Quit AIMeter")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.red)
                        }
                         .buttonStyle(.plain)
                    }
            }
          }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
        }
    }

    private func settingsRow<Content: View>(_ label: String, labelColor: Color = .secondary, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(labelColor)
            Spacer()
            content()
        }
    }
}
