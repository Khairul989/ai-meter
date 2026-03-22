import SwiftUI

private struct SessionPaceView: View {
    let pace: UsagePace.Result

    private let paceHelpText = "Pace shows whether you're using quota faster or slower than an ideal steady rate across the 5-hour window. Green means you're on track or have plenty left. Yellow means slightly fast. Red means you may run out before the window resets."

    private var paceColor: Color {
        switch pace.stage {
        case .farBehind, .behind, .slightlyBehind, .onTrack:
            return .green
        case .slightlyAhead:
            return .yellow
        case .ahead, .farAhead:
            return .red
        }
    }

    private var label: String {
        let delta = pace.deltaPercent
        let sign = delta >= 0 ? "+" : ""
        let deltaStr = String(format: "%@%.0f%%", sign, delta)
        var text = "Pace: \(pace.stage.rawValue)"
        // Only show delta when meaningfully off-track
        if abs(delta) >= 5 {
            text += " (\(deltaStr))"
        }
        if let eta = pace.etaDescription {
            text += " · \(eta)"
        }
        return text
    }

    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(paceColor)
                    .padding(.horizontal, 4)
                    .accessibilityLabel(label)
                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            if showHelp {
                Text(paceHelpText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ClaudeTabView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var statsService: ClaudeCodeStatsService
    let timeZone: TimeZone
    var planName: String?
    var providerStatus: ProviderStatusService.StatusInfo?

    var body: some View {
        let data = service.usageData
        VStack(spacing: 6) {
                HStack {
                    Text("Claude")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    if let plan = planName {
                        Text(plan)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        if PeakHoursHelper.isPromotionActive(now: context.date) {
                            let doubled = PeakHoursHelper.isDoubledUsage(now: context.date)
                            Text(doubled ? "2× Limit" : "Peak Hours")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(doubled ? .green : .orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((doubled ? Color.green : Color.orange).opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)

                if service.error != nil && service.error != .noCredentials {
                    ErrorBannerView(message: "Failed to fetch usage data") {
                        Task { await service.fetch() }
                    }
                }

                if let status = providerStatus, status.indicator != "none" {
                    ProviderStatusBannerView(status: status)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        UsageCardView(
                            icon: "timer",
                            title: "Session",
                            subtitle: PeakHoursHelper.isDoubledUsage(now: context.date) ? "5h window · 2× limit" : "5h sliding window",
                            percentage: data.fiveHour.utilization,
                            resetText: ResetTimeFormatter.format(
                                data.fiveHour.resetsAt,
                                style: .countdown,
                                timeZone: timeZone,
                                now: context.date
                            ),
                            accentColor: ProviderTheme.claude.accentColor,
                            isPrimary: true
                        )
                        if let pace = UsagePace.calculate(
                            usagePercent: data.fiveHour.utilization,
                            resetsAt: data.fiveHour.resetsAt,
                            windowDurationHours: 5.0,
                            now: context.date
                        ) {
                            SessionPaceView(pace: pace)
                        }
                    }
                }
                UsageCardView(
                    icon: "chart.bar.fill",
                    title: "Weekly",
                    subtitle: "Opus + Sonnet + Haiku",
                    percentage: data.sevenDay.utilization,
                    resetText: ResetTimeFormatter.format(data.sevenDay.resetsAt, style: .dayTime, timeZone: timeZone)
                )
                if let sonnet = data.sevenDaySonnet {
                    UsageCardView(
                        icon: "sparkles",
                        title: "Sonnet",
                        subtitle: "Dedicated limit",
                        percentage: sonnet.utilization,
                        resetText: ResetTimeFormatter.format(sonnet.resetsAt, style: .dayTime, timeZone: timeZone)
                    )
                }
                if let credits = data.extraCredits {
                    UsageCardView(
                        icon: "creditcard.fill",
                        title: "Extra Credits",
                        subtitle: String(format: "$%.2f / $%.2f", credits.used / 100, credits.limit / 100),
                        percentage: credits.utilization,
                        resetText: nil,
                        isCompact: true
                    )
                }

                ModelUsageView(statsService: statsService)
                TrendChartView(statsService: statsService)
            }
    }
}
