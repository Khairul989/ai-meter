import SwiftUI

struct ClaudeTabView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var statsService: ClaudeCodeStatsService
    let timeZone: TimeZone
    var planName: String?

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
                    Spacer()
                }
                .accessibilityElement(children: .combine)

                if service.error != nil && service.error != .noCredentials {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text("Failed to fetch usage data")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                ModelUsageView(statsService: statsService)
                TrendChartView(statsService: statsService)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    UsageCardView(
                        icon: "timer",
                        title: "Session",
                        subtitle: "5h sliding window",
                        percentage: data.fiveHour.utilization,
                        resetText: ResetTimeFormatter.format(
                            data.fiveHour.resetsAt,
                            style: .countdown,
                            timeZone: timeZone,
                            now: context.date
                        )
                    )
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
                        resetText: nil
                    )
                }
            }
    }
}
