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
    }

    // MARK: - Content Router

    @ViewBuilder
    private func contentForSection(_ section: SettingsSection) -> some View {
        switch section {
        case .accounts:
            AccountsSettingsSection(authManager: authManager, codexAuthManager: codexAuthManager)
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

    @AppStorage("hidePersonalInfo") private var hidePersonalInfo: Bool = false

    @State private var showSignOutConfirmation = false
    @State private var glmKeyInput: String = ""
    @State private var glmKeySaved: Bool = false
    @State private var kimiKeyInput: String = ""
    @State private var kimiKeySaved: Bool = false
    @State private var showCodexSignOutConfirmation = false

    var body: some View {
        settingsSectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Hide personal information", isOn: $hidePersonalInfo)
                    .font(.system(size: 12))

                Divider().opacity(0.3)

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
                            if let name = PersonalInfoRedactor.conditionalRedact(authManager.organizationName, hideInfo: hidePersonalInfo) {
                                Text(name)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button("Sign Out") {
                            showSignOutConfirmation = true
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
                } else if APIKeyKeychainHelper.glm.readAPIKey() != nil && glmKeyInput.isEmpty {
                    HStack {
                        Text("••••••••")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear") {
                            APIKeyKeychainHelper.glm.deleteAPIKey()
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
                                APIKeyKeychainHelper.glm.saveAPIKey(glmKeyInput)
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
                } else if APIKeyKeychainHelper.kimi.readAPIKey() != nil && kimiKeyInput.isEmpty {
                    HStack {
                        Text("••••••••")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear") {
                            APIKeyKeychainHelper.kimi.deleteAPIKey()
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
                                APIKeyKeychainHelper.kimi.saveAPIKey(kimiKeyInput)
                                kimiKeySaved = true
                                kimiKeyInput = ""
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundColor(kimiKeySaved ? .green : .accentColor)
                        }
                    }
                }

                Divider().opacity(0.3)

                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("Codex")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                if codexAuthManager.isAuthenticated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Signed in")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                            if let email = PersonalInfoRedactor.conditionalRedact(codexAuthManager.email, hideInfo: hidePersonalInfo) {
                                Text(email)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button("Sign Out") {
                            showCodexSignOutConfirmation = true
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                } else {
                    Button("Sign in with ChatGPT") {
                        codexAuthManager.openLoginWindow()
                    }
                    .font(.system(size: 12))
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
        .confirmationDialog("Sign out of Claude?", isPresented: $showSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to view usage data.")
        }
        .confirmationDialog("Sign out of Codex?", isPresented: $showCodexSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                codexAuthManager.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to view Codex usage data.")
        }
    }
}

// MARK: - DisplaySettingsSection

struct DisplaySettingsSection: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @AppStorage("menuBarProvider") private var menuBarProvider: String = MenuBarProvider.claude.rawValue
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
            }
        }
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

    @State private var launchAtLogin = false

    var body: some View {
        settingsSectionCard {
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

    var body: some View {
        settingsSectionCard {
            VStack(alignment: .leading, spacing: 8) {
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

                Button("Test Usage Alert") {
                    NotificationManager.shared.fireTestNotification()
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
