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

    var subtitle: String {
        switch self {
        case .accounts: return "Identity and provider access"
        case .display: return "Layout, refresh, and visual behavior"
        case .notifications: return "Threshold alerts and signals"
        case .shortcuts: return "Keyboard navigation map"
        case .general: return "System, updates, and exports"
        #if DEBUG
        case .developer: return "Diagnostics and preview toggles"
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
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.08),
                    Color(red: 0.08, green: 0.10, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 0) {
                sidebar

                Divider()
                    .background(Color.white.opacity(0.08))

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        settingsPageHeader
                        contentForSection(selectedSection)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 760, height: 560)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)

                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Control Deck")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            Divider()
                .overlay(Color.white.opacity(0.06))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            ForEach(SettingsSection.allCases, id: \.rawValue) { section in
                sidebarItem(section)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.02))
    }

    private func sidebarItem(_ section: SettingsSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selectedSection == section ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                        .frame(width: 22, height: 22)
                    Image(systemName: section.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(selectedSection == section ? .white : .secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.rawValue)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(section.subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(selectedSection == section ? Color.white.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundColor(selectedSection == section ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.rawValue) settings")
        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
    }

    private var settingsPageHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 44, height: 44)
                Image(systemName: selectedSection.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedSection.rawValue)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(selectedSection.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add a new key")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        HStack(spacing: 8) {
                            TextField("Label (optional)", text: labelInput)
                                .font(.system(size: 11, weight: .medium))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                                .frame(width: 120)

                            SecureField("Paste API key…", text: keyInput)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                                .onSubmit {
                                    let trimmedKey = keyInput.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmedKey.isEmpty else { return }
                                    let label = labelInput.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    authManager.addAccount(label: label.isEmpty ? "Default" : label, apiKey: trimmedKey)
                                    labelInput.wrappedValue = ""
                                    keyInput.wrappedValue = ""
                                }

                            Button("Save") {
                                let trimmedKey = keyInput.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmedKey.isEmpty else { return }
                                let label = labelInput.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                authManager.addAccount(label: label.isEmpty ? "Default" : label, apiKey: trimmedKey)
                                labelInput.wrappedValue = ""
                                keyInput.wrappedValue = ""
                            }
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .buttonStyle(.plain)
                            .foregroundColor(.black.opacity(0.82))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.accentColor)
                            )
                            .disabled(keyInput.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(keyInput.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                        }

                        Text("Press Return in API key field or click Save.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
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
                    VStack(alignment: .leading, spacing: 4) {
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
                        settingsDropdownTrigger(navigationStyle == "tabbar" ? "Tab Bar" : "Dropdown")
                    }
                }

                settingsRow("Menu bar") {
                    Menu {
                        ForEach(MenuBarProvider.allCases, id: \.rawValue) { provider in
                            Button(provider.displayName) { menuBarProvider = provider.rawValue }
                        }
                    } label: {
                        settingsDropdownTrigger(MenuBarProvider(rawValue: menuBarProvider)?.displayName ?? menuBarProvider)
                    }
                }

                settingsRow("Menu bar display") {
                    Menu {
                        ForEach(MenuBarDisplayMode.allCases, id: \.rawValue) { mode in
                            Button(mode.displayName) { menuBarDisplayMode = mode.rawValue }
                        }
                    } label: {
                        settingsDropdownTrigger(MenuBarDisplayMode(rawValue: menuBarDisplayMode)?.displayName ?? menuBarDisplayMode)
                    }
                }

                settingsRow("Loading animation") {
                    Menu {
                        ForEach(LoadingPattern.allCases, id: \.rawValue) { pattern in
                            Button(pattern.displayName) { loadingPattern = pattern.rawValue }
                        }
                    } label: {
                        settingsDropdownTrigger(LoadingPattern(rawValue: loadingPattern)?.displayName ?? loadingPattern)
                    }
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
                        settingsDropdownTrigger(tzOptions.first(where: { $0.value == timezoneOffset })?.label ?? "\(timezoneOffset >= 0 ? "+" : "")\(timezoneOffset)")
                    }
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
                        settingsDropdownTrigger(refreshOptions.first(where: { $0.value == refreshInterval })?.label ?? "\(Int(refreshInterval))s")
                    }
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
                        settingsDropdownTrigger("<\(colorElevated)%", minWidth: 84)
                    }
                }

                settingsRow("Elevated", labelColor: .yellow) {
                    Menu {
                        ForEach([60, 70, 75, 80], id: \.self) { val in
                            Button("\(val)%") { colorHigh = val }
                        }
                    } label: {
                        settingsDropdownTrigger("<\(colorHigh)%", minWidth: 84)
                    }
                }

                settingsRow("High", labelColor: .orange) {
                    Menu {
                        ForEach([85, 90, 95, 98], id: \.self) { val in
                            Button("\(val)%") { colorCritical = val }
                        }
                    } label: {
                        settingsDropdownTrigger("<\(colorCritical)%", minWidth: 84)
                    }
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
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(idx == 0 ? .secondary.opacity(0.35) : .secondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(idx == 0 ? 0.03 : 0.08))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(idx == 0 ? 0.08 : 0.18), lineWidth: 1)
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(idx == 0)
                        .accessibilityLabel("Move \(tab.displayName) up")
                        // Move down
                        Button {
                            moveProvider(from: idx, offset: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(idx == orderedTabs.count - 1 ? .secondary.opacity(0.35) : .secondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(idx == orderedTabs.count - 1 ? 0.03 : 0.08))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(idx == orderedTabs.count - 1 ? 0.08 : 0.18), lineWidth: 1)
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(idx == orderedTabs.count - 1)
                        .accessibilityLabel("Move \(tab.displayName) down")
                    }
                    .padding(.vertical, 3)
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
                settingsDropdownTrigger(options.first(where: { $0.1 == value.wrappedValue })?.0 ?? "\(Int(value.wrappedValue))s", minWidth: 84)
            }
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
                            settingsDropdownTrigger(warningOptions.first(where: { $0.value == notifyWarning })?.label ?? "\(notifyWarning)%", minWidth: 84)
                        }
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
                            settingsDropdownTrigger(criticalOptions.first(where: { $0.value == notifyCritical })?.label ?? "\(notifyCritical)%", minWidth: 84)
                        }
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
                shortcutRow("⌘1–6", "Jump to provider tab")
                shortcutRow("⌘7", "Open Settings")
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
                    settingsDropdownTrigger("Export History…", systemImage: "square.and.arrow.up", minWidth: 138)
                }

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

    @AppStorage("demoUIClaude") private var demoUIClaude: Bool = false
    @AppStorage("demoUICopilot") private var demoUICopilot: Bool = false
    @AppStorage("demoUIGLM") private var demoUIGLM: Bool = false
    @AppStorage("demoUIKimi") private var demoUIKimi: Bool = false
    @AppStorage("demoUICodex") private var demoUICodex: Bool = false
    @AppStorage("demoUIMiniMax") private var demoUIMiniMax: Bool = false
    @AppStorage("forceEmptyStatesAllProviders") private var forceEmptyStatesAllProviders: Bool = false

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

            // MARK: Demo UI

            settingsSectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Demo UI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Toggle("Claude", isOn: $demoUIClaude)
                        .font(.system(size: 12))
                    Toggle("Copilot", isOn: $demoUICopilot)
                        .font(.system(size: 12))
                    Toggle("GLM", isOn: $demoUIGLM)
                        .font(.system(size: 12))
                    Toggle("Kimi", isOn: $demoUIKimi)
                        .font(.system(size: 12))
                    Toggle("Codex", isOn: $demoUICodex)
                        .font(.system(size: 12))
                    Toggle("MiniMax", isOn: $demoUIMiniMax)
                        .font(.system(size: 12))

                    Divider().opacity(0.3)

                    Toggle("Force all providers empty state", isOn: $forceEmptyStatesAllProviders)
                        .font(.system(size: 12))

                    Divider().opacity(0.3)

                    Button("Disable all demo UI") {
                        demoUIClaude = false
                        demoUICopilot = false
                        demoUIGLM = false
                        demoUIKimi = false
                        demoUICodex = false
                        demoUIMiniMax = false
                        forceEmptyStatesAllProviders = false
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(.orange)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
}

private func settingsRow<Content: View>(_ label: String, labelColor: Color = .secondary, @ViewBuilder content: () -> Content) -> some View {
    HStack {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(labelColor)
        Spacer()
        content()
    }
    .padding(.vertical, 1)
}

private func settingsDropdownTrigger(_ value: String, systemImage: String? = nil, minWidth: CGFloat = 110) -> some View {
    HStack(spacing: 7) {
        if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }

        Text(value)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .lineLimit(1)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .frame(minWidth: minWidth, alignment: .leading)
    .frame(minHeight: 34)
    .background(
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.03))
    )
    .overlay(
        Capsule(style: .continuous)
            .stroke(Color.white.opacity(0.24), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.16), radius: 1, x: 0, y: 1)
    .contentShape(Capsule(style: .continuous))
}
