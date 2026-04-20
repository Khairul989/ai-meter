import SwiftUI
import Charts
import AppKit

private enum CopilotTelemetryTheme {
    static let panel = Color(red: 0.12, green: 0.15, blue: 0.20)
    static let panelRaised = Color(red: 0.14, green: 0.18, blue: 0.24)
    static let heroTop = Color(red: 0.10, green: 0.24, blue: 0.37)
    static let heroBottom = Color(red: 0.08, green: 0.12, blue: 0.20)
    static let chartTop = Color(red: 0.09, green: 0.14, blue: 0.22)
    static let chartBottom = Color(red: 0.07, green: 0.10, blue: 0.17)
    static let edge = Color.white.opacity(0.08)
    static let strongEdge = Color.white.opacity(0.14)
    static let primaryText = Color.white
    static let secondaryText = Color(red: 0.72, green: 0.79, blue: 0.90)
    static let tertiaryText = Color(red: 0.53, green: 0.61, blue: 0.73)
    static let azure = Color(red: 0.42, green: 0.72, blue: 1.00)
    static let electric = Color(red: 0.31, green: 0.90, blue: 1.00)
    static let line = Color(red: 0.56, green: 0.86, blue: 1.00)
}

private struct CopilotLimitRow: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let percentage: Int
    let detail: String
    let unlimited: Bool
}

