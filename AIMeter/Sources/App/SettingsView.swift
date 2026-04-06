import SwiftUI
import AppKit
import ServiceManagement

// MARK: - SettingsSection

enum SettingsSection: String, CaseIterable {
    case accounts = "Accounts"
    case display = "Display"
    case notifications = "Notifications"
    case shortcuts = "Shortcuts"
    case general = "General"
    #if DEBUG
    case developer = "Developer"
    #endif

    var icon: String {
        switch self {
        case .accounts:      return "person.2"
        case .display:       return "paintbrush"
        case .notifications: return "bell"
        case .shortcuts:     return "keyboard"
        case .general:       return "gear"
        #if DEBUG
        case .developer:     return "hammer"
        #endif
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject var updaterManager: UpdaterManager
    @ObservedObject var authManager: SessionAuthManager
    @ObservedObject var codexAuthManager: CodexAuthManager
    @ObservedObject var glmAuthManager: APIKeyAuthManager
    @ObservedObject var kimiAuthManager: APIKeyAuthManager
    @ObservedObject var minimaxAuthManager: APIKeyAuthManager
    @ObservedObject var historyService: QuotaHistoryService
    @ObservedObject var copilotHistoryService: CopilotHistoryService

    @State private var selectedSection: SettingsSection = .accounts

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
                .background(Color.white.opacity(0.1))
            ScrollView(.vertical, showsIndicators: true) {
                contentForSection(selectedSection)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 500)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases, id: \.rawValue) { section in
                sidebarItem(section)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 160)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.03))
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .frame(width: 18, alignment: .center)
                Text(section.rawValue)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(selectedSection == section ? Color.white.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .foregroundColor(selectedSection == section ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.rawValue) settings")
        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
    }

    // MARK: - Content Router

    @ViewBuilder
    private func contentForSection(_ section: SettingsSection) -> some View {
        switch section {
        case .accounts:
            AccountsSettingsSection(
                authManager: authManager,
                codexAuthManager: codexAuthManager,
                glmAuthManager: glmAuthManager,
                kimiAuthManager: kimiAuthManager,
                minimaxAuthManager: minimaxAuthManager
            )
        case .display:
            DisplaySettingsSection()
        case .notifications:
            NotificationsSettingsSection()
        case .shortcuts:
            ShortcutsSettingsSection()
        case .general:
            GeneralSettingsSection(updaterManager: updaterManager, historyService: historyService, copilotHistoryService: copilotHistoryService)
        #if DEBUG
        case .developer:
            DeveloperSettingsSection(historyService: historyService, copilotHistoryService: copilotHistoryService)
        #endif
        }
    }
}

// MARK: - AccountsSettingsSection

struct AccountsSettingsSection: View {
    @ObservedObject var authManager: SessionAuthManager
    @ObservedObject var codexAuthManager: CodexAuthManager
    @ObservedObject var glmAuthManager: APIKeyAuthManager
    @ObservedObject var kimiAuthManager: APIKeyAuthManager
    @ObservedObject var minimaxAuthManager: APIKeyAuthManager

    @AppStorage("hidePersonalInfo") private var hidePersonalInfo: Bool = false

    @State private var showSignOutConfirmation = false
    @State private var signOutTargetAccountId: String?
    @State private var showCodexSignOutConfirmation = false
    @State private var codexSignOutTargetAccountId: String?
    @State private var glmLabelInput = ""
    @State private var glmKeyInput = ""
    @State private var kimiLabelInput = ""
    @State private var kimiKeyInput = ""
    @State private var minimaxLabelInput = ""
    @State private var minimaxKeyInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsSectionCard {
                Toggle("Hide personal information", isOn: $hidePersonalInfo)
                    .font(.system(size: 12))
            }

