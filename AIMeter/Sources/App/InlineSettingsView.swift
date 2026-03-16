import SwiftUI
import ServiceManagement

struct InlineSettingsView: View {
    @ObservedObject var updaterManager: UpdaterManager
    @ObservedObject var authManager: SessionAuthManager
    @ObservedObject var codexAuthManager: CodexAuthManager
    @Binding var selectedTab: Tab
    @EnvironmentObject var historyService: QuotaHistoryService
    @EnvironmentObject var copilotHistoryService: CopilotHistoryService
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = TimeZone.current.secondsFromGMT() / 3600
    @State private var launchAtLogin = false
    @State private var showSignOutConfirmation = false
    @State private var glmKeyInput: String = ""
    @State private var glmKeySaved: Bool = false
    @State private var kimiKeyInput: String = ""
    @State private var kimiKeySaved: Bool = false
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
    @State private var showCodexSignOutConfirmation = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 10) {

                // MARK: - Accounts
                settingsSection("Accounts", icon: "person.2") {
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
                                    if let email = codexAuthManager.email {
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

                // MARK: - Display
                settingsSection("Display", icon: "paintbrush") {
                    VStack(alignment: .leading, spacing: 8) {
                        settingsRow("Navigation") {
                            Menu {
                                Button("Tab Bar") { navigationStyle = "tabbar" }
                                Button("Dropdown") { navigationStyle = "dropdown" }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(navigationStyle == "tabbar" ? "Tab Bar" : "Dropdown")
                                        .font(.system(size: 12))
                                }
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
                                HStack(spacing: 4) {
                                    Text(MenuBarProvider(rawValue: menuBarProvider)?.displayName ?? menuBarProvider)
                                        .font(.system(size: 12))
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
                                }
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

                // MARK: - Notifications
                settingsSection("Notifications", icon: "bell") {
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
                                    }
                                    .foregroundColor(.white)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }

                            // Threshold visualization bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    // Green zone
                                    Rectangle()
                                        .fill(Color.green.opacity(0.3))
                                        .frame(width: geo.size.width * CGFloat(notifyWarning) / 100)
                                    // Yellow/Orange zone
                                    Rectangle()
                                        .fill(Color.orange.opacity(0.3))
                                        .frame(width: geo.size.width * CGFloat(notifyCritical - notifyWarning) / 100)
                                        .offset(x: geo.size.width * CGFloat(notifyWarning) / 100)
                                    // Red zone
                                    Rectangle()
                                        .fill(Color.red.opacity(0.3))
                                        .frame(width: geo.size.width * CGFloat(100 - notifyCritical) / 100)
                                        .offset(x: geo.size.width * CGFloat(notifyCritical) / 100)
                                    // Warning marker
                                    Rectangle()
                                        .fill(Color.yellow)
                                        .frame(width: 1)
                                        .offset(x: geo.size.width * CGFloat(notifyWarning) / 100)
                                    // Critical marker
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

                // MARK: - Shortcuts
                settingsSection("Shortcuts", icon: "keyboard") {
                    VStack(alignment: .leading, spacing: 4) {
                        shortcutRow("⌘R", "Refresh all providers")
                        shortcutRow("⌘1–5", "Jump to provider tab")
                        shortcutRow("⌘6", "Open Settings")
                        shortcutRow("← →", "Navigate between tabs")
                        shortcutRow("Esc", "Return from Settings")
                        shortcutRow("⌘Q", "Quit AIMeter")
                    }
                }

                // MARK: - General
                settingsSection("General", icon: "gear") {
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
        }
        }
        .frame(maxHeight: 500)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
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

    // MARK: - Helpers

    private func settingsSection<Content: View>(_ title: String, icon: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
            }
            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
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