private struct CopilotBadge: View {
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

private struct CopilotSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let surfaceColor: Color
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, surfaceColor: Color = CopilotTelemetryTheme.panel, @ViewBuilder content: () -> Content) {
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
                    .foregroundColor(CopilotTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(CopilotTelemetryTheme.tertiaryText)
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
                .stroke(CopilotTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct CopilotDialGauge: View {
    let percentage: Int
    private let segmentCount = 72

    private var progress: Double {
        Double(min(max(percentage, 0), 100)) / 100.0
    }

    private func color(at location: Double) -> Color {
        let stops: [(Double, NSColor)] = [
            (0.00, .systemGreen),
            (0.50, .systemYellow),
            (0.80, .systemOrange),
            (0.95, .systemRed),
            (1.00, .systemRed)
        ]

        guard let upperIndex = stops.firstIndex(where: { location <= $0.0 }) else {
            return Color(stops.last?.1 ?? .systemRed)
        }
        if upperIndex == 0 {
            return Color(stops[0].1)
        }

        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let span = max(upper.0 - lower.0, 0.001)
        let t = (location - lower.0) / span

        let lowerRGB = lower.1.usingColorSpace(.sRGB) ?? lower.1
        let upperRGB = upper.1.usingColorSpace(.sRGB) ?? upper.1

        let red = lowerRGB.redComponent + ((upperRGB.redComponent - lowerRGB.redComponent) * t)
        let green = lowerRGB.greenComponent + ((upperRGB.greenComponent - lowerRGB.greenComponent) * t)
        let blue = lowerRGB.blueComponent + ((upperRGB.blueComponent - lowerRGB.blueComponent) * t)
        let alpha = lowerRGB.alphaComponent + ((upperRGB.alphaComponent - lowerRGB.alphaComponent) * t)

        return Color(nsColor: NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(CopilotTelemetryTheme.edge, lineWidth: 10)

            ForEach(0..<segmentCount, id: \.self) { index in
                let start = Double(index) / Double(segmentCount)
                let end = Double(index + 1) / Double(segmentCount)
                let visibleEnd = min(progress, end)

                if visibleEnd > start {
                    Circle()
                        .trim(from: start, to: visibleEnd)
                        .stroke(
                            color(at: (start + visibleEnd) / 2),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }

            Circle()
                .fill(Color.black.opacity(0.18))
                .padding(14)

            VStack(spacing: 3) {
                Text("Usage")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(CopilotTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.7)
                Text("\(percentage)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(CopilotTelemetryTheme.primaryText)
            }
        }
        .frame(width: 128, height: 128)
    }
}

private struct CopilotHeroView: View {
    let data: CopilotUsageData
    let timeZone: TimeZone
    let now: Date

    private var highestPercent: Int {
        data.highestUtilization
    }

    private var resetLine: String {
        guard let resetDate = data.resetDate else {
            return "Reset unavailable"
        }
        let resetText = ResetTimeFormatter.format(resetDate, style: .dateTime, timeZone: timeZone, now: now) ?? "unknown"
        return "Reset \(resetText)"
    }

    private var statusLine: String {
        if allUnlimited {
            return "Unlimited"
        }
        return UsageColor.levelDescription(highestPercent)
    }

    private var statusColor: Color {
        allUnlimited ? CopilotTelemetryTheme.azure : UsageColor.forUtilization(highestPercent)
    }

    private var allUnlimited: Bool {
        data.chat.unlimited && data.completions.unlimited && data.premiumInteractions.unlimited
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Monthly Quota")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CopilotTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)

                Text(allUnlimited ? "Unlimited" : "\(highestPercent)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(CopilotTelemetryTheme.electric)

                Text(resetLine)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(CopilotTelemetryTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

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

            CopilotDialGauge(percentage: highestPercent)
                .scaleEffect(0.9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CopilotTelemetryTheme.heroTop, CopilotTelemetryTheme.heroBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CopilotTelemetryTheme.strongEdge, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CopilotTelemetryTheme.electric)
                .frame(width: 48, height: 3)
                .padding(.top, 1)
                .padding(.leading, 14)
        }
    }

}

private struct CopilotLimitsView: View {
    let rows: [CopilotLimitRow]

    var body: some View {
        CopilotSectionCard(title: "Limit Bank", subtitle: "Quota lanes and utilization state", surfaceColor: CopilotTelemetryTheme.panelRaised) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    limitRow(row)
                    if index < rows.count - 1 {
                        divider
                    }
                }
            }
        }
    }

    private func limitRow(_ row: CopilotLimitRow) -> some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill((row.unlimited ? CopilotTelemetryTheme.azure : UsageColor.forUtilization(row.percentage)).opacity(0.14))
                        .frame(width: 24, height: 24)
                    Image(systemName: row.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(row.unlimited ? CopilotTelemetryTheme.azure : UsageColor.forUtilization(row.percentage))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(CopilotTelemetryTheme.primaryText)
                    Text(row.subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(CopilotTelemetryTheme.tertiaryText)
                }

                Spacer(minLength: 8)

                if row.unlimited {
                    CopilotBadge(text: "Unlimited", color: CopilotTelemetryTheme.azure)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(row.percentage)%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(UsageColor.forUtilization(row.percentage))
                        Text(row.detail)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(CopilotTelemetryTheme.secondaryText)
                    }
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    if row.unlimited {
                        Capsule()
                            .fill(CopilotTelemetryTheme.azure)
                            .frame(width: max(8, geometry.size.width))
                    } else {
                        UsageColor.utilizationGradient
                            .mask(alignment: .leading) {
                                Capsule()
                                    .frame(width: max(8, geometry.size.width * CGFloat(row.percentage) / 100))
                            }
                    }
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 7)
    }

    private var divider: some View {
        Divider()
            .overlay(Color.white.opacity(0.05))
    }
}

private struct CopilotRecentActivityView: View {
    let dataPoints: [CopilotHistoryDataPoint]

    private var filteredPoints: [CopilotHistoryDataPoint] {
        let cutoff = Date().addingTimeInterval(-QuotaTimeRange.hour6.interval)
        return dataPoints.filter { $0.timestamp >= cutoff }
    }

    private var plottedPoints: [(time: Date, value: Int)] {
        filteredPoints.compactMap { point in
            if let premium = point.premiumUtilization {
                return (point.timestamp, premium)
            }
            if let completions = point.completionsUtilization {
                return (point.timestamp, completions)
            }
            if let chat = point.chatUtilization {
                return (point.timestamp, chat)
            }
            return nil
        }
    }

    private var latestValue: Int? {
        plottedPoints.last?.value
    }

    private var peakValue: Int? {
        plottedPoints.map(\.value).max()
    }

    var body: some View {
        CopilotSectionCard(title: "Recent Activity", subtitle: "Highest visible lane usage in the last 6 hours", surfaceColor: CopilotTelemetryTheme.panel) {
            VStack(alignment: .leading, spacing: 10) {
                if plottedPoints.isEmpty {
                    Text("No history yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CopilotTelemetryTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    chart
                    summaryRail
                }
            }
        }
    }

    private var chart: some View {
        let values = plottedPoints.map { Double($0.value) }
        let minValue = values.min() ?? 0
        let maxValue = max(values.max() ?? 1, minValue + 1)
        let domainMax = max(maxValue + max((maxValue - minValue) * 0.15, 8), 100)

        return Chart {
            ForEach(Array(plottedPoints.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Time", point.time),
                    y: .value("Usage", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [CopilotTelemetryTheme.line.opacity(0.25), CopilotTelemetryTheme.line.opacity(0.02)],
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
                        colors: [CopilotTelemetryTheme.electric, CopilotTelemetryTheme.azure],
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
                    .foregroundStyle(CopilotTelemetryTheme.tertiaryText)
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
                        colors: [CopilotTelemetryTheme.chartTop, CopilotTelemetryTheme.chartBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CopilotTelemetryTheme.edge, lineWidth: 1)
        )
    }

    private var summaryRail: some View {
        HStack(spacing: 10) {
            metricPill(title: "Latest", value: latestValue.map { "\($0)%" } ?? "0%")
            metricPill(title: "Peak", value: peakValue.map { "\($0)%" } ?? "0%")
            metricPill(title: "Samples", value: "\(plottedPoints.count)")
        }
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(CopilotTelemetryTheme.tertiaryText)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(CopilotTelemetryTheme.primaryText)
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

private struct CopilotFooterView: View {
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
                        .foregroundColor(CopilotTelemetryTheme.tertiaryText)
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
                    .foregroundColor(CopilotTelemetryTheme.secondaryText)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(CopilotTelemetryTheme.secondaryText)
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

struct CopilotTabView: View {
    @ObservedObject var copilotService: CopilotService
    @ObservedObject var historyService: CopilotHistoryService
    let timeZone: TimeZone
    var providerStatus: ProviderStatusService.StatusInfo?
    var forceEmptyState: Bool = false
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        if forceEmptyState || copilotService.error == .noToken {
            connectGitHubView
        } else {
            let copilotData = copilotService.copilotData

            VStack(alignment: .leading, spacing: 10) {
                header(planType: copilotData.plan)

                if copilotService.error == .tokenExpired {
                    ErrorBannerView(message: "GitHub token expired — run `gh auth login`")
                } else if copilotService.error == .fetchFailed {
                    ErrorBannerView(message: "Failed to fetch Copilot data") {
                        Task { await copilotService.fetch() }
                    }
                } else if case .rateLimited = copilotService.error {
                    ErrorBannerView(message: "Rate limited — retrying", retryDate: copilotService.retryDate)
                }

                if let status = providerStatus, status.indicator != "none" {
                    ProviderStatusBannerView(status: status)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    CopilotHeroView(data: copilotData, timeZone: timeZone, now: context.date)
                }

                CopilotLimitsView(rows: limitRows(from: copilotData))
                CopilotRecentActivityView(dataPoints: historyService.history.dataPoints)
                CopilotFooterView(
                    fetchedAt: copilotData.fetchedAt,
                    isStale: copilotService.isStale,
                    onRefresh: onRefresh,
                    onOpenSettings: onOpenSettings
                )
            }
            .padding(.top, 2)
        }
    }

    private var connectGitHubView: some View {
        CopilotSectionCard(title: "Copilot Access", subtitle: "Connect GitHub CLI to monitor runtime telemetry", surfaceColor: CopilotTelemetryTheme.panelRaised) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CopilotTelemetryTheme.azure.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image("copilot")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .foregroundColor(CopilotTelemetryTheme.electric)
                }

                VStack(spacing: 4) {
                    Text("Control plane offline")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(CopilotTelemetryTheme.primaryText)
                    Text("Authenticate via GitHub CLI to track chat, completions, and premium interactions live.")
                        .font(.system(size: 11))
                        .foregroundColor(CopilotTelemetryTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                CopilotBadge(text: "Run gh auth login", color: CopilotTelemetryTheme.azure)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func header(planType: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Copilot")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(CopilotTelemetryTheme.primaryText)
                Text("Control Plane")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CopilotTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)
            }

            Spacer()

            if !planType.isEmpty {
                CopilotBadge(text: cleanedPlanName(planType), color: CopilotTelemetryTheme.electric)
            }
        }
    }

    private func limitRows(from data: CopilotUsageData) -> [CopilotLimitRow] {
        [
            buildRow(id: "chat", icon: "bubble.left.and.bubble.right", title: "Chat", quota: data.chat),
            buildRow(id: "completions", icon: "wand.and.stars", title: "Completions", quota: data.completions),
            buildRow(id: "premium", icon: "bolt.horizontal.circle", title: "Premium", quota: data.premiumInteractions)
        ]
    }

    private func buildRow(id: String, icon: String, title: String, quota: CopilotQuota) -> CopilotLimitRow {
        CopilotLimitRow(
            id: id,
            icon: icon,
            title: title,
            subtitle: quota.unlimited ? "Unlimited lane" : "Monthly quota lane",
            percentage: quota.unlimited ? 0 : quota.utilization,
            detail: quota.unlimited ? "No cap" : "\(quota.remaining)/\(quota.entitlement) left",
            unlimited: quota.unlimited
        )
    }

    private func cleanedPlanName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
