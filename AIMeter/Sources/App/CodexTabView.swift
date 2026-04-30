import AppKit
import SwiftUI
import Charts

enum CodexTelemetryTheme {
    static let panel = Color(red: 0.13, green: 0.15, blue: 0.15)
    static let panelRaised = Color(red: 0.15, green: 0.18, blue: 0.18)
    static let heroTop = Color(red: 0.10, green: 0.19, blue: 0.16)
    static let heroBottom = Color(red: 0.08, green: 0.10, blue: 0.10)
    static let chartTop = Color(red: 0.08, green: 0.13, blue: 0.11)
    static let chartBottom = Color(red: 0.07, green: 0.09, blue: 0.09)
    static let edge = Color.white.opacity(0.08)
    static let strongEdge = Color.white.opacity(0.14)
    static let primaryText = Color.white
    static let secondaryText = Color(red: 0.74, green: 0.77, blue: 0.75)
    static let tertiaryText = Color(red: 0.53, green: 0.58, blue: 0.56)
    static let jade = Color(red: 0.22, green: 0.86, blue: 0.64)
    static let mint = Color(red: 0.45, green: 0.95, blue: 0.72)
    static let teal = Color(red: 0.18, green: 0.73, blue: 0.63)
    static let lime = Color(red: 0.74, green: 0.92, blue: 0.34)
    static let glow = Color(red: 0.58, green: 0.92, blue: 0.78)
}

private struct CodexLimitRow: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let percentage: Int
    let detail: String
}

private struct CodexInsight {
    let icon: String
    let title: String
    let detail: String
}

private struct CodexBadge: View {
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
                    .stroke(color.opacity(0.22), lineWidth: 1)
            )
    }
}

private struct CodexSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let surfaceColor: Color
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, surfaceColor: Color = CodexTelemetryTheme.panel, @ViewBuilder content: () -> Content) {
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
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(CodexTelemetryTheme.tertiaryText)
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
                .stroke(CodexTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct CodexDialGauge: View {
    let percentage: Int
    private let segmentCount = 72

    private var progress: Double {
        Double(min(max(percentage, 0), 100)) / 100.0
    }

    private func color(at location: Double) -> Color {
        let stops: [(Double, NSColor)] = [
            (0.00, NSColor(CodexTelemetryTheme.jade)),
            (0.42, NSColor(CodexTelemetryTheme.lime)),
            (0.70, .systemYellow),
            (0.88, .systemOrange),
            (0.97, .systemRed),
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
                .stroke(CodexTelemetryTheme.edge, lineWidth: 10)

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
                                lineWidth: 10,
                                lineCap: index == 0 || visibleEnd == progress ? .round : .butt
                            )
                        )
                        .rotationEffect(.degrees(-90))
                }
            }

            Circle()
                .fill(Color.black.opacity(0.18))
                .padding(14)

            VStack(spacing: 3) {
                Text("Window")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.7)
                Text("5H")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(CodexTelemetryTheme.primaryText)
            }
        }
        .frame(width: 128, height: 128)
    }
}

private struct CodexHeroView: View {
    let data: CodexUsageData
    let timeZone: TimeZone
    let pace: UsagePace.Result?
    let now: Date

    private var paceLabel: String {
        guard let pace else { return "Stable burn" }
        switch pace.stage {
        case .farBehind, .behind, .slightlyBehind:
            return "Conservative"
        case .onTrack:
            return "On pace"
        case .slightlyAhead, .ahead, .farAhead:
            return "Aggressive"
        }
    }

    private var paceSummaryText: String {
        guard let pace else { return "On pace." }
        let delta = Int(abs(pace.deltaPercent).rounded())
        if delta < 5 {
            return "On pace."
        }
        if pace.deltaPercent > 0 {
            return "\(delta)% ahead."
        }
        return "\(delta)% below."
    }

    private var detailLine: String {
        if let eta = pace?.etaDescription {
            return eta
        }
        return "Holds to reset."
    }

