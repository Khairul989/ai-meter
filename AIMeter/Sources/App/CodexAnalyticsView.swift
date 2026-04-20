import AppKit
import SwiftUI
import Charts

private struct CodexAnalyticsSummaryItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let accent: Color
}

struct CodexAnalyticsView: View {
    @ObservedObject var statsService: CodexSessionStatsService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                CodexAnalyticsSummaryGrid(items: summaryItems)
                CodexAnalyticsDistributionPanel(
                    title: "Model Distribution",
                    subtitle: "Token share, prompts, and session count by model",
                    buckets: statsService.models,
                    emptyMessage: "No model activity in this range",
                    tintPalette: [CodexTelemetryTheme.mint, CodexTelemetryTheme.lime, CodexTelemetryTheme.teal, .yellow, .orange]
                )
                CodexAnalyticsDistributionPanel(
                    title: "Workspace Footprint",
                    subtitle: "Where Codex activity is happening across your local projects",
                    buckets: Array(statsService.workspaces.prefix(6)),
                    emptyMessage: "No workspace activity in this range",
                    tintPalette: [CodexTelemetryTheme.teal, CodexTelemetryTheme.mint, .blue, .green, .gray]
                )
                CodexAnalyticsEffortPanel(buckets: statsService.efforts)
                CodexAnalyticsTrendPanel(statsService: statsService)
                CodexAnalyticsSessionsPanel(sessions: statsService.topSessions)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(22)
        }
        .frame(minWidth: 620, minHeight: 560)
        .background(
            LinearGradient(
                colors: [CodexTelemetryTheme.chartTop, CodexTelemetryTheme.chartBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .task {
            await statsService.loadIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Analytics")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(CodexTelemetryTheme.primaryText)
                Text("Local session telemetry from ~/.codex threads and prompt history")
                    .font(.system(size: 12))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)

                if let loadError = statsService.loadError, statsService.sessions.isEmpty {
                    Text(loadError)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    CodexAnalyticsRangePicker(
                        options: CodexAnalyticsRange.allCases,
                        selection: statsService.selectedRange,
                        onSelect: { statsService.selectedRange = $0 }
                    )

                    Button {
                        Task { await statsService.load(force: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(CodexTelemetryTheme.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(CodexTelemetryTheme.panelRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
            }
        }
    }

    private var summaryItems: [CodexAnalyticsSummaryItem] {
        [
            CodexAnalyticsSummaryItem(
                id: "tokens",
                title: "Range Tokens",
                value: formatCompact(statsService.totalTokens),
                detail: statsService.selectedRange.rawValue,
                accent: CodexTelemetryTheme.mint
            ),
            CodexAnalyticsSummaryItem(
                id: "sessions",
                title: "Sessions",
                value: "\(statsService.totalSessions)",
                detail: statsService.totalSessions == 0 ? "No sessions" : "\(formatCompact(statsService.averageTokensPerSession)) avg tok / session",
                accent: CodexTelemetryTheme.lime
            ),
            CodexAnalyticsSummaryItem(
                id: "prompts",
                title: "Prompts",
                value: formatCompact(statsService.totalPrompts),
                detail: statsService.totalPrompts == 0 ? "No prompt history" : "\(statsService.averagePromptsPerSession) avg prompts / session",
                accent: CodexTelemetryTheme.teal
            ),
            CodexAnalyticsSummaryItem(
                id: "focus",
                title: "Lead Stack",
                value: statsService.topModel?.name ?? "No model",
                detail: statsService.topWorkspace.map { "Top workspace: \($0.name)" } ?? "Open Codex to start logging sessions",
                accent: .white
            )
        ]
    }

    private var statusText: String {
        if statsService.isLoading {
            return "Refreshing local Codex telemetry"
        }
        guard let lastLoadedAt = statsService.lastLoadedAt else {
            return "No analytics snapshot yet"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: lastLoadedAt, relativeTo: .now))"
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

private struct CodexAnalyticsSummaryGrid: View {
    let items: [CodexAnalyticsSummaryItem]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(summaryRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row) { item in
                        summaryCard(item)
                    }

                    if row.count == 1 {
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var summaryRows: [[CodexAnalyticsSummaryItem]] {
        stride(from: 0, to: items.count, by: 2).map { start in
            Array(items[start..<min(start + 2, items.count)])
        }
    }

    private func summaryCard(_ item: CodexAnalyticsSummaryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(CodexTelemetryTheme.tertiaryText)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(item.value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(CodexTelemetryTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(item.detail)
                .font(.system(size: 11))
                .foregroundColor(CodexTelemetryTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.accent)
                .frame(width: 36, height: 3)
                .padding(.top, 1)
                .padding(.leading, 14)
        }
    }
}

private struct CodexAnalyticsPanel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.85)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(CodexTelemetryTheme.tertiaryText)
            }

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CodexTelemetryTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CodexTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct CodexAnalyticsRangePicker: View {
    let options: [CodexAnalyticsRange]
    let selection: CodexAnalyticsRange
    let onSelect: (CodexAnalyticsRange) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(selection == option ? CodexTelemetryTheme.primaryText : CodexTelemetryTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selection == option ? CodexTelemetryTheme.panelRaised : Color.clear)
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
                .stroke(CodexTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct CodexAnalyticsDistributionPanel: View {
    let title: String
    let subtitle: String
    let buckets: [CodexAnalyticsBucket]
    let emptyMessage: String
    let tintPalette: [Color]

    var body: some View {
        CodexAnalyticsPanel(title: title, subtitle: subtitle) {
            if buckets.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    rail
                    VStack(spacing: 10) {
                        ForEach(Array(buckets.prefix(6).enumerated()), id: \.element.id) { index, bucket in
                            CodexAnalyticsBucketRow(
                                bucket: bucket,
                                share: share(for: bucket),
                                color: tintPalette[index % max(tintPalette.count, 1)]
                            )
                        }
                    }
                }
            }
        }
    }

    private var totalTokens: Int {
        buckets.reduce(0) { $0 + $1.tokens }
    }

    private var rail: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(buckets.prefix(6).enumerated()), id: \.element.id) { index, bucket in
                    let fraction = max(CGFloat(bucket.tokens) / CGFloat(max(totalTokens, 1)), 0)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tintPalette[index % max(tintPalette.count, 1)])
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

    private func share(for bucket: CodexAnalyticsBucket) -> Int {
        guard totalTokens > 0 else { return 0 }
        return Int((Double(bucket.tokens) / Double(totalTokens) * 100).rounded())
    }
}

private struct CodexAnalyticsBucketRow: View {
    let bucket: CodexAnalyticsBucket
    let share: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(CodexTelemetryTheme.primaryText)
                    Text("\(share)% of visible tokens")
                        .font(.system(size: 10))
                        .foregroundColor(CodexTelemetryTheme.tertiaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCompact(bucket.tokens))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(CodexTelemetryTheme.primaryText)
                    Text("\(bucket.sessions) sess  •  \(bucket.prompts) prompts")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(CodexTelemetryTheme.secondaryText)
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
                .fill(CodexTelemetryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CodexTelemetryTheme.edge, lineWidth: 1)
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

private struct CodexAnalyticsEffortPanel: View {
    let buckets: [CodexAnalyticsBucket]

    var body: some View {
        CodexAnalyticsPanel(title: "Reasoning Mix", subtitle: "Session and token distribution by reasoning effort") {
            if buckets.isEmpty {
                Text("No effort metadata in this range")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                HStack(spacing: 10) {
                    ForEach(Array(buckets.prefix(4))) { bucket in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bucket.name)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(CodexTelemetryTheme.tertiaryText)
                                .textCase(.uppercase)
                            Text(formatCompact(bucket.tokens))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(CodexTelemetryTheme.primaryText)
                            Text("\(bucket.sessions) sessions • \(bucket.prompts) prompts")
                                .font(.system(size: 10))
                                .foregroundColor(CodexTelemetryTheme.secondaryText)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(CodexTelemetryTheme.panelRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(CodexTelemetryTheme.edge, lineWidth: 1)
                        )
                    }
                }
            }
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

private struct CodexAnalyticsTrendPanel: View {
    @ObservedObject var statsService: CodexSessionStatsService

    var body: some View {
        CodexAnalyticsPanel(title: "Daily Traffic", subtitle: "Session volume with token-weighted trend across your local Codex work") {
            if statsService.dailyPoints.isEmpty {
                Text("No daily activity yet in this range")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    chart
                    summaryStrip
                }
            }
        }
    }

    private var chart: some View {
        let points = statsService.dailyPoints
        let maxSessions = max(points.map(\.sessions).max() ?? 0, 1)
        let maxTokens = max(points.map(\.tokens).max() ?? 0, 1)

        return Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Sessions", point.sessions)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [CodexTelemetryTheme.mint.opacity(0.55), CodexTelemetryTheme.lime.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(3)
            }

            ForEach(points) { point in
                let scaledTokens = Double(point.tokens) / Double(maxTokens) * Double(maxSessions)
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Tokens", scaledTokens)
                )
                .foregroundStyle(CodexTelemetryTheme.teal)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            ForEach(points) { point in
                let scaledTokens = Double(point.tokens) / Double(maxTokens) * Double(maxSessions)
                PointMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Tokens", scaledTokens)
                )
                .foregroundStyle(CodexTelemetryTheme.teal)
                .symbolSize(18)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(dayLabel(date))
                            .font(.system(size: 8))
                            .foregroundColor(CodexTelemetryTheme.tertiaryText)
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
                        Text("\(v)")
                            .font(.system(size: 8))
                            .foregroundColor(CodexTelemetryTheme.tertiaryText)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.05))
            }
        }
        .chartYScale(domain: 0...maxSessions)
        .chartLegend(.hidden)
        .frame(height: 180)
        .chartPlotStyle { plot in
            plot
                .background(Color.white.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var summaryStrip: some View {
        let totalPrompts = statsService.dailyPoints.reduce(0) { $0 + $1.prompts }
        let topDay = statsService.dailyPoints.max(by: { $0.tokens < $1.tokens })

        return HStack(spacing: 10) {
            summaryPill(title: "Active Days", value: "\(statsService.activeDays)", accent: CodexTelemetryTheme.mint)
            summaryPill(title: "Total Prompts", value: formatCompact(totalPrompts), accent: CodexTelemetryTheme.primaryText)
            summaryPill(title: "Peak Day", value: topDay.map { formatCompact($0.tokens) } ?? "0", accent: CodexTelemetryTheme.teal)
        }
    }

    private func summaryPill(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(CodexTelemetryTheme.tertiaryText)
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
                .fill(CodexTelemetryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CodexTelemetryTheme.edge, lineWidth: 1)
        )
    }

    private var xAxisStride: Int {
        switch statsService.selectedRange {
        case .sevenDay: return 1
        case .fourteenDay: return 3
        case .thirtyDay: return 5
        case .allTime: return max(statsService.dailyPoints.count / 8, 7)
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

private struct CodexAnalyticsSessionsPanel: View {
    let sessions: [CodexSessionRecord]

    var body: some View {
        CodexAnalyticsPanel(title: "Top Sessions", subtitle: "Largest local Codex threads in the selected range") {
            if sessions.isEmpty {
                Text("No session data yet in this range")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                VStack(spacing: 10) {
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: CodexSessionRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CodexTelemetryTheme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    label(text: session.workspaceName)
                    label(text: session.modelDisplayName)
                    label(text: session.effortDisplayName)
                }

                Text("\(dateText(session.createdAt)) • \(session.promptCount) prompts • \(session.workspacePath)")
                    .font(.system(size: 10))
                    .foregroundColor(CodexTelemetryTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            Text(formatCompact(session.tokensUsed))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(CodexTelemetryTheme.mint)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CodexTelemetryTheme.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CodexTelemetryTheme.edge, lineWidth: 1)
        )
    }

    private func label(text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(CodexTelemetryTheme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mma"
        return formatter.string(from: date).lowercased()
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

final class CodexAnalyticsWindowController: NSWindowController {
    private static var instance: CodexAnalyticsWindowController?
    private static var hostingView: NSHostingView<CodexAnalyticsView>?

    static func show(statsService: CodexSessionStatsService) {
        if let existing = instance {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            hostingView?.rootView = CodexAnalyticsView(statsService: statsService)
            Task { await statsService.loadIfNeeded() }
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Analytics"
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.08, green: 0.10, blue: 0.10, alpha: 1.0)
        window.minSize = NSSize(width: 580, height: 500)

        let rootView = CodexAnalyticsView(statsService: statsService)
        let hostingView = NSHostingView(rootView: rootView)
        window.contentView = hostingView

        let controller = CodexAnalyticsWindowController(window: window)
        instance = controller
        Self.hostingView = hostingView

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            instance = nil
            Self.hostingView = nil
        }

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { await statsService.loadIfNeeded() }
    }
}
