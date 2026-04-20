import SwiftUI
import Charts

private enum GLMTelemetryTheme {
    static let panel = Color(red: 0.11, green: 0.14, blue: 0.20)
    static let panelRaised = Color(red: 0.13, green: 0.17, blue: 0.25)
    static let heroTop = Color(red: 0.11, green: 0.24, blue: 0.42)
    static let heroBottom = Color(red: 0.08, green: 0.12, blue: 0.20)
    static let chartTop = Color(red: 0.09, green: 0.14, blue: 0.24)
    static let chartBottom = Color(red: 0.07, green: 0.10, blue: 0.18)
    static let edge = Color.white.opacity(0.08)
    static let strongEdge = Color.white.opacity(0.14)
    static let primaryText = Color.white
    static let secondaryText = Color(red: 0.74, green: 0.80, blue: 0.91)
    static let tertiaryText = Color(red: 0.52, green: 0.60, blue: 0.73)
    static let electric = Color(red: 0.41, green: 0.74, blue: 1.00)
    static let cyan = Color(red: 0.34, green: 0.91, blue: 1.00)
    static let line = Color(red: 0.56, green: 0.86, blue: 1.00)
}

private struct GLMBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(color.opacity(0.24), lineWidth: 1)
            )
    }
}

private struct GLMSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let surfaceColor: Color
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, surfaceColor: Color = GLMTelemetryTheme.panel, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.surfaceColor = surfaceColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(GLMTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(GLMTelemetryTheme.tertiaryText)
                }
            }

            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(surfaceColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(GLMTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct GLMDialGauge: View {
    let percentage: Int
    private let ringWidth: CGFloat = 10
    private let ringInset: CGFloat = 5

    var body: some View {
        ZStack {
            Circle()
                .inset(by: ringInset)
                .stroke(GLMTelemetryTheme.edge, lineWidth: ringWidth)

            UsageColor.utilizationGradient
                .mask {
                    Circle()
                        .inset(by: ringInset)
                        .trim(from: 0, to: Double(min(max(percentage, 0), 100)) / 100.0)
                        .stroke(style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

            Circle()
                .fill(Color.black.opacity(0.18))
                .padding(18)

            VStack(spacing: 3) {
                Text("Tokens")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(GLMTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.7)
                Text("\(percentage)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(GLMTelemetryTheme.primaryText)
            }
        }
        .frame(width: 112, height: 112)
    }
}

private struct GLMHeroView: View {
    let data: GLMUsageData

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Token Quota")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(GLMTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)

                Text("\(data.tokensPercent)%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(GLMTelemetryTheme.cyan)

                Text("5h sliding window")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(GLMTelemetryTheme.secondaryText)

                Text(UsageColor.levelDescription(data.tokensPercent))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(UsageColor.forUtilization(data.tokensPercent))
                    .textCase(.uppercase)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(UsageColor.forUtilization(data.tokensPercent).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GLMDialGauge(percentage: data.tokensPercent)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [GLMTelemetryTheme.heroTop, GLMTelemetryTheme.heroBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(GLMTelemetryTheme.strongEdge, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(GLMTelemetryTheme.cyan)
                .frame(width: 48, height: 3)
                .padding(.top, 1)
                .padding(.leading, 14)
        }
    }
}

private struct GLMLimitsView: View {
    let data: GLMUsageData

    var body: some View {
        GLMSectionCard(title: "Limit Bank", subtitle: "Current lane state", surfaceColor: GLMTelemetryTheme.panelRaised) {
            VStack(spacing: 8) {
                VStack(spacing: 7) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(GLMTelemetryTheme.electric.opacity(0.14))
                                .frame(width: 24, height: 24)
                            Image(systemName: "waveform.path")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(GLMTelemetryTheme.electric)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Token Lane")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(GLMTelemetryTheme.primaryText)
                            Text("5-hour utilization")
                                .font(.system(size: 9))
                                .foregroundColor(GLMTelemetryTheme.tertiaryText)
                        }

                        Spacer(minLength: 8)

                        Text("\(data.tokensPercent)%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(UsageColor.forUtilization(data.tokensPercent))
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.07))
                            UsageColor.utilizationGradient
                                .mask(alignment: .leading) {
                                    Capsule()
                                        .frame(width: max(8, geometry.size.width * CGFloat(data.tokensPercent) / 100))
                                }
                        }
                    }
                    .frame(height: 5)
                }

                Divider().overlay(Color.white.opacity(0.05))

                HStack {
                    Text("Account Tier")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GLMTelemetryTheme.primaryText)
                    Spacer()
                    GLMBadge(text: data.tier.isEmpty ? "Unknown" : data.tier, color: GLMTelemetryTheme.cyan)
                }
            }
        }
    }
}

private struct GLMRecentActivityView: View {
    let points: [(time: Date, value: Int)]

    private var filtered: [(time: Date, value: Int)] {
        let cutoff = Date().addingTimeInterval(-QuotaTimeRange.hour6.interval)
        return points.filter { $0.time >= cutoff }
    }

    private var latestValue: Int? {
        filtered.last?.value
    }

    private var peakValue: Int? {
        filtered.map(\.value).max()
    }

    var body: some View {
        GLMSectionCard(title: "Recent Activity", subtitle: "Token lane trend in the last 6 hours", surfaceColor: GLMTelemetryTheme.panel) {
            VStack(alignment: .leading, spacing: 10) {
                if filtered.isEmpty {
                    Text("No history yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(GLMTelemetryTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    chart
                    summary
                }
            }
        }
    }

    private var chart: some View {
        let values = filtered.map { Double($0.value) }
        let minValue = values.min() ?? 0
        let maxValue = max(values.max() ?? 1, minValue + 1)
        let domainMax = max(maxValue + max((maxValue - minValue) * 0.15, 8), 100)

        return Chart {
            ForEach(Array(filtered.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Usage", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [GLMTelemetryTheme.line.opacity(0.25), GLMTelemetryTheme.line.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Usage", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [GLMTelemetryTheme.cyan, GLMTelemetryTheme.electric],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: Date.now.addingTimeInterval(-QuotaTimeRange.hour6.interval)...Date.now)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.white.opacity(0.10))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisValueLabel()
                    .foregroundStyle(GLMTelemetryTheme.tertiaryText)
                    .font(.system(size: 8))
            }
        }
        .chartYScale(domain: 0...domainMax)
        .chartLegend(.hidden)
        .frame(height: 56)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [GLMTelemetryTheme.chartTop, GLMTelemetryTheme.chartBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(GLMTelemetryTheme.edge, lineWidth: 1)
        )
    }

    private var summary: some View {
        HStack(spacing: 10) {
            pill(title: "Latest", value: latestValue.map { "\($0)%" } ?? "0%")
            pill(title: "Peak", value: peakValue.map { "\($0)%" } ?? "0%")
            pill(title: "Samples", value: "\(filtered.count)")
        }
    }

    private func pill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(GLMTelemetryTheme.tertiaryText)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(GLMTelemetryTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

private struct GLMFooterView: View {
    let fetchedAt: Date
    let isStale: Bool
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text(updatedText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(GLMTelemetryTheme.tertiaryText)
                    if isStale {
                        Text("stale")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }

                Spacer()

                Button("Settings", action: onOpenSettings)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(GLMTelemetryTheme.secondaryText)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(GLMTelemetryTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Refresh (⌘R)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var updatedText: String {
        guard fetchedAt != .distantPast else { return "Waiting for first update" }
        let seconds = Int(Date().timeIntervalSince(fetchedAt))
        if seconds < 60 { return "Updated just now" }
        return "Updated \(seconds / 60)m ago"
    }
}

struct GLMTabView: View {
    @ObservedObject var glmService: GLMService
    @ObservedObject var historyService: GLMHistoryService
    @EnvironmentObject private var apiKeyAuthManagers: APIKeyAuthManagers
    var providerStatus: ProviderStatusService.StatusInfo? = nil
    var forceDemo: Bool = false
    var forceEmptyState: Bool = false
    var onKeySaved: (() -> Void)? = nil
    var onRefresh: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    private var authManager: APIKeyAuthManager { apiKeyAuthManagers.glm }

    var body: some View {
        let isDemoMode = forceDemo

        if forceEmptyState || (glmService.error == .noKey && !isDemoMode) {
            ProviderAPIKeyEmptyStateView(
                providerName: "GLM",
                iconSystemName: "waveform.path.ecg",
                iconAssetName: "glm",
                headline: "GLM control plane offline",
                subtitle: "Connect your GLM API key to track token quota telemetry in real time.",
                placeholder: "GLM_API_KEY…",
                accentColor: ProviderTheme.glm.accentColor
            ) { key in
                authManager.addAccount(label: "Default", apiKey: key)
                onKeySaved?()
            }
        } else {
            let glmData = isDemoMode ? Self.demoData : glmService.glmData
            let points = isDemoMode
                ? Self.demoHistoryPoints
                : historyService.history.dataPoints.map { (time: $0.timestamp, value: $0.tokensPercent) }

            VStack(alignment: .leading, spacing: 10) {
                header(data: glmData, isDemoMode: isDemoMode)

                if isDemoMode {
                    demoNotice
                }

                if !isDemoMode && authManager.accounts.count > 1 {
                    accountSwitcher
                }

                if !isDemoMode {
                    if case .fetchFailed = glmService.error {
                        ErrorBannerView(message: "Failed to fetch GLM data") {
                            Task { await glmService.fetch() }
                        }
                    } else if case .rateLimited = glmService.error {
                        ErrorBannerView(message: "Rate limited — retrying", retryDate: glmService.retryDate)
                    }

                    if let status = providerStatus, status.indicator != "none" {
                        ProviderStatusBannerView(status: status)
                    }
                }

                GLMHeroView(data: glmData)
                GLMLimitsView(data: glmData)
                GLMRecentActivityView(points: points)
                GLMFooterView(
                    fetchedAt: glmData.fetchedAt,
                    isStale: isDemoMode ? false : glmService.isStale,
                    onRefresh: onRefresh,
                    onOpenSettings: onOpenSettings
                )

                if isDemoMode {
                    APIKeyInputView(
                        providerName: "GLM",
                        placeholder: "GLM_API_KEY…",
                        accentColor: ProviderTheme.glm.accentColor
                    ) { key in
                        authManager.addAccount(label: "Default", apiKey: key)
                        onKeySaved?()
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func header(data: GLMUsageData, isDemoMode: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("GLM")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(GLMTelemetryTheme.primaryText)
                Text("Token Pulse")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(GLMTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)
            }

            Spacer()

            GLMBadge(
                text: isDemoMode ? "Demo" : (data.tier.isEmpty ? "Unknown" : data.tier),
                color: isDemoMode ? GLMTelemetryTheme.cyan : GLMTelemetryTheme.electric
            )
        }
    }

    private var demoNotice: some View {
        GLMSectionCard(
            title: "Demo Data",
            subtitle: "Preview mode from Developer settings",
            surfaceColor: GLMTelemetryTheme.panelRaised
        ) {
            Text("This is a visual demo of the redesigned GLM tab. Disable demo mode in Settings to return to live API data.")
                .font(.system(size: 11))
                .foregroundColor(GLMTelemetryTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountSwitcher: some View {
        HStack {
            Menu {
                ForEach(authManager.accounts) { account in
                    Button {
                        authManager.setActiveAccount(account.id)
                    } label: {
                        HStack {
                            Text(account.label)
                            if account.id == authManager.activeAccountId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(authManager.activeAccount?.label ?? "")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(GLMTelemetryTheme.secondaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(GLMTelemetryTheme.tertiaryText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()
        }
    }

    private static var demoData: GLMUsageData {
        GLMUsageData(
            tokensPercent: 64,
            tier: "Pro",
            fetchedAt: Date().addingTimeInterval(-90)
        )
    }

    private static var demoHistoryPoints: [(time: Date, value: Int)] {
        let now = Date()
        let values = [36, 40, 44, 47, 49, 52, 54, 57, 59, 62, 64, 64]

        return values.enumerated().map { index, value in
            (
                time: now.addingTimeInterval(Double(index - (values.count - 1)) * 1800),
                value: value
            )
        }
    }
}
