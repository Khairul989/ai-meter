import AppKit
import SwiftUI
import Charts

enum ClaudeTelemetryTheme {
    static let panel = Color(red: 0.14, green: 0.14, blue: 0.15)
    static let panelRaised = Color(red: 0.18, green: 0.18, blue: 0.19)
    static let heroTop = Color(red: 0.25, green: 0.21, blue: 0.14)
    static let heroBottom = Color(red: 0.13, green: 0.13, blue: 0.14)
    static let insight = Color(red: 0.19, green: 0.17, blue: 0.14)
    static let edge = Color.white.opacity(0.08)
    static let strongEdge = Color.white.opacity(0.14)
    static let primaryText = Color.white
    static let secondaryText = Color(red: 0.72, green: 0.71, blue: 0.68)
    static let tertiaryText = Color(red: 0.56, green: 0.56, blue: 0.53)
    static let amber = Color(red: 0.95, green: 0.73, blue: 0.31)
    static let amberSoft = Color(red: 0.94, green: 0.79, blue: 0.48)
    static let metal = Color(red: 0.36, green: 0.34, blue: 0.28)
    static let analyticsBackground = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let analyticsTop = Color(red: 0.17, green: 0.14, blue: 0.10)
    static let analyticsBottom = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let analyticsLine = Color(red: 0.49, green: 0.83, blue: 1.00)
}

private struct ClaudeInsight {
    let icon: String
    let title: String
    let detail: String
}

private struct ClaudeLimitRow: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let percentage: Int
    let detail: String
    var pace: UsagePace.Result? = nil
}

private struct ClaudeAnalyticsSummary: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let accent: Color
}

private struct ClaudeBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(color.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct ClaudeSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let surfaceColor: Color
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, surfaceColor: Color = ClaudeTelemetryTheme.panel, @ViewBuilder content: () -> Content) {
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
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
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
                .stroke(ClaudeTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct ClaudeDialGauge: View {
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
                .stroke(ClaudeTelemetryTheme.edge, lineWidth: 8)

            ForEach(0..<segmentCount, id: \.self) { index in
                let start = Double(index) / Double(segmentCount)
                let end = Double(index + 1) / Double(segmentCount)
                let visibleEnd = min(progress, end)

                if visibleEnd > start {
                    Circle()
                        .trim(from: start, to: visibleEnd)
                        .stroke(
                            color(at: (start + visibleEnd) / 2),
                            style: StrokeStyle(
                                lineWidth: 8,
                                lineCap: index == 0 || visibleEnd == progress ? .round : .butt
                            )
                        )
                        .rotationEffect(.degrees(-90))
                }
            }

            Circle()
                .fill(Color.black.opacity(0.18))
                .padding(12)

            VStack(spacing: 3) {
                Text("Session")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.7)
                Text("5H")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(ClaudeTelemetryTheme.primaryText)
            }
        }
        .frame(width: 114, height: 114)
    }
}

private struct ClaudeHeroView: View {
    let usage: UsageData
    let timeZone: TimeZone
    let pace: UsagePace.Result?
    let now: Date

    private var urgencyText: String? {
        pace?.etaDescription
    }

    private var paceLabel: String {
        guard let pace else { return "Steady" }
        switch pace.stage {
        case .farBehind, .behind, .slightlyBehind:
            return "Conservative pace"
        case .onTrack:
            return "Steady pace"
        case .slightlyAhead, .ahead, .farAhead:
            return "Aggressive pace"
        }
    }

    private var detailLine: String {
        if let urgencyText {
            return urgencyText
        }
        return "Quota lasts until reset at the current pace."
    }

    private var paceSummaryText: String {
        guard let pace else { return "Tracking close to a steady pace." }
        let delta = Int(abs(pace.deltaPercent).rounded())
        if delta < 5 {
            return "Tracking close to a steady pace."
        }
        if pace.deltaPercent > 0 {
            return "\(delta)% ahead of a steady pace."
        }
        return "\(delta)% below a steady pace."
    }