    private var resetLine: String {
        let countdown = ResetTimeFormatter.format(data.primaryResetAt, style: .countdown, timeZone: timeZone, now: now) ?? "soon"
        return "Reset \(countdown) • \(resetClockText)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Window Telemetry")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)

                Text("\(data.primaryPercent)%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(CodexTelemetryTheme.mint)

                Text(resetLine)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                    .layoutPriority(1)

                Text(paceLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(UsageColor.forUtilization(data.primaryPercent))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(UsageColor.forUtilization(data.primaryPercent).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(paceSummaryText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CodexTelemetryTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: pace?.etaDescription == nil ? "clock.arrow.circlepath" : "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(pace?.etaDescription == nil ? CodexTelemetryTheme.secondaryText : CodexTelemetryTheme.glow)
                    Text(detailLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CodexTelemetryTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CodexDialGauge(percentage: data.primaryPercent)
                .scaleEffect(0.9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CodexTelemetryTheme.heroTop, CodexTelemetryTheme.heroBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CodexTelemetryTheme.strongEdge, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(CodexTelemetryTheme.mint)
                .frame(width: 48, height: 3)
                .padding(.top, 1)
                .padding(.leading, 14)
        }
    }

    private var resetClockText: String {
        guard let date = data.primaryResetAt else { return "soon" }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }
}

private struct CodexLimitsView: View {
    let rows: [CodexLimitRow]

    var body: some View {
        CodexSectionCard(title: "Limit Bank", subtitle: "Quota windows and review capacity", surfaceColor: CodexTelemetryTheme.panelRaised) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    quotaRow(row)
                    if index < rows.count - 1 {
                        divider
                    }
                }
            }
        }
    }

    private func quotaRow(_ row: CodexLimitRow) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(UsageColor.forUtilization(row.percentage).opacity(0.14))
                        .frame(width: 24, height: 24)
                    Image(systemName: row.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(UsageColor.forUtilization(row.percentage))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(CodexTelemetryTheme.primaryText)
                    Text(row.subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(CodexTelemetryTheme.tertiaryText)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(row.percentage)%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(UsageColor.forUtilization(row.percentage))
                    Text(row.detail)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(CodexTelemetryTheme.secondaryText)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    UsageColor.utilizationGradient
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

    private var divider: some View {
        Divider()
            .overlay(Color.white.opacity(0.05))
    }

}

private struct CodexControlPlaneView: View {
    @ObservedObject var codexAuthManager: CodexAuthManager

    var body: some View {
        CodexSectionCard(title: "Control Plane", subtitle: "Account routing and proxy state", surfaceColor: CodexTelemetryTheme.panelRaised) {
            VStack(spacing: 0) {
                accountRow
                divider
                statusRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: "Proxy",
                    value: codexAuthManager.isProxyRunning ? "Connected" : "Degraded",
                    detail: codexAuthManager.proxyStatus.displayText,
                    tone: codexAuthManager.isProxyRunning ? CodexTelemetryTheme.jade : .orange
                )
                divider
                statusRow(
                    icon: "arrow.triangle.branch",
                    title: "Routing",
                    value: codexAuthManager.isLoadBalancingAvailable ? "Auto-switch" : "Single account",
                    detail: codexAuthManager.isLoadBalancingAvailable ? "Load balancing enabled" : "Using the active account only",
                    tone: codexAuthManager.isLoadBalancingAvailable ? CodexTelemetryTheme.lime : CodexTelemetryTheme.secondaryText
                )

                if let state = codexAuthManager.activeAccountState {
                    divider
                    statusRow(
                        icon: stateIcon(state),
                        title: "Session",
                        value: accountStateText(state),
                        detail: accountStateDetail(state),
                        tone: accountStateColor(state)
                    )
                }
            }
        }
    }

    private var accountRow: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CodexTelemetryTheme.jade.opacity(0.14))
                    .frame(width: 24, height: 24)
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CodexTelemetryTheme.jade)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Account")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CodexTelemetryTheme.primaryText)
                Text(accountCountText)
                    .font(.system(size: 9))
                    .foregroundColor(CodexTelemetryTheme.tertiaryText)
            }

            Spacer()

            Menu {
                ForEach(codexAuthManager.accounts) { account in
                    Button {
                        codexAuthManager.setActiveAccount(account.id)
                    } label: {
                        HStack {
                            Text(account.email)
                            if account.id == codexAuthManager.activeAccountId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button {
                    codexAuthManager.openLoginWindow()
                } label: {
                    Label("Add Account", systemImage: "plus")
                }

                if codexAuthManager.activeAccountId != nil {
                    Button(role: .destructive) {
                        if let id = codexAuthManager.activeAccountId {
                            codexAuthManager.signOut(accountId: id)
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(CodexTelemetryTheme.tertiaryText)

                    Text(codexAuthManager.activeAccount?.email ?? "Select account")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .foregroundColor(CodexTelemetryTheme.primaryText)

                    Spacer(minLength: 6)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(CodexTelemetryTheme.tertiaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minWidth: 176, alignment: .leading)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .contentShape(Capsule(style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 7)
    }

    private var divider: some View {
        Divider()
            .overlay(Color.white.opacity(0.05))
    }

    private func statusRow(icon: String, title: String, value: String, detail: String, tone: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tone.opacity(0.14))
                    .frame(width: 24, height: 24)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tone)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CodexTelemetryTheme.primaryText)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundColor(CodexTelemetryTheme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer()

            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(tone)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        .padding(.vertical, 7)
    }

    private var accountCountText: String {
        let count = codexAuthManager.accounts.count
        if count == 1 {
            return "1 account configured"
        }
        return "\(count) accounts configured"
    }

    private func stateIcon(_ state: CodexAccountState) -> String {
        switch state.status {
        case .ready:
            return "checkmark.shield"
        case .rateLimited:
            return "clock.badge.exclamationmark"
        case .unauthorized:
            return "exclamationmark.triangle"
        case .unavailable:
            return "wifi.exclamationmark"
        }
    }

    private func accountStateText(_ state: CodexAccountState) -> String {
        switch state.status {
        case .ready:
            return "Account ready"
        case .rateLimited:
            if let resetAt = state.resetAt {
                return "Limited until \(shortTime(resetAt))"
            }
            return "Rate limited"
        case .unauthorized:
            return "Session expired"
        case .unavailable:
            return "Unavailable"
        }
    }

    private func accountStateDetail(_ state: CodexAccountState) -> String {
        switch state.status {
        case .ready:
            return "Requests can route through the active account"
        case .rateLimited:
            return state.message ?? "Traffic will route away until reset"
        case .unauthorized:
            return "Re-authenticate this account to restore traffic"
        case .unavailable:
            return state.message ?? "Proxy could not use the active account"
        }
    }

    private func accountStateColor(_ state: CodexAccountState) -> Color {
        switch state.status {
        case .ready:
            return CodexTelemetryTheme.jade
        case .rateLimited:
            return .orange
        case .unauthorized, .unavailable:
            return .red
        }
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).lowercased()
    }
}

private struct CodexFooterView: View {
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
                        .foregroundColor(CodexTelemetryTheme.tertiaryText)
                    if isStale {
                        Text("stale")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                Button("Analytics", action: onOpenAnalytics)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(CodexTelemetryTheme.primaryText)

                Button("Settings", action: onOpenSettings)
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundColor(CodexTelemetryTheme.secondaryText)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(CodexTelemetryTheme.secondaryText)
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

private struct CodexInsightView: View {
    let insight: CodexInsight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CodexTelemetryTheme.jade.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: insight.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CodexTelemetryTheme.mint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Insight")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(insight.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CodexTelemetryTheme.primaryText)
                Text(insight.detail)
                    .font(.system(size: 11))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CodexTelemetryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CodexTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct CodexRecentActivityView: View {
    let dataPoints: [CodexHistoryDataPoint]

    private var filteredPoints: [CodexHistoryDataPoint] {
        let cutoff = Date().addingTimeInterval(-QuotaTimeRange.hour6.interval)
        return dataPoints.filter { $0.timestamp >= cutoff }
    }

    private var latestPoint: CodexHistoryDataPoint? {
        filteredPoints.sorted(by: { $0.timestamp < $1.timestamp }).last
    }

    private var peakPoint: CodexHistoryDataPoint? {
        filteredPoints.max(by: { $0.primaryPercent < $1.primaryPercent })
    }

    var body: some View {
        CodexSectionCard(title: "Recent Activity", subtitle: "Compact window history from the last 6 hours", surfaceColor: CodexTelemetryTheme.panel) {
            VStack(alignment: .leading, spacing: 10) {
                if filteredPoints.isEmpty {
                    Text("No history yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CodexTelemetryTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    chart
                    summaryRail
                }
            }
        }
    }

    private var chart: some View {
        let values = filteredPoints.map { Double($0.primaryPercent) }
        let minValue = values.min() ?? 0
        let maxValue = max(values.max() ?? 1, minValue + 1)
        let domainMax = maxValue + max((maxValue - minValue) * 0.15, 8)

        return Chart {
            ForEach(filteredPoints) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.primaryPercent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [CodexTelemetryTheme.teal.opacity(0.25), CodexTelemetryTheme.teal.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.primaryPercent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [CodexTelemetryTheme.mint, CodexTelemetryTheme.lime],
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
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.white.opacity(0.10))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisValueLabel()
                    .foregroundStyle(CodexTelemetryTheme.tertiaryText)
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
                        colors: [CodexTelemetryTheme.chartTop, CodexTelemetryTheme.chartBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CodexTelemetryTheme.edge, lineWidth: 1)
        )
    }

    private var summaryRail: some View {
        HStack(spacing: 10) {
            metricPill(title: "Latest", value: latestPoint.map { "\($0.primaryPercent)%" } ?? "0%")
            metricPill(title: "Peak", value: peakPoint.map { "\($0.primaryPercent)%" } ?? "0%")
            metricPill(title: "Samples", value: "\(filteredPoints.count)")
        }
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(CodexTelemetryTheme.tertiaryText)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(CodexTelemetryTheme.primaryText)
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

struct CodexTabView: View {
    @ObservedObject var codexService: CodexService
    @ObservedObject var codexAuthManager: CodexAuthManager
    @ObservedObject var historyService: CodexHistoryService
    @ObservedObject var statsService: CodexSessionStatsService
    @EnvironmentObject private var codexTokenWarden: CodexTokenWarden
    let timeZone: TimeZone
    var providerStatus: ProviderStatusService.StatusInfo?
    var forceEmptyState: Bool = false
    var onOpenAnalytics: () -> Void
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        if forceEmptyState || !codexAuthManager.isAuthenticated {
            signInView
        } else {
            authenticatedView
        }
    }

    private var authenticatedView: some View {
        let codexData = codexService.codexData

        return VStack(alignment: .leading, spacing: 10) {
            header(planType: codexData.planType)

            if codexService.error == .fetchFailed {
                ErrorBannerView(message: "Failed to fetch Codex data") {
                    Task { await codexService.fetch() }
                }
            } else if case .rateLimited = codexService.error {
                ErrorBannerView(message: "Rate limited — retrying", retryDate: codexService.retryDate)
            } else if let account = codexAuthManager.activeAccount, codexTokenWarden.requiresManualSignIn(account) {
                tokenExpiredBanner
            }

            if let status = providerStatus, status.indicator != "none" {
                ProviderStatusBannerView(status: status)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                CodexHeroView(
                    data: codexData,
                    timeZone: timeZone,
                    pace: UsagePace.calculate(
                        usagePercent: codexData.primaryPercent,
                        resetsAt: codexData.primaryResetAt,
                        windowDurationHours: 5.0,
                        now: context.date
                    ),
                    now: context.date
                )
            }

            CodexLimitsView(rows: limitRows(from: codexData))
            CodexControlPlaneView(codexAuthManager: codexAuthManager)
            if let insight {
                CodexInsightView(insight: insight)
            }
            CodexFooterView(
                fetchedAt: codexData.fetchedAt,
                isStale: codexService.isStale,
                onOpenAnalytics: onOpenAnalytics,
                onRefresh: onRefresh,
                onOpenSettings: onOpenSettings
            )
        }
    }

    private func header(planType: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(CodexTelemetryTheme.primaryText)
                Text("Control Plane")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)
            }

            Spacer()

            if !planType.isEmpty {
                CodexBadge(text: cleanedPlanName(planType), color: CodexTelemetryTheme.mint)
            }
        }
    }

    private func limitRows(from data: CodexUsageData) -> [CodexLimitRow] {
        var rows = [
            CodexLimitRow(
                id: "weekly",
                icon: "calendar",
                title: "7-Day Usage",
                subtitle: "Longer running capacity",
                percentage: data.secondaryPercent,
                detail: ResetTimeFormatter.format(data.secondaryResetAt, style: .dayTime, timeZone: timeZone) ?? "No reset"
            )
        ]

        if data.codeReviewPercent > 0 {
            rows.append(
                CodexLimitRow(
                    id: "code-review",
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Code Review",
                    subtitle: "Dedicated review quota",
                    percentage: data.codeReviewPercent,
                    detail: "Dedicated lane"
                )
            )
        }

        return rows
    }

    private func cleanedPlanName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private var insight: CodexInsight? {
        if let topModel = statsService.topModel, statsService.totalTokens > 0 {
            let share = Int(round(Double(topModel.tokens) / Double(max(statsService.totalTokens, 1)) * 100))
            return CodexInsight(
                icon: "terminal",
                title: "\(topModel.name) is carrying most Codex usage",
                detail: "\(share)% of visible tokens in the current analytics range"
            )
        }

        if let topWorkspace = statsService.topWorkspace, topWorkspace.tokens > 0 {
            return CodexInsight(
                icon: "folder.fill.badge.gearshape",
                title: "\(topWorkspace.name) is your busiest Codex workspace",
                detail: "\(formatCompact(topWorkspace.tokens)) tokens across \(topWorkspace.sessions) sessions"
            )
        }

        if codexAuthManager.isLoadBalancingAvailable {
            let count = codexAuthManager.accounts.count
            return CodexInsight(
                icon: "arrow.triangle.branch",
                title: "Load balancing is active across \(count) Codex accounts",
                detail: "Open Analytics to inspect local session volume, models, and workspace mix"
            )
        }

        if codexService.codexData.primaryPercent >= codexService.codexData.secondaryPercent {
            return CodexInsight(
                icon: "bolt.badge.clock",
                title: "The 5-hour window is the current pressure point",
                detail: "\(codexService.codexData.primaryPercent)% used vs \(codexService.codexData.secondaryPercent)% of the 7-day bank"
            )
        }

        return CodexInsight(
            icon: "chart.xyaxis.line",
            title: "Codex analytics is ready when you are",
            detail: "Open Analytics to inspect local sessions, daily traffic, and model usage from ~/.codex"
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

    private var signInView: some View {
        CodexSectionCard(title: "Codex Access", subtitle: "Sign in to monitor runtime and routing telemetry", surfaceColor: CodexTelemetryTheme.panelRaised) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CodexTelemetryTheme.jade.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image("codex")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .foregroundColor(CodexTelemetryTheme.mint)
                }

                VStack(spacing: 4) {
                    Text("Control plane offline")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(CodexTelemetryTheme.primaryText)
                    Text("Connect your ChatGPT account to track 5-hour usage, weekly capacity, and proxy routing health.")
                        .font(.system(size: 11))
                        .foregroundColor(CodexTelemetryTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    codexAuthManager.openLoginWindow()
                } label: {
                    Text("Sign in with ChatGPT")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.82))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(CodexTelemetryTheme.mint)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(codexAuthManager.isLoggingIn)

                if codexAuthManager.isLoggingIn {
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                        Text("Waiting for login...")
                            .font(.system(size: 10))
                            .foregroundColor(CodexTelemetryTheme.secondaryText)
                    }
                }

                if let error = codexAuthManager.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var tokenExpiredBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 11))
            Text("Session expired — sign in again")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Spacer()
            Button("Sign in") {
                codexAuthManager.openLoginWindow()
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .foregroundColor(.orange)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }
}
