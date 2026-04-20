import SwiftUI
import Charts

private enum KimiTelemetryTheme {
    static let panel = Color(red: 0.10, green: 0.15, blue: 0.16)
    static let panelRaised = Color(red: 0.12, green: 0.18, blue: 0.19)
    static let heroTop = Color(red: 0.08, green: 0.29, blue: 0.26)
    static let heroBottom = Color(red: 0.08, green: 0.13, blue: 0.16)
    static let chartTop = Color(red: 0.08, green: 0.17, blue: 0.17)
    static let chartBottom = Color(red: 0.06, green: 0.10, blue: 0.12)
    static let edge = Color.white.opacity(0.08)
    static let strongEdge = Color.white.opacity(0.14)
    static let primaryText = Color.white
    static let secondaryText = Color(red: 0.72, green: 0.85, blue: 0.82)
    static let tertiaryText = Color(red: 0.51, green: 0.68, blue: 0.65)
    static let mint = Color(red: 0.46, green: 0.93, blue: 0.74)
    static let jade = Color(red: 0.30, green: 0.83, blue: 0.69)
    static let line = Color(red: 0.56, green: 0.93, blue: 0.81)
}

private struct KimiBalanceLane: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let amount: Double
    let percentage: Int
}

private struct KimiBadge: View {
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

private struct KimiSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let surfaceColor: Color
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, surfaceColor: Color = KimiTelemetryTheme.panel, @ViewBuilder content: () -> Content) {
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
                    .foregroundColor(KimiTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(KimiTelemetryTheme.tertiaryText)
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
                .stroke(KimiTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct KimiDialGauge: View {
    let percentage: Int
    private let ringWidth: CGFloat = 10
    private let ringInset: CGFloat = 5

    var body: some View {
        ZStack {
            Circle()
                .inset(by: ringInset)
                .stroke(KimiTelemetryTheme.edge, lineWidth: ringWidth)

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
                Text("Cash")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(KimiTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.7)
                Text("\(percentage)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(KimiTelemetryTheme.primaryText)
            }
        }
        .frame(width: 120, height: 120)
    }
}

private struct KimiHeroView: View {
    let data: KimiUsageData

    private var cashPercent: Int {
        guard data.totalBalance > 0 else { return 0 }
        return Int((data.cashBalance / data.totalBalance * 100).rounded())
    }

    private var statusLine: String {
        if data.totalBalance <= 0 { return "Depleted" }
        if data.totalBalance < 5 { return "Low balance" }
        if data.totalBalance < 20 { return "Watch balance" }
        return "Healthy" }

    private var statusColor: Color {
        if data.totalBalance <= 0 { return .red }
        if data.totalBalance < 5 { return .orange }
        if data.totalBalance < 20 { return .yellow }
        return KimiTelemetryTheme.mint
    }

    private var balanceLabel: String {
        String(format: "¥%.4f", data.totalBalance)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Balance")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(KimiTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)

                Text(balanceLabel)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundColor(KimiTelemetryTheme.mint)

                Text("Cash share \(cashPercent)%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(KimiTelemetryTheme.secondaryText)
                    .lineLimit(1)

                Text(statusLine)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(statusColor)
                    .textCase(.uppercase)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            KimiDialGauge(percentage: cashPercent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [KimiTelemetryTheme.heroTop, KimiTelemetryTheme.heroBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KimiTelemetryTheme.strongEdge, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(KimiTelemetryTheme.mint)
                .frame(width: 48, height: 3)
                .padding(.top, 1)
                .padding(.leading, 14)
        }
    }
}

private struct KimiLanesView: View {
    let rows: [KimiBalanceLane]

    var body: some View {
        KimiSectionCard(title: "Balance Lanes", subtitle: "Cash and voucher composition", surfaceColor: KimiTelemetryTheme.panelRaised) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    laneRow(row)
                    if index < rows.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.05))
                    }
                }
            }
        }
    }

    private func laneRow(_ row: KimiBalanceLane) -> some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(KimiTelemetryTheme.mint.opacity(0.14))
                        .frame(width: 24, height: 24)
                    Image(systemName: row.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(KimiTelemetryTheme.mint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(KimiTelemetryTheme.primaryText)
                    Text(row.subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(KimiTelemetryTheme.tertiaryText)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "¥%.4f", row.amount))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(KimiTelemetryTheme.primaryText)
                    Text("\(row.percentage)%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(KimiTelemetryTheme.secondaryText)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    LinearGradient(
                        colors: [KimiTelemetryTheme.jade, KimiTelemetryTheme.mint],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .mask(alignment: .leading) {
                        Capsule()
                            .frame(width: max(8, geometry.size.width * CGFloat(row.percentage) / 100))
                    }
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 7)
    }
}

