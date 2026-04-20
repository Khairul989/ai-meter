import AppKit
import SwiftUI
import Charts

private struct ClaudeSessionAnalyticsSummary: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let accent: Color
}

struct ClaudeSessionAnalyticsView: View {
    @ObservedObject var statsService: ClaudeSessionStatsService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ClaudeSessionAnalyticsSummaryGrid(items: summaryItems)
                ClaudeSessionAnalyticsModelsPanel(statsService: statsService)
                ClaudeSessionAnalyticsDistributionPanel(
                    title: "Workspace Footprint",
                    subtitle: "Where Claude Code activity is happening across your local projects",
                    buckets: Array(statsService.workspaces.prefix(6)),
                    emptyMessage: "No workspace activity in this range",
                    tintPalette: [ClaudeTelemetryTheme.analyticsLine, .green, .blue, .mint, .gray]
                )
                ClaudeSessionAnalyticsRuntimePanel(
                    branches: Array(statsService.branches.prefix(5)),
                    versions: Array(statsService.versions.prefix(5))
                )
                ClaudeSessionAnalyticsTrendPanel(statsService: statsService)
                ClaudeSessionAnalyticsSessionsPanel(sessions: statsService.topSessions)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(22)
        }
        .frame(minWidth: 640, minHeight: 600)
        .background(
            LinearGradient(
                colors: [ClaudeTelemetryTheme.analyticsTop, ClaudeTelemetryTheme.analyticsBottom],
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
                Text("Claude Analytics")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(ClaudeTelemetryTheme.primaryText)
                Text("Session, workspace, model, and cache telemetry from ~/.claude/projects")
                    .font(.system(size: 12))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)

                if let loadError = statsService.loadError, statsService.totalSessions == 0 {
                    Text(loadError)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    ClaudeSessionAnalyticsRangePicker(
                        options: ClaudeAnalyticsRange.allCases,
                        selection: statsService.selectedRange,
                        onSelect: { statsService.selectedRange = $0 }
                    )

                    Button {
                        Task { await statsService.load(force: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ClaudeTelemetryTheme.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(ClaudeTelemetryTheme.panelRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
            }
        }
    }

    private var summaryItems: [ClaudeSessionAnalyticsSummary] {
        let topModel = statsService.topModel
        let share = {
            guard let topModel, statsService.totalVisibleTokens > 0 else { return 0 }
            return Int((Double(topModel.visibleTokens) / Double(statsService.totalVisibleTokens) * 100).rounded())
        }()

        return [
            ClaudeSessionAnalyticsSummary(
                id: "visible",
                title: "Visible Tokens",
                value: formatCompact(statsService.totalVisibleTokens),
                detail: "\(formatCompact(statsService.totalInputTokens)) in • \(formatCompact(statsService.totalOutputTokens)) out",
                accent: ClaudeTelemetryTheme.amber
            ),
            ClaudeSessionAnalyticsSummary(
                id: "sessions",
                title: "Sessions",
                value: "\(statsService.totalSessions)",
                detail: "\(statsService.averageAssistantTurnsPerSession) avg assistant turns / session",
                accent: ClaudeTelemetryTheme.analyticsLine
            ),
            ClaudeSessionAnalyticsSummary(
                id: "cache",
                title: "Cache Read",
                value: formatCompact(statsService.totalCacheReadTokens),
                detail: "\(statsService.cacheReadRatio)% of visible token volume",
                accent: .green
            ),
            ClaudeSessionAnalyticsSummary(
                id: "lead",
                title: "Lead Model",
                value: topModel?.name ?? "No model",
                detail: topModel == nil ? "No Claude activity in this range" : "\(share)% of visible usage",
                accent: topModel.map(modelColor(for:)) ?? ClaudeTelemetryTheme.secondaryText
            )
        ]
    }

    private var statusText: String {
        if statsService.isLoading {
            return "Refreshing Claude session telemetry"
        }
        guard let lastLoadedAt = statsService.lastLoadedAt else {
            return "No analytics snapshot yet"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: lastLoadedAt, relativeTo: .now))"
    }

    private func modelColor(for bucket: ClaudeAnalyticsBucket) -> Color {
        let lower = bucket.name.lowercased()
        if lower.contains("opus") { return .orange }
        if lower.contains("sonnet") { return .blue }
        if lower.contains("haiku") { return .green }
        return .gray
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

private struct ClaudeSessionAnalyticsSummaryGrid: View {
    let items: [ClaudeSessionAnalyticsSummary]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(summaryRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row) { item in
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
                                .minimumScaleFactor(0.75)
                            Text(item.detail)
                                .font(.system(size: 11))
                                .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
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

                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var summaryRows: [[ClaudeSessionAnalyticsSummary]] {
        stride(from: 0, to: items.count, by: 2).map { start in
            Array(items[start..<min(start + 2, items.count)])
        }
    }
}

private struct ClaudeSessionAnalyticsPanel<Content: View>: View {
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
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.85)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
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

private struct ClaudeSessionAnalyticsRangePicker: View {
    let options: [ClaudeAnalyticsRange]
    let selection: ClaudeAnalyticsRange
    let onSelect: (ClaudeAnalyticsRange) -> Void

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

private struct ClaudeSessionAnalyticsModelsPanel: View {
    @ObservedObject var statsService: ClaudeSessionStatsService

    var body: some View {
        ClaudeSessionAnalyticsPanel(
            title: "Model Distribution",
            subtitle: "Visible token mix plus cache leverage across Claude models"
        ) {
            if statsService.isLoading && statsService.models.isEmpty {
                Text("Reading Claude session logs…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else if statsService.models.isEmpty {
                Text("No Claude model activity in this range")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    rail
                    VStack(spacing: 10) {
                        ForEach(Array(statsService.models.prefix(6))) { bucket in
                            ClaudeSessionAnalyticsModelRow(
                                bucket: bucket,
                                share: share(for: bucket),
                                color: colorFor(bucket)
                            )
                        }
                    }
                }
            }
        }
    }

    private var rail: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(statsService.models.prefix(6))) { bucket in
                    let fraction = max(CGFloat(bucket.visibleTokens) / CGFloat(max(statsService.totalVisibleTokens, 1)), 0)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colorFor(bucket))
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

    private func share(for bucket: ClaudeAnalyticsBucket) -> Int {
        guard statsService.totalVisibleTokens > 0 else { return 0 }
        return Int((Double(bucket.visibleTokens) / Double(statsService.totalVisibleTokens) * 100).rounded())
    }

    private func colorFor(_ bucket: ClaudeAnalyticsBucket) -> Color {
        let lower = bucket.name.lowercased()
        if lower.contains("opus") { return .orange }
        if lower.contains("sonnet") { return .blue }
        if lower.contains("haiku") { return .green }
        return .gray
    }
}

private struct ClaudeSessionAnalyticsModelRow: View {
    let bucket: ClaudeAnalyticsBucket
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
                        .foregroundColor(ClaudeTelemetryTheme.primaryText)
                    Text("\(share)% of visible tokens")
                        .font(.system(size: 10))
                        .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCompact(bucket.visibleTokens))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(ClaudeTelemetryTheme.primaryText)
                    Text("\(formatCompact(bucket.cacheReadTokens)) cache read")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                }
            }

            HStack(spacing: 8) {
                statChip(text: "\(formatCompact(bucket.inputTokens)) in")
                statChip(text: "\(formatCompact(bucket.outputTokens)) out")
                statChip(text: "\(bucket.assistantTurns) turns")
                statChip(text: "\(bucket.toolUseTurns) tool")
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

    private func statChip(text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(ClaudeTelemetryTheme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

private struct ClaudeSessionAnalyticsDistributionPanel: View {
    let title: String
    let subtitle: String
    let buckets: [ClaudeAnalyticsBucket]
    let emptyMessage: String
    let tintPalette: [Color]

    var body: some View {
        ClaudeSessionAnalyticsPanel(title: title, subtitle: subtitle) {
            if buckets.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                                let fraction = max(CGFloat(bucket.visibleTokens) / CGFloat(max(totalTokens, 1)), 0)
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

                    VStack(spacing: 10) {
                        ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                            ClaudeSessionAnalyticsSimpleBucketRow(
                                bucket: bucket,
                                color: tintPalette[index % max(tintPalette.count, 1)],
                                share: share(for: bucket)
                            )
                        }
                    }
                }
            }
        }
    }

    private var totalTokens: Int {
        buckets.reduce(0) { $0 + $1.visibleTokens }
    }

    private func share(for bucket: ClaudeAnalyticsBucket) -> Int {
        guard totalTokens > 0 else { return 0 }
        return Int((Double(bucket.visibleTokens) / Double(totalTokens) * 100).rounded())
    }
}

private struct ClaudeSessionAnalyticsSimpleBucketRow: View {
    let bucket: ClaudeAnalyticsBucket
    let color: Color
    let share: Int

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ClaudeTelemetryTheme.primaryText)
                Text("\(bucket.sessions) sessions • \(share)% of visible tokens")
                    .font(.system(size: 10))
                    .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
            }

            Spacer()

            Text(formatCompact(bucket.visibleTokens))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(ClaudeTelemetryTheme.primaryText)
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

private struct ClaudeSessionAnalyticsRuntimePanel: View {
    let branches: [ClaudeAnalyticsBucket]
    let versions: [ClaudeAnalyticsBucket]

    var body: some View {
        ClaudeSessionAnalyticsPanel(
            title: "Runtime Footprint",
            subtitle: "Branch and Claude Code version distribution in the selected range"
        ) {
            HStack(alignment: .top, spacing: 10) {
                runtimeColumn(title: "Branches", buckets: branches)
                runtimeColumn(title: "Versions", buckets: versions)
            }
        }
    }

    private func runtimeColumn(title: String, buckets: [ClaudeAnalyticsBucket]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                .textCase(.uppercase)
                .tracking(0.8)

            if buckets.isEmpty {
                Text("No data")
                    .font(.system(size: 11))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(buckets) { bucket in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bucket.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(ClaudeTelemetryTheme.primaryText)
                                    .lineLimit(1)
                                Text("\(bucket.sessions) sess • \(bucket.assistantTurns) turns")
                                    .font(.system(size: 10))
                                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                            }
                            Spacer()
                            Text(formatCompact(bucket.visibleTokens))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(ClaudeTelemetryTheme.amberSoft)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(ClaudeTelemetryTheme.panelRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(ClaudeTelemetryTheme.edge, lineWidth: 1)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

private struct ClaudeSessionAnalyticsTrendPanel: View {
    @ObservedObject var statsService: ClaudeSessionStatsService

    var body: some View {
        ClaudeSessionAnalyticsPanel(
            title: "Daily Traffic",
            subtitle: "Prompt volume, assistant turns, and visible token trend in the selected range"
        ) {
            if statsService.dailyPoints.isEmpty {
                Text("No Claude activity yet in this range")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
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
        let maxTurns = max(points.map { max($0.assistantTurns, $0.userPrompts) }.max() ?? 0, 1)
        let maxTokens = max(points.map(\.visibleTokens).max() ?? 0, 1)

        return Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Prompts", point.userPrompts)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [ClaudeTelemetryTheme.amberSoft.opacity(0.6), ClaudeTelemetryTheme.amber.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(3)
            }

            ForEach(points) { point in
                let scaledTokens = Double(point.visibleTokens) / Double(maxTokens) * Double(maxTurns)
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Visible Tokens", scaledTokens)
                )
                .foregroundStyle(ClaudeTelemetryTheme.analyticsLine)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            ForEach(points) { point in
                let scaledTokens = Double(point.visibleTokens) / Double(maxTokens) * Double(maxTurns)
                PointMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Visible Tokens", scaledTokens)
                )
                .foregroundStyle(ClaudeTelemetryTheme.analyticsLine)
                .symbolSize(16)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride(for: points.count))) { value in
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
                        Text("\(v)")
                            .font(.system(size: 8))
                            .foregroundColor(ClaudeTelemetryTheme.tertiaryText)
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.05))
            }
        }
        .chartYScale(domain: 0...maxTurns)
        .chartLegend(.hidden)
        .frame(height: 190)
        .chartPlotStyle { plot in
            plot
                .background(Color.white.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            summaryPill(title: "User Prompts", value: formatCompact(statsService.totalUserPrompts), accent: ClaudeTelemetryTheme.amber)
            summaryPill(title: "Assistant Turns", value: formatCompact(statsService.totalAssistantTurns), accent: ClaudeTelemetryTheme.primaryText)
            summaryPill(title: "Tool Use", value: "\(statsService.toolUseRatio)% turns", accent: ClaudeTelemetryTheme.analyticsLine)
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

    private func xAxisStride(for count: Int) -> Int {
        switch count {
        case 0...7: return 1
        case 8...14: return 3
        case 15...30: return 5
        default: return max(count / 8, 7)
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

private struct ClaudeSessionAnalyticsSessionsPanel: View {
    let sessions: [ClaudeSessionRecord]

    var body: some View {
        ClaudeSessionAnalyticsPanel(
            title: "Top Sessions",
            subtitle: "Largest Claude Code sessions in the selected range"
        ) {
            if sessions.isEmpty {
                Text("No session data yet in this range")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
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

    private func sessionRow(_ session: ClaudeSessionRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ClaudeTelemetryTheme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    chip(text: session.workspaceName)
                    chip(text: session.primaryModelDisplayName)
                    chip(text: session.branchDisplayName)
                }

                Text("\(dateText(session.updatedAt)) • \(session.assistantTurns) turns • \(session.toolUseTurns) tool • \(session.versionDisplayName)")
                    .font(.system(size: 10))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCompact(session.visibleTokens))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(ClaudeTelemetryTheme.amber)
                Text("\(formatCompact(session.cacheReadTokens)) cache")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(ClaudeTelemetryTheme.secondaryText)
            }
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

    private func chip(text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(ClaudeTelemetryTheme.secondaryText)
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

final class ClaudeSessionAnalyticsWindowController: NSWindowController {
    private static var instance: ClaudeSessionAnalyticsWindowController?
    private static var hostingView: NSHostingView<ClaudeSessionAnalyticsView>?

    static func show(statsService: ClaudeSessionStatsService) {
        if let existing = instance {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            hostingView?.rootView = ClaudeSessionAnalyticsView(statsService: statsService)
            Task { await statsService.loadIfNeeded() }
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Analytics"
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        window.minSize = NSSize(width: 620, height: 560)

        let rootView = ClaudeSessionAnalyticsView(statsService: statsService)
        let hostingView = NSHostingView(rootView: rootView)
        window.contentView = hostingView

        let controller = ClaudeSessionAnalyticsWindowController(window: window)
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
