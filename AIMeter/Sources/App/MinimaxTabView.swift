import SwiftUI
import AppKit
import Charts

private enum MinimaxTelemetryTheme {
    static let panel = Color(red: 0.16, green: 0.12, blue: 0.14)
    static let panelRaised = Color(red: 0.20, green: 0.15, blue: 0.17)
    static let heroTop = Color(red: 0.30, green: 0.10, blue: 0.13)
    static let heroBottom = Color(red: 0.16, green: 0.08, blue: 0.10)
    static let edge = Color.white.opacity(0.08)
    static let strongEdge = Color.white.opacity(0.14)
    static let primaryText = Color.white
    static let secondaryText = Color(red: 0.83, green: 0.77, blue: 0.80)
    static let tertiaryText = Color(red: 0.64, green: 0.58, blue: 0.61)
    static let magenta = Color(red: 0.97, green: 0.31, blue: 0.52)
    static let chartTop = Color(red: 0.22, green: 0.09, blue: 0.14)
    static let chartBottom = Color(red: 0.12, green: 0.06, blue: 0.09)
    static let linePrimary = Color(red: 0.98, green: 0.42, blue: 0.60)
    static let lineSecondary = Color(red: 1.00, green: 0.62, blue: 0.74)
}

private struct MinimaxSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let surfaceColor: Color
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, surfaceColor: Color = MinimaxTelemetryTheme.panel, @ViewBuilder content: () -> Content) {
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
                    .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.8)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(MinimaxTelemetryTheme.tertiaryText)
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
                .stroke(MinimaxTelemetryTheme.edge, lineWidth: 1)
        )
    }
}

private struct MinimaxHeaderView: View {
    let accountCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MiniMax")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(MinimaxTelemetryTheme.primaryText)

                Text("Model Quota Grid")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)
            }

            Spacer(minLength: 8)

            Text("\(accountCount) acct")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

private struct MinimaxHeroView: View {
    let data: MinimaxUsageData

    private var highestInterval: Int {
        data.highestIntervalPercent
    }

    private var topModelName: String {
        guard let model = data.models.max(by: { $0.intervalPercent < $1.intervalPercent }) else {
            return "No model"
        }
        return model.displayName
    }

    private var intervalTone: Color {
        UsageColor.forUtilization(highestInterval)
    }