private struct KimiRecentActivityView: View {
    let dataPoints: [(time: Date, value: Double)]

    private var filteredPoints: [(time: Date, value: Double)] {
        let cutoff = Date().addingTimeInterval(-QuotaTimeRange.day1.interval)
        return dataPoints.filter { $0.time >= cutoff }
    }

    private var plottedPoints: [(time: Date, value: Double)] {
        filteredPoints
    }

    private var latestValue: Double? {
        plottedPoints.last?.value
    }

    private var peakValue: Double? {
        plottedPoints.map(\.value).max()
    }

    private var changeValue: Double {
        guard let first = plottedPoints.first?.value, let last = plottedPoints.last?.value else { return 0 }
        return last - first
    }

    var body: some View {
        KimiSectionCard(title: "Recent Activity", subtitle: "Wallet movement in the last 24 hours", surfaceColor: KimiTelemetryTheme.panel) {
            VStack(alignment: .leading, spacing: 10) {
                if plottedPoints.isEmpty {
                    Text("No history yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(KimiTelemetryTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    chart
                    summaryRail
                }
            }
        }
    }

    private var chart: some View {
        let values = plottedPoints.map(\.value)
        let minValue = values.min() ?? 0
        let maxValue = max(values.max() ?? 1, minValue + 0.1)
        let domainMax = max(maxValue + max((maxValue - minValue) * 0.15, 0.5), 1)

        return Chart {
            ForEach(Array(plottedPoints.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Balance", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [KimiTelemetryTheme.line.opacity(0.25), KimiTelemetryTheme.line.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", point.time),
                    y: .value("Balance", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [KimiTelemetryTheme.mint, KimiTelemetryTheme.jade],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: Date.now.addingTimeInterval(-QuotaTimeRange.day1.interval)...Date.now)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.white.opacity(0.10))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisValueLabel()
                    .foregroundStyle(KimiTelemetryTheme.tertiaryText)
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
                        colors: [KimiTelemetryTheme.chartTop, KimiTelemetryTheme.chartBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(KimiTelemetryTheme.edge, lineWidth: 1)
        )
    }

    private var summaryRail: some View {
        HStack(spacing: 10) {
            metricPill(title: "Latest", value: latestValue.map { String(format: "¥%.2f", $0) } ?? "¥0.00")
            metricPill(title: "Peak", value: peakValue.map { String(format: "¥%.2f", $0) } ?? "¥0.00")
            metricPill(title: "Change", value: String(format: "%@¥%.2f", changeValue >= 0 ? "+" : "", changeValue))
        }
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(KimiTelemetryTheme.tertiaryText)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(KimiTelemetryTheme.primaryText)
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

private struct KimiFooterView: View {
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
                        .foregroundColor(KimiTelemetryTheme.tertiaryText)
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
                    .foregroundColor(KimiTelemetryTheme.secondaryText)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(KimiTelemetryTheme.secondaryText)
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

struct KimiTabView: View {
    @ObservedObject var kimiService: KimiService
    @ObservedObject var historyService: KimiHistoryService
    @EnvironmentObject private var apiKeyAuthManagers: APIKeyAuthManagers
    var providerStatus: ProviderStatusService.StatusInfo? = nil
    var forceDemo: Bool = false
    var forceEmptyState: Bool = false
    var onKeySaved: (() -> Void)? = nil
    var onRefresh: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    private var authManager: APIKeyAuthManager { apiKeyAuthManagers.kimi }

    var body: some View {
        let isDemoMode = forceDemo

        if forceEmptyState || (kimiService.error == .noKey && !isDemoMode) {
            ProviderAPIKeyEmptyStateView(
                providerName: "Kimi",
                iconSystemName: "creditcard.circle",
                iconAssetName: "kimi",
                headline: "Kimi wallet telemetry offline",
                subtitle: "Connect your Kimi API key to monitor cash and voucher balance telemetry.",
                placeholder: "KIMI_API_KEY…",
                accentColor: ProviderTheme.kimi.accentColor
            ) { key in
                authManager.addAccount(label: "Default", apiKey: key)
                onKeySaved?()
            }
        } else {
            let kimiData = isDemoMode ? Self.demoData : kimiService.kimiData
            let timeline = isDemoMode
                ? Self.demoHistoryDataPoints
                : historyService.history.dataPoints.map { (time: $0.timestamp, value: $0.totalBalance) }

            VStack(alignment: .leading, spacing: 10) {
                header(data: kimiData, isDemoMode: isDemoMode)

                if isDemoMode {
                    demoNotice
                }

                if !isDemoMode && authManager.accounts.count > 1 {
                    accountSwitcher
                }

                if !isDemoMode {
                    if case .fetchFailed = kimiService.error {
                        ErrorBannerView(message: "Failed to fetch balance") {
                            Task { await kimiService.fetch() }
                        }
                    } else if case .rateLimited = kimiService.error {
                        ErrorBannerView(message: "Rate limited — retrying", retryDate: kimiService.retryDate)
                    }

                    if let status = providerStatus, status.indicator != "none" {
                        ProviderStatusBannerView(status: status)
                    }
                }

                KimiHeroView(data: kimiData)
                KimiLanesView(rows: lanes(from: kimiData))
                KimiRecentActivityView(dataPoints: timeline)
                KimiFooterView(
                    fetchedAt: kimiData.fetchedAt,
                    isStale: isDemoMode ? false : kimiService.isStale,
                    onRefresh: onRefresh,
                    onOpenSettings: onOpenSettings
                )

                if isDemoMode {
                    APIKeyInputView(
                        providerName: "Kimi",
                        placeholder: "KIMI_API_KEY…",
                        accentColor: ProviderTheme.kimi.accentColor
                    ) { key in
                        authManager.addAccount(label: "Default", apiKey: key)
                        onKeySaved?()
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func header(data: KimiUsageData, isDemoMode: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kimi")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(KimiTelemetryTheme.primaryText)
                Text("Wallet Pulse")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(KimiTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)
            }

            Spacer()

            KimiBadge(
                text: isDemoMode ? "Demo" : (data.totalBalance > 0 ? "Active" : "Empty"),
                color: isDemoMode ? KimiTelemetryTheme.jade : (data.totalBalance > 0 ? KimiTelemetryTheme.mint : .orange)
            )
        }
    }

    private var demoNotice: some View {
        KimiSectionCard(
            title: "Demo Data",
            subtitle: "Preview mode from Developer settings",
            surfaceColor: KimiTelemetryTheme.panelRaised
        ) {
            Text("This is a visual demo of the redesigned Kimi tab. Disable demo mode in Settings to return to live data.")
                .font(.system(size: 11))
                .foregroundColor(KimiTelemetryTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lanes(from data: KimiUsageData) -> [KimiBalanceLane] {
        let total = max(data.totalBalance, 0)
        let cashPercent = total > 0 ? Int((data.cashBalance / total * 100).rounded()) : 0
        let voucherPercent = total > 0 ? Int((data.voucherBalance / total * 100).rounded()) : 0

        return [
            KimiBalanceLane(
                id: "cash",
                icon: "yensign.circle.fill",
                title: "Cash",
                subtitle: "Spendable wallet balance",
                amount: data.cashBalance,
                percentage: cashPercent
            ),
            KimiBalanceLane(
                id: "voucher",
                icon: "ticket.fill",
                title: "Voucher",
                subtitle: "Promotional credits",
                amount: data.voucherBalance,
                percentage: voucherPercent
            )
        ]
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
                        .foregroundColor(KimiTelemetryTheme.secondaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(KimiTelemetryTheme.tertiaryText)
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

    private static var demoData: KimiUsageData {
        KimiUsageData(
            cashBalance: 24.8750,
            voucherBalance: 11.4200,
            totalBalance: 36.2950,
            fetchedAt: Date().addingTimeInterval(-120)
        )
    }

    private static var demoHistoryDataPoints: [(time: Date, value: Double)] {
        let now = Date()
        let values: [Double] = [31.8, 31.2, 30.9, 30.4, 30.0, 29.7, 29.2, 28.8, 28.5, 28.1, 27.6, 27.2, 26.9, 26.3, 25.8, 25.2, 24.9, 24.6, 24.2, 23.9, 23.5, 23.0, 22.6, 22.3]

        return values.enumerated().map { index, value in
            (
                time: now.addingTimeInterval(Double(index - (values.count - 1)) * 3600),
                value: value
            )
        }
    }

}