    private var resetLine: String {
        let countdown = ResetTimeFormatter.format(usage.fiveHour.resetsAt, style: .countdown, timeZone: timeZone, now: now) ?? "soon"
        let clock = resetClockText
        return "Reset \(countdown) at \(clock)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Session Telemetry")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)

                Text("\(usage.fiveHour.utilization)%")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(ClaudeTelemetryTheme.amber)

                Text(resetLine)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .layoutPriority(1)

                Text(paceLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(UsageColor.forUtilization(usage.fiveHour.utilization))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(UsageColor.forUtilization(usage.fiveHour.utilization).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(paceSummaryText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ClaudeTelemetryTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: urgencyText == nil ? "clock" : "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(urgencyText == nil ? ClaudeTelemetryTheme.secondaryText : ClaudeTelemetryTheme.amberSoft)
                    Text(detailLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ClaudeDialGauge(percentage: usage.fiveHour.utilization)
                .padding(.vertical, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [ClaudeTelemetryTheme.heroTop, ClaudeTelemetryTheme.heroBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ClaudeTelemetryTheme.strongEdge, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(ClaudeTelemetryTheme.amber)
                .frame(width: 48, height: 3)
                .padding(.top, 1)
                .padding(.leading, 16)
        }
    }

    private var resetClockText: String {
        guard let date = usage.fiveHour.resetsAt else { return "soon" }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }
}

private struct ClaudeLimitsListView: View {
    let rows: [ClaudeLimitRow]

    var body: some View {
        ClaudeSectionCard(title: "Limit Bank", subtitle: "Secondary quotas and spend", surfaceColor: ClaudeTelemetryTheme.panelRaised) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    VStack(spacing: 8) {
                        HStack(alignment: .center, spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(UsageColor.forUtilization(row.percentage).opacity(0.14))
                                    .frame(width: 28, height: 28)
                                Image(systemName: row.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(UsageColor.forUtilization(row.percentage))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(ClaudeTelemetryTheme.primaryText)
                                Text(row.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(row.percentage)%")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(UsageColor.forUtilization(row.percentage))
                                Text(row.detail)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                            }
                        }

                        ProgressBarView(percentage: row.percentage, height: 4)
                            .frame(height: 4)

                        if let pace = row.pace {
                            HStack(spacing: 6) {
                                let paceLabel: String = {
                                    switch pace.stage {
                                    case .farBehind, .behind, .slightlyBehind: return "Conservative"
                                    case .onTrack: return "Steady"
                                    case .slightlyAhead, .ahead, .farAhead: return "Aggressive"
                                    }
                                }()
                                let delta = Int(abs(pace.deltaPercent).rounded())
                                let sign = pace.deltaPercent >= 0 ? "+" : "-"
                                let paceColor = UsageColor.forUtilization(row.percentage)

                                Text(paceLabel)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(paceColor)
                                    .textCase(.uppercase)
                                    .tracking(0.4)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(paceColor.opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                                if delta >= 1 {
                                    Text("\(sign)\(delta)%")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                                }

                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.vertical, 10)

                    if index < rows.count - 1 {
                        Divider()
                            .background(ClaudeTelemetryTheme.edge)
                    }
                }
            }
        }
    }
}

private struct ClaudeInsightView: View {
    let insight: ClaudeInsight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ClaudeTelemetryTheme.amber.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: insight.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ClaudeTelemetryTheme.amber)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Insight")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(insight.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ClaudeTelemetryTheme.primaryText)
                Text(insight.detail)
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ClaudeTelemetryTheme.insight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ClaudeTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct ClaudeFooterView: View {
    let fetchedAt: Date
    let isStale: Bool
    let onOpenAnalytics: () -> Void
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text(updatedText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                    if isStale {
                        Text("stale")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(ClaudeTelemetryTheme.amber)
                    }
                }

                Spacer()

                Button("Analytics", action: onOpenAnalytics)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(ClaudeTelemetryTheme.primaryText)

                Button("Settings", action: onOpenSettings)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(ClaudeTelemetryTheme.secondaryText)
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

struct ClaudeTabView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var statsService: ClaudeCodeStatsService
    @EnvironmentObject private var authManager: SessionAuthManager
    @EnvironmentObject private var codexAuthManager: CodexAuthManager
    let timeZone: TimeZone
    var planName: String?
    var providerStatus: ProviderStatusService.StatusInfo?
    var onOpenAnalytics: () -> Void
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        let data = service.usageData

        VStack(spacing: 10) {
            header

            if case .rateLimited = service.error {
                ErrorBannerView(message: "Rate limited — retrying", retryDate: service.retryDate)
            } else if case .sessionExpired = service.error {
                ErrorBannerView(message: "Session expired — sign in again")
            } else if case .cloudflareBlocked = service.error {
                ErrorBannerView(message: "Blocked by Cloudflare — try again later") {
                    Task { await service.fetch() }
                }
            } else if service.error == .fetchFailed {
                ErrorBannerView(message: "Failed to fetch usage data") {
                    Task { await service.fetch() }
                }
            }

            if let status = providerStatus, status.indicator != "none" {
                ProviderStatusBannerView(status: status)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                ClaudeHeroView(
                    usage: data,
                    timeZone: timeZone,
                    pace: UsagePace.calculate(
                        usagePercent: data.fiveHour.utilization,
                        resetsAt: data.fiveHour.resetsAt,
                        windowDurationHours: 5.0,
                        now: context.date
                    ),
                    now: context.date
                )
            }

            if !limitRows.isEmpty {
                ClaudeLimitsListView(rows: limitRows)
            }

            if let insight {
                ClaudeInsightView(insight: insight)
            }

            ClaudeFooterView(
                fetchedAt: data.fetchedAt,
                isStale: service.isStale,
                onOpenAnalytics: onOpenAnalytics,
                onRefresh: onRefresh,
                onOpenSettings: onOpenSettings
            )
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(ClaudeTelemetryTheme.primaryText)
                    Text("Quota telemetry")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    if let planName {
                        ClaudeBadge(text: planName, color: ClaudeTelemetryTheme.amber)
                    }

                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        if PeakHoursHelper.isPeakHours(now: context.date) {
                            ClaudeBadge(text: "Peak", color: ClaudeTelemetryTheme.amberSoft)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)

            if authManager.accounts.count > 1 {
                accountSwitcher
            }
        }
    }

    private var limitRows: [ClaudeLimitRow] {
        let weeklyData = service.usageData.sevenDay
        var rows: [ClaudeLimitRow] = [
            ClaudeLimitRow(
                id: "weekly",
                icon: "chart.bar.fill",
                title: "Weekly",
                subtitle: "All models",
                percentage: weeklyData.utilization,
                detail: limitDetail(weeklyData.resetsAt),
                pace: UsagePace.calculate(
                    usagePercent: weeklyData.utilization,
                    resetsAt: weeklyData.resetsAt,
                    windowDurationHours: 168.0
                )
            )
        ]

        if let sonnet = service.usageData.sevenDaySonnet {
            rows.append(ClaudeLimitRow(
                id: "sonnet",
                icon: "sparkles",
                title: "Sonnet",
                subtitle: "Dedicated limit",
                percentage: sonnet.utilization,
                detail: limitDetail(sonnet.resetsAt)
            ))
        }

        if let design = service.usageData.sevenDayDesign {
            rows.append(ClaudeLimitRow(
                id: "design",
                icon: "paintbrush.pointed.fill",
                title: "Claude Design",
                subtitle: "Dedicated limit",
                percentage: design.utilization,
                detail: limitDetail(design.resetsAt)
            ))
        }

        if let credits = service.usageData.extraCredits {
            rows.append(ClaudeLimitRow(
                id: "credits",
                icon: "creditcard.fill",
                title: "Extra Credits",
                subtitle: "Usage-based spend",
                percentage: credits.utilization,
                detail: String(format: "$%.2f", credits.used)
            ))
        }

        return rows
    }

    private var insight: ClaudeInsight? {
        if let topModel = statsService.models.first, statsService.totalTokens > 0 {
            let share = Int(round(Double(topModel.totalTokens) / Double(statsService.totalTokens) * 100))
            return ClaudeInsight(
                icon: "brain.head.profile",
                title: "\(topModel.displayName) is driving usage today",
                detail: "\(share)% of today's Claude Code tokens"
            )
        }

        let totalMessages = statsService.trendPoints.reduce(0) { $0 + $1.messages }
        if totalMessages > 0 {
            return ClaudeInsight(
                icon: "waveform.path.ecg",
                title: "Claude Code activity is building up",
                detail: "\(formatCompact(totalMessages)) messages in the current trend view"
            )
        }

        return ClaudeInsight(
            icon: "moon.stars.fill",
            title: "No Claude Code activity yet today",
            detail: "Open Analytics after your next Claude Code session for model and trend details."
        )
    }

    @ViewBuilder
    private var accountSwitcher: some View {
        Menu {
            ForEach(authManager.accounts) { account in
                Button {
                    authManager.setActiveAccount(account.id)
                } label: {
                    HStack {
                        Text(account.organizationName.isEmpty ? account.id : account.organizationName)
                        if account.id == authManager.activeAccountId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                Text(authManager.activeAccount?.organizationName.isEmpty == false ? (authManager.activeAccount?.organizationName ?? "") : (authManager.activeAccount?.id ?? ""))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ClaudeTelemetryTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ClaudeTelemetryTheme.edge, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func formatCompact(_ value: Int) -> String {
        switch value {
        case ..<1_000:
            return "\(value)"
        case ..<1_000_000:
            let k = Double(value) / 1_000
            return k >= 100 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
        default:
            let m = Double(value) / 1_000_000
            return m >= 100 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        }
    }

    private func limitDetail(_ date: Date?) -> String {
        ResetTimeFormatter.format(date, style: .dayTime, timeZone: timeZone) ?? "No reset"
    }
}

struct ClaudeAnalyticsView: View {
    @ObservedObject var statsService: ClaudeCodeStatsService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                analyticsHeader
                ClaudeAnalyticsSummaryGrid(items: summaryItems)
                ClaudeAnalyticsModelsPanel(statsService: statsService)
                ClaudeAnalyticsTrendPanel(statsService: statsService)
            }
            .padding(22)
        }
        .frame(minWidth: 560, minHeight: 500)
        .background(
            LinearGradient(
                colors: [ClaudeTelemetryTheme.analyticsTop, ClaudeTelemetryTheme.analyticsBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var analyticsHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Analytics")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(ClaudeTelemetryTheme.primaryText)
                Text("Model mix and recent traffic across Claude Code sessions")
                    .font(.system(size: 12))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text("Telemetry Window")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(statsService.isLoading ? "Refreshing logs" : "Live from Claude JSONL")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
            }
        }
    }

    private var summaryItems: [ClaudeAnalyticsSummary] {
        let points = statsService.trendPoints
        let totalMessages = points.reduce(0) { $0 + $1.messages }
        let totalTokens = points.reduce(0) { $0 + $1.tokens }
        let activeDays = points.filter { $0.messages > 0 || $0.tokens > 0 }.count
        let avgMessages = activeDays > 0 ? totalMessages / activeDays : 0

        let topModel = statsService.models.max(by: { $0.totalTokens < $1.totalTokens })
        let topShare = statsService.totalTokens > 0 && topModel != nil
            ? Int((Double(topModel!.totalTokens) / Double(statsService.totalTokens) * 100).rounded())
            : 0

        return [
            ClaudeAnalyticsSummary(
                id: "tokens",
                title: "Range Tokens",
                value: formatCompact(statsService.totalTokens),
                detail: statsService.selectedRange.rawValue,
                accent: ClaudeTelemetryTheme.amber
            ),
            ClaudeAnalyticsSummary(
                id: "leader",
                title: "Leading Model",
                value: topModel?.displayName ?? "None",
                detail: topModel == nil ? "No model activity" : "\(topShare)% of visible usage",
                accent: topModel.map(modelColor(for:)) ?? ClaudeTelemetryTheme.secondaryText
            ),
            ClaudeAnalyticsSummary(
                id: "messages",
                title: "Avg Messages",
                value: "\(avgMessages)",
                detail: activeDays == 0 ? "No active days" : "per active day",
                accent: ClaudeTelemetryTheme.analyticsLine
            ),
            ClaudeAnalyticsSummary(
                id: "days",
                title: "Active Days",
                value: "\(activeDays)",
                detail: "\(formatCompact(totalMessages)) msgs / \(formatCompact(totalTokens)) tok",
                accent: .green
            )
        ]
    }

    private func modelColor(for model: ModelTokenUsage) -> Color {
        switch model.colorIndex {
        case 0: return .orange
        case 1: return .blue
        case 2: return .green
        default: return .gray
        }
    }

    private func formatCompact(_ value: Int) -> String {
        switch value {
        case ..<1_000:
            return "\(value)"
        case ..<1_000_000:
            let k = Double(value) / 1_000
            return k >= 100 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
        default:
            let m = Double(value) / 1_000_000
            return m >= 100 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        }
    }
}

private struct ClaudeAnalyticsSummaryGrid: View {
    let items: [ClaudeAnalyticsSummary]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Text(item.value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(ClaudeTelemetryTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(item.detail)
                        .font(.system(size: 11))
                        .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ClaudeTelemetryTheme.panelRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(ClaudeTelemetryTheme.edge, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.accent)
                        .frame(width: 36, height: 3)
                        .padding(.top, 1)
                        .padding(.leading, 14)
                }
            }
        }
    }
}

private struct ClaudeAnalyticsPanel<Content: View, Controls: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let controls: Controls
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.controls = controls()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                        .textCase(.uppercase)
                        .tracking(0.85)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                }

                Spacer(minLength: 12)
                controls
            }

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ClaudeTelemetryTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ClaudeTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct ClaudeSegmentedPicker<Selection: Hashable & RawRepresentable>: View where Selection.RawValue == String {
    let options: [Selection]
    let selection: Selection
    let onSelect: (Selection) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(selection == option ? ClaudeTelemetryTheme.primaryText : ClaudeTelemetryTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selection == option ? ClaudeTelemetryTheme.panelRaised : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(ClaudeTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct ClaudeAnalyticsModelsPanel: View {
    @ObservedObject var statsService: ClaudeCodeStatsService

    var body: some View {
        ClaudeAnalyticsPanel(
            title: "Model Distribution",
            subtitle: "Token share, input volume, and output volume by model"
        ) {
            ClaudeSegmentedPicker(
                options: ModelTimeRange.allCases,
                selection: statsService.selectedRange,
                onSelect: { statsService.selectedRange = $0 }
            )
        } content: {
            if statsService.isLoading && statsService.models.isEmpty && statsService.selectedRange != .allTime {
                VStack(spacing: 8) {
                    SkeletonBlock(height: 8)
                    SkeletonBlock(height: 54)
                    SkeletonBlock(height: 54)
                }
                .modifier(ShimmerModifier())
            } else if statsService.models.isEmpty {
                EmptyStateView(
                    icon: "cpu",
                    message: "No model usage in this period",
                    hint: "Select another range to inspect older activity"
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    modelRail
                    VStack(spacing: 10) {
                        ForEach(statsService.models) { model in
                            ClaudeAnalyticsModelRow(
                                model: model,
                                share: share(for: model),
                                color: colorFor(model)
                            )
                        }
                    }
                }
            }
        }
    }

    private var modelRail: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(statsService.models) { model in
                    let fraction = max(CGFloat(model.totalTokens) / CGFloat(max(statsService.totalTokens, 1)), 0)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colorFor(model))
                        .frame(width: max(geo.size.width * fraction, 6))
                }
            }
        }
        .frame(height: 10)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    private func share(for model: ModelTokenUsage) -> Int {
        guard statsService.totalTokens > 0 else { return 0 }
        return Int((Double(model.totalTokens) / Double(statsService.totalTokens) * 100).rounded())
    }

    private func colorFor(_ model: ModelTokenUsage) -> Color {
        switch model.colorIndex {
        case 0: return .orange
        case 1: return .blue
        case 2: return .green
        default: return .gray
        }
    }
}

private struct ClaudeAnalyticsModelRow: View {
    let model: ModelTokenUsage
    let share: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ClaudeTelemetryTheme.primaryText)
                    Text("\(share)% of visible tokens")
                        .font(.system(size: 10))
                        .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCompact(model.totalTokens))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(ClaudeTelemetryTheme.primaryText)
                    Text("\(formatCompact(model.inputTokens)) in  •  \(formatCompact(model.outputTokens)) out")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(0.9))
                        .frame(width: geo.size.width * CGFloat(share) / 100)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ClaudeTelemetryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ClaudeTelemetryTheme.edge, lineWidth: 1)
        )
    }

    private func formatCompact(_ value: Int) -> String {
        switch value {
        case ..<1_000:
            return "\(value)"
        case ..<1_000_000:
            let k = Double(value) / 1_000
            return k >= 100 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
        default:
            let m = Double(value) / 1_000_000
            return m >= 100 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        }
    }
}