    private var intervalRiskText: String {
        UsageColor.levelDescription(highestInterval)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Interval Telemetry")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.9)

                Text("\(highestInterval)%")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(intervalTone)

                Text("Top: \(topModelName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                    .lineLimit(1)

                Text(intervalRiskText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(intervalTone)
                    .textCase(.uppercase)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(intervalTone.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if let nextReset = data.nextResetAt,
                   let resetText = ResetTimeFormatter.format(nextReset, style: .dateTime) {
                    Text("Reset \(resetText)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MinimaxDialGauge(percentage: highestInterval)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [MinimaxTelemetryTheme.heroTop, MinimaxTelemetryTheme.heroBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MinimaxTelemetryTheme.strongEdge, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MinimaxTelemetryTheme.magenta)
                .frame(width: 48, height: 3)
                .padding(.top, 1)
                .padding(.leading, 14)
        }
    }

}

private struct MinimaxDialGauge: View {
    let percentage: Int
    private let segmentCount = 72

    private var progress: Double {
        Double(min(max(percentage, 0), 100)) / 100.0
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(MinimaxTelemetryTheme.edge, lineWidth: 10)

            ForEach(0..<segmentCount, id: \.self) { index in
                let start = Double(index) / Double(segmentCount)
                let end = Double(index + 1) / Double(segmentCount)
                let visibleEnd = min(progress, end)

                if visibleEnd > start {
                    Circle()
                        .trim(from: start, to: visibleEnd)
                        .stroke(
                            UsageColor.forUtilization(Int(((start + visibleEnd) * 50).rounded())),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }

            Circle()
                .fill(Color.black.opacity(0.18))
                .padding(14)

            VStack(spacing: 3) {
                Text("INT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.7)
                Text("\(percentage)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(MinimaxTelemetryTheme.primaryText)
            }
        }
        .frame(width: 128, height: 128)
    }
}

private struct MinimaxLimitsView: View {
    let data: MinimaxUsageData

    private var highestWeeklyModel: MinimaxModelQuota? {
        data.models.max(by: { $0.weeklyPercent < $1.weeklyPercent })
    }

    var body: some View {
        MinimaxSectionCard(title: "Limit Bank", subtitle: "Weekly pressure across models", surfaceColor: MinimaxTelemetryTheme.panelRaised) {
            VStack(spacing: 10) {
                if let model = highestWeeklyModel {
                    limitRow(
                        icon: "calendar.badge.clock",
                        title: "Weekly Peak",
                        subtitle: model.displayName,
                        percentage: model.weeklyPercent,
                        detail: "\(model.weeklyUsed)/\(model.weeklyTotal)"
                    )
                }
            }
        }
    }

    private func limitRow(icon: String, title: String, subtitle: String, percentage: Int, detail: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(UsageColor.forUtilization(percentage).opacity(0.14))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(UsageColor.forUtilization(percentage))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MinimaxTelemetryTheme.primaryText)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(MinimaxTelemetryTheme.tertiaryText)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(percentage)%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(UsageColor.forUtilization(percentage))
                    Text(detail)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                }
            }

            ProgressBarView(percentage: percentage, height: 5)
                .frame(height: 5)
        }
    }
}

private struct MinimaxRecentActivityView: View {
    let dataPoints: [MinimaxHistoryDataPoint]

    private var filteredPoints: [MinimaxHistoryDataPoint] {
        let cutoff = Date().addingTimeInterval(-QuotaTimeRange.hour6.interval)
        return dataPoints.filter { $0.timestamp >= cutoff }
    }

    private var latestPoint: MinimaxHistoryDataPoint? {
        filteredPoints.sorted(by: { $0.timestamp < $1.timestamp }).last
    }

    private var peakPoint: MinimaxHistoryDataPoint? {
        filteredPoints.max(by: { $0.intervalPercent < $1.intervalPercent })
    }

    var body: some View {
        MinimaxSectionCard(title: "Recent Activity", subtitle: "Compact interval history from the last 6 hours") {
            VStack(alignment: .leading, spacing: 10) {
                if filteredPoints.isEmpty {
                    Text("No history yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    chart
                    summaryRail
                }
            }
        }
    }

    private var chart: some View {
        let values = filteredPoints.map { Double($0.intervalPercent) }
        let minValue = values.min() ?? 0
        let maxValue = max(values.max() ?? 1, minValue + 1)
        let domainMax = max(maxValue + max((maxValue - minValue) * 0.15, 8), 100)

        return Chart {
            ForEach(filteredPoints) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.intervalPercent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [MinimaxTelemetryTheme.linePrimary.opacity(0.25), MinimaxTelemetryTheme.linePrimary.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.intervalPercent)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [MinimaxTelemetryTheme.linePrimary, MinimaxTelemetryTheme.lineSecondary],
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
                    .foregroundStyle(MinimaxTelemetryTheme.tertiaryText)
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
                        colors: [MinimaxTelemetryTheme.chartTop, MinimaxTelemetryTheme.chartBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MinimaxTelemetryTheme.edge, lineWidth: 1)
        )
    }

    private var summaryRail: some View {
        HStack(spacing: 10) {
            metricPill(title: "Latest", value: latestPoint.map { "\($0.intervalPercent)%" } ?? "0%")
            metricPill(title: "Peak", value: peakPoint.map { "\($0.intervalPercent)%" } ?? "0%")
            metricPill(title: "Samples", value: "\(filteredPoints.count)")
        }
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(MinimaxTelemetryTheme.tertiaryText)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(MinimaxTelemetryTheme.primaryText)
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

private struct MinimaxFooterView: View {
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
                        .foregroundColor(MinimaxTelemetryTheme.tertiaryText)
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
                    .foregroundColor(MinimaxTelemetryTheme.secondaryText)

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(MinimaxTelemetryTheme.secondaryText)
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

private struct MinimaxModelLane {
    let title: String
    let subtitle: String
    let models: [MinimaxModelQuota]
}

private struct MinimaxLaneView: View {
    let lane: MinimaxModelLane

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(lane.title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                    .textCase(.uppercase)
                Text(lane.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(MinimaxTelemetryTheme.tertiaryText)
            }

            if lane.models.isEmpty {
                Text("None")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MinimaxTelemetryTheme.tertiaryText)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(lane.models) { model in
                        let maxPercent = max(model.intervalPercent, model.weeklyPercent)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(UsageColor.forUtilization(maxPercent))
                                .frame(width: 5, height: 5)
                            Text(model.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(MinimaxTelemetryTheme.primaryText)
                            Text("\(maxPercent)%")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
                    }
                }
            }
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MinimaxTabView: View {
    @ObservedObject var minimaxService: MinimaxService
    @ObservedObject var historyService: MinimaxHistoryService
    @EnvironmentObject private var apiKeyAuthManagers: APIKeyAuthManagers
    @State private var expandedModels: Set<String> = []
    var forceEmptyState: Bool = false
    var onKeySaved: (() -> Void)? = nil
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void

    private var authManager: APIKeyAuthManager { apiKeyAuthManagers.minimax }

    var body: some View {
        if forceEmptyState || minimaxService.error == .noKey {
            ProviderAPIKeyEmptyStateView(
                providerName: "MiniMax",
                iconSystemName: "bolt.badge.clock",
                iconAssetName: "minimax",
                headline: "MiniMax quota grid offline",
                subtitle: "Connect your MiniMax API key to track interval and weekly model limits.",
                placeholder: "MINIMAX_API_KEY…",
                accentColor: ProviderTheme.minimax.accentColor
            ) { key in
                authManager.addAccount(label: "Default", apiKey: key)
                onKeySaved?()
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                    MinimaxHeaderView(accountCount: authManager.accounts.count)

                    if authManager.accounts.count > 1 {
                        accountSwitcher
                    }
                    if case .fetchFailed = minimaxService.error {
                        ErrorBannerView(message: "Failed to fetch MiniMax data") {
                            Task { await minimaxService.fetch() }
                        }
                    }
                    if case .rateLimited = minimaxService.error {
                        ErrorBannerView(message: "Rate limited — retrying", retryDate: minimaxService.retryDate)
                    }

                    MinimaxHeroView(data: minimaxService.minimaxData)
                    MinimaxLimitsView(data: minimaxService.minimaxData)

                    MinimaxSectionCard(title: "Interval Risk Lanes", subtitle: "Models grouped by highest interval pressure", surfaceColor: MinimaxTelemetryTheme.panelRaised) {
                        VStack(alignment: .leading, spacing: 10) {
                            MinimaxLaneView(lane: criticalLane)
                            Divider().overlay(Color.white.opacity(0.05))
                            MinimaxLaneView(lane: activeLane)
                            Divider().overlay(Color.white.opacity(0.05))
                            MinimaxLaneView(lane: healthyLane)
                        }
                    }

                    MinimaxSectionCard(title: "Model Bank", subtitle: "Drill into model-level interval and weekly usage") {
                        VStack(spacing: 0) {
                            ForEach(sortedModels) { model in
                                DisclosureGroup(isExpanded: isExpanded(model.modelName)) {
                                    VStack(spacing: 8) {
                                        UsageCardView(
                                            icon: "waveform.path",
                                            title: "Interval",
                                            subtitle: "\(model.intervalUsed)/\(model.intervalTotal) used",
                                            percentage: model.intervalPercent,
                                            resetText: ResetTimeFormatter.format(model.resetsAt, style: .countdown),
                                            accentColor: ProviderTheme.minimax.accentColor
                                        )

                                        UsageCardView(
                                            icon: "calendar.badge.clock",
                                            title: "Weekly",
                                            subtitle: "\(model.weeklyUsed)/\(model.weeklyTotal) used",
                                            percentage: model.weeklyPercent,
                                            resetText: ResetTimeFormatter.format(model.weeklyResetsAt, style: .dayTime),
                                            accentColor: ProviderTheme.minimax.accentColor
                                        )
                                    }
                                    .padding(.top, 6)
                                    .padding(.bottom, 2)
                                } label: {
                                    modelHeader(model)
                                }
                                .padding(.vertical, 6)

                                if model.id != sortedModels.last?.id {
                                    Divider().overlay(Color.white.opacity(0.05))
                                }
                            }
                        }
                    }

                        MinimaxRecentActivityView(dataPoints: historyService.history.dataPoints)
                    }
                }
                MinimaxFooterView(
                    fetchedAt: minimaxService.minimaxData.fetchedAt,
                    isStale: minimaxService.isStale,
                    onRefresh: onRefresh,
                    onOpenSettings: onOpenSettings
                )
            }
            .frame(minHeight: 680)
            .onAppear {
                updateExpandedModels()
            }
            .onChange(of: minimaxService.minimaxData.models, initial: false) { _, _ in
                updateExpandedModels()
            }
        }
    }

    private func isExpanded(_ modelName: String) -> Binding<Bool> {
        Binding(
            get: { expandedModels.contains(modelName) },
            set: {
                if $0 {
                    expandedModels.insert(modelName)
                } else {
                    expandedModels.remove(modelName)
                }
            }
        )
    }

    private func maxPercent(for model: MinimaxModelQuota) -> Int {
        max(model.intervalPercent, model.weeklyPercent)
    }

    private var sortedModels: [MinimaxModelQuota] {
        minimaxService.minimaxData.models.sorted {
            let lhs = maxPercent(for: $0)
            let rhs = maxPercent(for: $1)
            if lhs == rhs {
                return $0.modelName.localizedCaseInsensitiveCompare($1.modelName) == .orderedAscending
            }
            return lhs > rhs
        }
    }

    private var criticalLane: MinimaxModelLane {
        let models = sortedModels.filter { $0.intervalPercent >= 80 }
        return MinimaxModelLane(title: "At Risk", subtitle: "80%+", models: models)
    }

    private var activeLane: MinimaxModelLane {
        let models = sortedModels.filter {
            let value = $0.intervalPercent
            return value >= 50 && value < 80
        }
        return MinimaxModelLane(title: "Active", subtitle: "50-79%", models: models)
    }

    private var healthyLane: MinimaxModelLane {
        let models = sortedModels.filter { $0.intervalPercent < 50 }
        return MinimaxModelLane(title: "Healthy", subtitle: "<50%", models: models)
    }

    private func modelHeader(_ model: MinimaxModelQuota) -> some View {
        HStack(spacing: 8) {
            Text(model.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(MinimaxTelemetryTheme.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text("I")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(MinimaxTelemetryTheme.tertiaryText)
                miniBar(value: model.intervalPercent)
                    .frame(width: 44)
                Text("W")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(MinimaxTelemetryTheme.tertiaryText)
                miniBar(value: model.weeklyPercent)
                    .frame(width: 44)
            }

            Text("\(maxPercent(for: model))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(UsageColor.forUtilization(maxPercent(for: model)))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }

    private func miniBar(value: Int) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.10))
                .frame(height: 4)

            UsageColor.utilizationGradient
                .mask(alignment: .leading) {
                    Capsule()
                        .frame(width: max(4, 44 * CGFloat(value) / 100), height: 4)
                }
        }
    }

    private func updateExpandedModels() {
        let ordered = sortedModels
        let active = Set(
            ordered
                .filter { maxPercent(for: $0) >= 80 }
                .map(\.modelName)
        )
        let newModels = Set(ordered.map(\.modelName))
        let toAdd: Set<String>
        if active.isEmpty {
            toAdd = ordered.first.map { [$0.modelName] }.map(Set.init) ?? []
        } else {
            toAdd = active
        }
        expandedModels = expandedModels.intersection(newModels).union(toAdd)
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
                HStack(spacing: 4) {
                    Text(authManager.activeAccount?.label ?? "")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
    }
}
