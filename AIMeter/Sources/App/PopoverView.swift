import SwiftUI
import ServiceManagement

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var copilotService: CopilotService
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = 0
    @State private var showSettings = false

    private var configuredTimeZone: TimeZone {
        TimeZone(secondsFromGMT: timezoneOffset * 3600) ?? .current
    }

    private var overallHighestUtilization: Int {
        var values = [service.usageData.highestUtilization]
        values.append(copilotService.copilotData.highestUtilization)
        return values.max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundColor(UsageColor.forUtilization(overallHighestUtilization))
                    .font(.system(size: 10))
                Text("AI Meter")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.bottom, 8)

            if showSettings {
                settingsPanel
            } else if let error = service.error, error == .noToken {
                noTokenView
            } else {
                claudeSection
                copilotSection
            }

            Divider().background(Color.gray.opacity(0.3))

            // Footer
            HStack {
                Text(updatedText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                if service.isStale {
                    Text("(stale)")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSettings.toggle()
                    }
                } label: {
                    Image(systemName: showSettings ? "xmark" : "gear")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private var claudeSection: some View {
        sectionHeader("Claude")

        let data = service.usageData

        UsageCardView(
            icon: "timer",
            title: "Session",
            subtitle: "5h sliding window",
            percentage: data.fiveHour.utilization,
            resetText: ResetTimeFormatter.format(data.fiveHour.resetsAt, style: .countdown, timeZone: configuredTimeZone)
        )

        UsageCardView(
            icon: "chart.bar.fill",
            title: "Weekly",
            subtitle: "Opus + Sonnet + Haiku",
            percentage: data.sevenDay.utilization,
            resetText: ResetTimeFormatter.format(data.sevenDay.resetsAt, style: .dayTime, timeZone: configuredTimeZone)
        )

        if let sonnet = data.sevenDaySonnet {
            UsageCardView(
                icon: "sparkles",
                title: "Sonnet",
                subtitle: "Dedicated limit",
                percentage: sonnet.utilization,
                resetText: ResetTimeFormatter.format(sonnet.resetsAt, style: .dayTime, timeZone: configuredTimeZone)
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

    @ViewBuilder
    private var copilotSection: some View {
        if copilotService.error == .noToken {
            connectGitHubView
        } else {
            let copilot = copilotService.copilotData
            let planLabel = copilot.plan.isEmpty ? "GitHub Copilot" : "GitHub Copilot (\(copilot.plan.capitalized))"
            sectionHeader(planLabel)

            if let resetText = ResetTimeFormatter.format(copilot.resetDate, style: .dayTime, timeZone: configuredTimeZone) {
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
        .padding(.vertical, 6)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.gray.opacity(0.4))
                .frame(height: 1)
                .frame(maxWidth: 20)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Rectangle()
                .fill(Color.gray.opacity(0.4))
                .frame(height: 1)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var settingsPanel: some View {
        InlineSettingsView()
    }

    private var noTokenView: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No token found")
                .font(.headline)
                .foregroundColor(.white)
            Text("Sign into Claude Code to get started")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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

    private var updatedText: String {
        let seconds = Int(Date().timeIntervalSince(service.usageData.fetchedAt))
        if seconds < 60 { return "Updated less than a minute ago" }
        let minutes = seconds / 60
        return "Updated \(minutes)m ago"
    }
}

struct InlineSettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = 8
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 8) {
                Text("Refresh interval")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Picker("", selection: $refreshInterval) {
                    Text("30s").tag(30.0)
                    Text("60s").tag(60.0)
                    Text("120s").tag(120.0)
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