private struct ClaudeAnalyticsTrendPanel: View {
    @ObservedObject var statsService: ClaudeCodeStatsService
    @State private var hoverDate: Date?

    var body: some View {
        ClaudeAnalyticsPanel(
            title: "Daily Traffic",
            subtitle: "Message throughput with token-weighted trend overlay"
        ) {
            ClaudeSegmentedPicker(
                options: TrendRange.allCases,
                selection: statsService.trendRange,
                onSelect: { statsService.trendRange = $0 }
            )
        } content: {
            if statsService.isLoading && statsService.trendPoints.allSatisfy({ $0.messages == 0 && $0.tokens == 0 }) {
                VStack(spacing: 8) {
                    SkeletonBlock(height: 160)
                    SkeletonBlock(height: 28)
                }
                .modifier(ShimmerModifier())
            } else if statsService.trendPoints.allSatisfy({ $0.messages == 0 && $0.tokens == 0 }) {
                EmptyStateView(
                    icon: "chart.xyaxis.line",
                    message: "No recent Claude traffic",
                    hint: "Once Claude Code logs are present, the trend view will populate"
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    chartView
                    summaryStrip
                }
            }
        }
    }

    private var chartView: some View {
        let points = statsService.trendPoints
        let maxMessages = max(points.map(\.messages).max() ?? 0, 1)
        let maxTokens = max(points.map(\.tokens).max() ?? 0, 1)

        return Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Messages", point.messages)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [ClaudeTelemetryTheme.amberSoft.opacity(0.65), ClaudeTelemetryTheme.amber.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(3)
            }