            claudeCard
            glmCard
            kimiCard
            minimaxCard
            codexCard
            copilotCard
        }
    }

    private var claudeCard: some View {
        settingsSectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Claude")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                ForEach(authManager.accounts) { account in
                    HStack {
                        Image(systemName: account.id == authManager.activeAccountId ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(account.id == authManager.activeAccountId ? .green : .secondary)
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Signed in")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            Text(PersonalInfoRedactor.conditionalRedact(account.organizationName, hideInfo: hidePersonalInfo) ?? account.id)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if authManager.accounts.count > 1 && account.id != authManager.activeAccountId {
                            Button("Switch") {
                                authManager.setActiveAccount(account.id)
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                        Button("Sign Out") {
                            signOutTargetAccountId = account.id
                            showSignOutConfirmation = true
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }

                Button {
                    authManager.openLoginWindow()
                } label: {
                    Label("Add Account", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(authManager.isLoggingIn)

                if let error = authManager.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }
        }
        .confirmationDialog("Sign out of Claude?", isPresented: $showSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                if let id = signOutTargetAccountId {
                    authManager.signOut(accountId: id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to view usage data.")
        }
    }

    private func apiKeyCard(
        title: String,
        authManager: APIKeyAuthManager,
        envVarName: String,
        isEnvKey: Bool,
        labelInput: Binding<String>,
        keyInput: Binding<String>
    ) -> some View {
        settingsSectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                if isEnvKey {
                    Text("Using \(envVarName) from environment")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .italic()
                }

                ForEach(authManager.accounts) { account in
                    HStack {
                        Image(systemName: account.id == authManager.activeAccountId ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(account.id == authManager.activeAccountId ? .green : .secondary)
                            .font(.system(size: 12))
                        Text(account.label)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Text("••••••••")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        if authManager.accounts.count > 1 && account.id != authManager.activeAccountId {
                            Button("Switch") {
                                authManager.setActiveAccount(account.id)
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                        Button("Remove") {
                            authManager.removeAccount(id: account.id)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }

                if !isEnvKey {
                    HStack(spacing: 6) {
                        TextField("Label", text: labelInput)
                            .font(.system(size: 11))
                            .textFieldStyle(.plain)
                            .frame(width: 80)
                        SecureField("Paste API key…", text: keyInput)
                            .font(.system(size: 12))
                            .textFieldStyle(.plain)
                        if !keyInput.wrappedValue.isEmpty {
                            Button("Save") {
                                let label = labelInput.wrappedValue.isEmpty ? "Default" : labelInput.wrappedValue
                                authManager.addAccount(label: label, apiKey: keyInput.wrappedValue)
                                labelInput.wrappedValue = ""
                                keyInput.wrappedValue = ""
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var glmCard: some View {
        apiKeyCard(
            title: "GLM API Key",
            authManager: glmAuthManager,
            envVarName: "GLM_API_KEY",
            isEnvKey: GLMService.keyIsFromEnvironment,
            labelInput: $glmLabelInput,
            keyInput: $glmKeyInput
        )
    }

    private var kimiCard: some View {
        apiKeyCard(
            title: "Kimi API Key",
            authManager: kimiAuthManager,
            envVarName: "KIMI_API_KEY",
            isEnvKey: KimiService.keyIsFromEnvironment,
            labelInput: $kimiLabelInput,
            keyInput: $kimiKeyInput
        )
    }

    private var minimaxCard: some View {
        apiKeyCard(
            title: "MiniMax API Key",
            authManager: minimaxAuthManager,
            envVarName: "MINIMAX_API_KEY",
            isEnvKey: MinimaxService.keyIsFromEnvironment,
            labelInput: $minimaxLabelInput,
            keyInput: $minimaxKeyInput
        )
    }

    private var codexCard: some View {
        settingsSectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Codex")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                if codexAuthManager.isLoadBalancingAvailable {
                    Text("Auto-switches to another signed-in Codex account when the preferred account is rate limited or expired.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                ForEach(codexAuthManager.accounts) { account in
                    HStack {
                        Image(systemName: account.id == codexAuthManager.activeAccountId ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(account.id == codexAuthManager.activeAccountId ? .green : .secondary)
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Signed in")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            Text(PersonalInfoRedactor.conditionalRedact(account.email, hideInfo: hidePersonalInfo) ?? account.id)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if codexAuthManager.accounts.count > 1 && account.id != codexAuthManager.activeAccountId {
                            Button("Switch") {
                                codexAuthManager.setActiveAccount(account.id)
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        }
                        Button("Sign Out") {
                            codexSignOutTargetAccountId = account.id
                            showCodexSignOutConfirmation = true
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }

                if codexAuthManager.accounts.isEmpty {
                    Button("Sign in with ChatGPT") {
                        codexAuthManager.openLoginWindow()
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .disabled(codexAuthManager.isLoggingIn)
                } else {
                    Button {
                        codexAuthManager.openLoginWindow()
                    } label: {
                        Label("Add Account", systemImage: "plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .disabled(codexAuthManager.isLoggingIn)
                }

                if let error = codexAuthManager.lastError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
            }
        }
        .confirmationDialog("Sign out of Codex?", isPresented: $showCodexSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                if let id = codexSignOutTargetAccountId {
                    codexAuthManager.signOut(accountId: id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to view Codex usage data.")
        }
    }

    private var copilotCard: some View {
        settingsSectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Copilot")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text("Managed by GitHub CLI")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

// MARK: - DisplaySettingsSection

struct DisplaySettingsSection: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @AppStorage("menuBarProvider") private var menuBarProvider: String = MenuBarProvider.claude.rawValue
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayMode: String = MenuBarDisplayMode.classic.rawValue
    @AppStorage("navigationStyle") private var navigationStyle: String = "tabbar"
    @AppStorage("colorThresholdElevated") private var colorElevated: Int = 50
    @AppStorage("colorThresholdHigh") private var colorHigh: Int = 80
    @AppStorage("colorThresholdCritical") private var colorCritical: Int = 95
    @AppStorage("perProviderRefresh") private var perProviderRefresh: Bool = false
    @AppStorage("refreshClaude") private var refreshClaude: Double = 60
    @AppStorage("refreshCopilot") private var refreshCopilot: Double = 60
    @AppStorage("refreshGLM") private var refreshGLM: Double = 120
    @AppStorage("refreshKimi") private var refreshKimi: Double = 300
    @AppStorage("refreshCodex") private var refreshCodex: Double = 300
    @AppStorage("providerTabOrder") private var providerTabOrder: String = Tab.defaultOrderString
    @AppStorage("loadingPattern") private var loadingPattern: String = LoadingPattern.fade.rawValue

    private var orderedTabs: [Tab] { decodedProviderOrder(providerTabOrder) }

    var body: some View {
        settingsSectionCard {
            VStack(alignment: .leading, spacing: 8) {
                settingsRow("Navigation") {
                    Menu {
                        Button("Tab Bar") { navigationStyle = "tabbar" }
                        Button("Dropdown") { navigationStyle = "dropdown" }
                    } label: {
                        Text(navigationStyle == "tabbar" ? "Tab Bar" : "Dropdown")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                settingsRow("Menu bar") {
                    Menu {
                        ForEach(MenuBarProvider.allCases, id: \.rawValue) { provider in
                            Button(provider.displayName) { menuBarProvider = provider.rawValue }
                        }
                    } label: {
                        Text(MenuBarProvider(rawValue: menuBarProvider)?.displayName ?? menuBarProvider)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                settingsRow("Menu bar display") {
                    Menu {
                        ForEach(MenuBarDisplayMode.allCases, id: \.rawValue) { mode in
                            Button(mode.displayName) { menuBarDisplayMode = mode.rawValue }
                        }
                    } label: {
                        Text(MenuBarDisplayMode(rawValue: menuBarDisplayMode)?.displayName ?? menuBarDisplayMode)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                settingsRow("Loading animation") {
                    Menu {
                        ForEach(LoadingPattern.allCases, id: \.rawValue) { pattern in
                            Button(pattern.displayName) { loadingPattern = pattern.rawValue }
                        }
                    } label: {
                        Text(LoadingPattern(rawValue: loadingPattern)?.displayName ?? loadingPattern)
                            .font(.system(size: 12))
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
                        Text(tzOptions.first(where: { $0.value == timezoneOffset })?.label ?? "\(timezoneOffset >= 0 ? "+" : "")\(timezoneOffset)")
                            .font(.system(size: 12))
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
                        Text(refreshOptions.first(where: { $0.value == refreshInterval })?.label ?? "\(Int(refreshInterval))s")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Toggle("Per-provider intervals", isOn: $perProviderRefresh)
                    .font(.system(size: 12))

                if perProviderRefresh {
                    providerRefreshRow("Claude", value: $refreshClaude)
                    providerRefreshRow("Copilot", value: $refreshCopilot)
                    providerRefreshRow("GLM", value: $refreshGLM)
                    providerRefreshRow("Kimi", value: $refreshKimi)
                    providerRefreshRow("Codex", value: $refreshCodex)
                }

                Divider().opacity(0.3)

                Text("Color Thresholds")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                settingsRow("Normal", labelColor: .green) {
                    Menu {
                        ForEach([30, 40, 50, 60], id: \.self) { val in
                            Button("\(val)%") { colorElevated = val }
                        }
                    } label: {
                        Text("<\(colorElevated)%")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                settingsRow("Elevated", labelColor: .yellow) {
                    Menu {
                        ForEach([60, 70, 75, 80], id: \.self) { val in
                            Button("\(val)%") { colorHigh = val }
                        }
                    } label: {
                        Text("<\(colorHigh)%")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                settingsRow("High", labelColor: .orange) {
                    Menu {
                        ForEach([85, 90, 95, 98], id: \.self) { val in
                            Button("\(val)%") { colorCritical = val }
                        }
                    } label: {
                        Text("<\(colorCritical)%")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Divider().opacity(0.3)

                Text("Provider Order")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                ForEach(Array(orderedTabs.enumerated()), id: \.element) { idx, tab in
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(tab.displayName)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Spacer()
                        // Move up
                        Button {
                            moveProvider(from: idx, offset: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(idx == 0 ? .secondary.opacity(0.3) : .secondary)
                        .disabled(idx == 0)
                        .accessibilityLabel("Move \(tab.displayName) up")
                        // Move down
                        Button {
                            moveProvider(from: idx, offset: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(idx == orderedTabs.count - 1 ? .secondary.opacity(0.3) : .secondary)
                        .disabled(idx == orderedTabs.count - 1)
                        .accessibilityLabel("Move \(tab.displayName) down")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func moveProvider(from index: Int, offset: Int) {
        var tabs = orderedTabs
        let dest = index + offset
        guard dest >= 0 && dest < tabs.count else { return }
        tabs.swapAt(index, dest)
        providerTabOrder = tabs.map(\.rawValue).joined(separator: ",")
    }

    private func providerRefreshRow(_ label: String, value: Binding<Double>) -> some View {
        let options: [(String, Double)] = [("30s", 30), ("1m", 60), ("2m", 120), ("5m", 300)]
        return settingsRow("  \(label)") {
            Menu {
                ForEach(options, id: \.1) { opt in
                    Button(opt.0) { value.wrappedValue = opt.1 }
                }
            } label: {
                Text(options.first(where: { $0.1 == value.wrappedValue })?.0 ?? "\(Int(value.wrappedValue))s")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

// MARK: - NotificationsSettingsSection

struct NotificationsSettingsSection: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("notifyWarning") private var notifyWarning: Int = 80
    @AppStorage("notifyCritical") private var notifyCritical: Int = 90

    var body: some View {
        settingsSectionCard {
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
                            Text(warningOptions.first(where: { $0.value == notifyWarning })?.label ?? "\(notifyWarning)%")
                                .font(.system(size: 12))
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
                            Text(criticalOptions.first(where: { $0.value == notifyCritical })?.label ?? "\(notifyCritical)%")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    // Threshold visualization bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.green.opacity(0.3))
                                .frame(width: geo.size.width * CGFloat(notifyWarning) / 100)
                            Rectangle()
                                .fill(Color.orange.opacity(0.3))
                                .frame(width: geo.size.width * CGFloat(notifyCritical - notifyWarning) / 100)
                                .offset(x: geo.size.width * CGFloat(notifyWarning) / 100)
                            Rectangle()
                                .fill(Color.red.opacity(0.3))
                                .frame(width: geo.size.width * CGFloat(100 - notifyCritical) / 100)
                                .offset(x: geo.size.width * CGFloat(notifyCritical) / 100)
                            Rectangle()
                                .fill(Color.yellow)
                                .frame(width: 1)
                                .offset(x: geo.size.width * CGFloat(notifyWarning) / 100)
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 1)
                                .offset(x: geo.size.width * CGFloat(notifyCritical) / 100)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
                    }
                    .frame(height: 8)
                    .animation(.easeInOut(duration: 0.2), value: notifyWarning)
                    .animation(.easeInOut(duration: 0.2), value: notifyCritical)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Notification thresholds: normal below \(notifyWarning)%, warning at \(notifyWarning)%, critical at \(notifyCritical)%")
                }
            }
        }
    }
}

// MARK: - ShortcutsSettingsSection

struct ShortcutsSettingsSection: View {
    var body: some View {
        settingsSectionCard {
            VStack(alignment: .leading, spacing: 4) {
                shortcutRow("⌃⌥A", "Toggle menu bar popover")
                shortcutRow("⌘R", "Refresh all providers")
                shortcutRow("⌘1–5", "Jump to provider tab")
                shortcutRow("⌘6", "Open Settings")
                shortcutRow("⌘,", "Open Settings")
                shortcutRow("← →", "Navigate between tabs")
                shortcutRow("Esc", "Return from Settings")
                shortcutRow("⌘Q", "Quit AIMeter")
            }
        }
    }

    private func shortcutRow(_ shortcut: String, _ description: String) -> some View {
        HStack {
            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 50, alignment: .leading)
            Text(description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - GeneralSettingsSection

struct GeneralSettingsSection: View {
    @ObservedObject var updaterManager: UpdaterManager
    @ObservedObject var historyService: QuotaHistoryService
    @ObservedObject var copilotHistoryService: CopilotHistoryService

    @AppStorage("hidePersonalInfo") private var hidePersonalInfo: Bool = false
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @AppStorage("menuBarProvider") private var menuBarProvider: String = MenuBarProvider.claude.rawValue
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayMode: String = MenuBarDisplayMode.classic.rawValue
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = false
    @AppStorage("notifyWarning") private var notifyWarning: Int = 80
    @AppStorage("notifyCritical") private var notifyCritical: Int = 90
    @AppStorage("navigationStyle") private var navigationStyle: String = "tabbar"
    @AppStorage("colorThresholdElevated") private var colorElevated: Int = 50
    @AppStorage("colorThresholdHigh") private var colorHigh: Int = 80
    @AppStorage("colorThresholdCritical") private var colorCritical: Int = 95
    @AppStorage("perProviderRefresh") private var perProviderRefresh: Bool = false
    @AppStorage("refreshClaude") private var refreshClaude: Double = 60
    @AppStorage("refreshCopilot") private var refreshCopilot: Double = 60
    @AppStorage("refreshGLM") private var refreshGLM: Double = 120
    @AppStorage("refreshKimi") private var refreshKimi: Double = 300
    @AppStorage("refreshCodex") private var refreshCodex: Double = 300
    @AppStorage("providerTabOrder") private var providerTabOrder: String = Tab.defaultOrderString
    @AppStorage("checkProviderStatus") private var checkProviderStatus: Bool = true
    @AppStorage("loadingPattern") private var loadingPattern: String = LoadingPattern.fade.rawValue

    @State private var launchAtLogin = false

    var body: some View {
        settingsSectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Check provider status", isOn: $checkProviderStatus)
                    .font(.system(size: 12))

                Divider().opacity(0.3)

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

                HStack {
                    Text("Version")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider().opacity(0.3)

                Menu {
                    Button("Claude Quota History") {
                        ExportService.exportQuotaHistory(from: historyService)
                    }
                    Button("Copilot Quota History") {
                        ExportService.exportCopilotHistory(from: copilotHistoryService)
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                        Text("Export History…")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.accentColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Divider().opacity(0.3)

                Button {
                    refreshInterval = 60
                    timezoneOffset = TimeZone.current.secondsFromGMT() / 3600
                    navigationStyle = "tabbar"
                    menuBarProvider = MenuBarProvider.claude.rawValue
                    menuBarDisplayMode = MenuBarDisplayMode.classic.rawValue
                    notificationsEnabled = false
                    notifyWarning = 80
                    notifyCritical = 90
                    colorElevated = 50
                    colorHigh = 80
                    colorCritical = 95
                    perProviderRefresh = false
                    refreshClaude = 60
                    refreshCopilot = 60
                    refreshGLM = 120
                    refreshKimi = 300
                    refreshCodex = 300
                    hidePersonalInfo = false
                    providerTabOrder = Tab.defaultOrderString
                    loadingPattern = LoadingPattern.fade.rawValue
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                        Text("Reset to Defaults")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.orange)
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
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - DeveloperSettingsSection (DEBUG only)

#if DEBUG
struct DeveloperSettingsSection: View {
    @ObservedObject var historyService: QuotaHistoryService
    @ObservedObject var copilotHistoryService: CopilotHistoryService

    @State private var clearCacheConfirm = false
    @State private var resetSettingsConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // MARK: Notifications

            settingsSectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Button("Test Usage Alert") {
                        NotificationManager.shared.fireTestNotification()
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)

                    Button("Test Session Depleted") {
                        NotificationManager.shared.fireViaOsascriptPublic(
                            title: "Claude Session Depleted",
                            body: "Usage at 100% — will notify when available again."
                        )
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)

                    Button("Test Session Restored") {
                        NotificationManager.shared.fireViaOsascriptPublic(
                            title: "Claude Session Restored",
                            body: "Session quota is available again."
                        )
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)

                    Button("Test Recap Notification") {
                        NotificationManager.shared.fireRecapNotification(for: Date())
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            // MARK: Monthly Recap

            settingsSectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recap")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Button("Test Monthly Recap") {
                        let now = Date()
                        let calendar = Calendar.current
                        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                        let sampleRecap = MonthlyRecapData(
                            month: monthStart,
                            generatedAt: now,
                            claude: ClaudeRecapStats(
                                avgSessionUtilization: 0.45,
                                avgWeeklyUtilization: 0.62,
                                peakSessionUtilization: 0.88,
                                peakWeeklyUtilization: 0.75,
                                peakDate: now.addingTimeInterval(-5 * 86400),
                                dataPointCount: 720,
                                planName: "Pro"
                            ),
                            copilot: CopilotRecapStats(
                                avgChatUtilization: 0.30,
                                avgCompletionsUtilization: 0.55,
                                avgPremiumUtilization: 0.40,
                                peakChatUtilization: 0.72,
                                peakCompletionsUtilization: 0.85,
                                peakPremiumUtilization: 0.60,
                                peakDate: now.addingTimeInterval(-3 * 86400),
                                dataPointCount: 680,
                                plan: "Pro"
                            )
                        )
                        RecapWindowController.show(recap: sampleRecap)
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            // MARK: Service Status

            settingsSectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last Fetch")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    serviceStatusRow("Claude", date: SharedDefaults.load()?.fetchedAt)
                    serviceStatusRow("Copilot", date: SharedDefaults.loadCopilot()?.fetchedAt)
                    serviceStatusRow("GLM", date: SharedDefaults.loadGLM()?.fetchedAt)
                    serviceStatusRow("Kimi", date: SharedDefaults.loadKimi()?.fetchedAt)
                    serviceStatusRow("Codex", date: SharedDefaults.loadCodex()?.fetchedAt)
                }
            }

            // MARK: Actions

            settingsSectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Button {
                        NotificationCenter.default.post(name: .forceRefreshAll, object: nil)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11))
                            Text("Force Refresh All")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)

                    Button {
                        clearCacheConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Clear Cached Data")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Clear cached data?", isPresented: $clearCacheConfirm) {
                        Button("Clear", role: .destructive) {
                            let suite = UserDefaults(suiteName: SharedDefaults.suiteName)
                            suite?.removeObject(forKey: "usageData")
                            suite?.removeObject(forKey: "copilotData")
                            suite?.removeObject(forKey: "glmData")
                            suite?.removeObject(forKey: "kimiData")
                            suite?.removeObject(forKey: "codexData")
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Cached provider data will be removed. It will reload on the next refresh.")
                    }
                }
            }

            // MARK: App Info

            settingsSectionCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("App Info")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    infoRow("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                    infoRow("Bundle ID", value: Bundle.main.bundleIdentifier ?? "—")
                    infoRow("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                }
            }
        }
    }

    private func serviceStatusRow(_ name: String, date: Date?) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            if let date = date, date != .distantPast {
                Text(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
#endif

// MARK: - Shared Helpers

private func settingsSectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
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