            ForEach(points) { point in
                let scaledTokens = Double(point.tokens) / Double(maxTokens) * Double(maxMessages)
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Tokens", scaledTokens)
                )
                .foregroundStyle(ClaudeTelemetryTheme.analyticsLine)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            ForEach(points) { point in
                let scaledTokens = Double(point.tokens) / Double(maxTokens) * Double(maxMessages)
                PointMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Tokens", scaledTokens)
                )
                .foregroundStyle(ClaudeTelemetryTheme.analyticsLine)
                .symbolSize(18)
            }

            if let hoverDate, let nearest = nearestTrendPoint(to: hoverDate, in: points) {
                RuleMark(x: .value("Hover", nearest.date))
                    .foregroundStyle(Color.white.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dayLabel(nearest.date))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                            Text("\(nearest.messages) msgs")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(ClaudeTelemetryTheme.amber)
                            Text("\(formatCompact(nearest.tokens)) tok")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(ClaudeTelemetryTheme.analyticsLine)
                        }
                        .padding(6)
                        .background(ClaudeTelemetryTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(dayLabel(date))
                            .font(.system(size: 8))
                            .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.06))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text(formatCompact(v))
                            .font(.system(size: 8))
                            .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.05))
            }
        }
        .chartYScale(domain: 0...maxMessages)
        .chartLegend(.hidden)
        .frame(height: 180)
        .chartPlotStyle { plot in
            plot
                .background(Color.white.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let origin = geo[proxy.plotAreaFrame].origin
                            hoverDate = proxy.value(atX: location.x - origin.x, as: Date.self)
                        case .ended:
                            hoverDate = nil
                        }
                    }
            }
        }
    }

    private var summaryStrip: some View {
        let points = statsService.trendPoints
        let totalMessages = points.reduce(0) { $0 + $1.messages }
        let totalTokens = points.reduce(0) { $0 + $1.tokens }
        let activeDays = points.filter { $0.messages > 0 || $0.tokens > 0 }.count
        let avgMessages = activeDays > 0 ? totalMessages / activeDays : 0

        return HStack(spacing: 10) {
            summaryPill(title: "Avg / Active Day", value: "\(avgMessages) msgs", accent: ClaudeTelemetryTheme.amber)
            summaryPill(title: "Total Messages", value: formatCompact(totalMessages), accent: ClaudeTelemetryTheme.primaryText)
            summaryPill(title: "Total Tokens", value: formatCompact(totalTokens), accent: ClaudeTelemetryTheme.analyticsLine)
        }
    }

    private func summaryPill(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                .textCase(.uppercase)
                .tracking(0.7)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ClaudeTelemetryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ClaudeTelemetryTheme.edge, lineWidth: 1)
        )
    }

    private func nearestTrendPoint(to date: Date, in points: [DailyTrendPoint]) -> DailyTrendPoint? {
        points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    private var xAxisStride: Int {
        switch statsService.trendRange {
        case .sevenDay: return 1
        case .fourteenDay: return 3
        case .thirtyDay: return 5
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func formatCompact(_ value: Int) -> String {
        switch value {
        case ..<1_000:
            return "\(value)"
        case ..<1_000_000:
            let k = Double(value) / 1_000
            return k >= 100 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
        default:
            let m = Double(value) / 1_000_000
            return m >= 100 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        }
    }
}

final class ClaudeAnalyticsWindowController: NSWindowController {
    private static var instance: ClaudeAnalyticsWindowController?
    private static var hostingView: NSHostingView<ClaudeAnalyticsView>?

    static func show(statsService: ClaudeCodeStatsService) {
        if let existing = instance {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            hostingView?.rootView = ClaudeAnalyticsView(statsService: statsService)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Analytics"
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        window.minSize = NSSize(width: 520, height: 430)
        window.center()

        let hosting = NSHostingView(rootView: ClaudeAnalyticsView(statsService: statsService))
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 480)
        window.contentView = hosting
        hostingView = hosting

        let controller = ClaudeAnalyticsWindowController(window: window)
        instance = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
