import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let data: UsageData
    let copilotData: CopilotUsageData?

    private var configuredTimeZone: TimeZone {
        let offset = UserDefaults(suiteName: SharedDefaults.suiteName)?.integer(forKey: "timezoneOffset") ?? 0
        return TimeZone(secondsFromGMT: offset * 3600) ?? .current
    }

    // Count of gauges to show (determines sizing)
    private var gaugeCount: Int {
        var count = 2 // Session + Weekly always shown
        if data.sevenDaySonnet != nil { count += 1 }
        if data.extraCredits != nil { count += 1 }
        if let copilot = copilotData, !copilot.premiumInteractions.unlimited { count += 1 }
        return count
    }

    private var overallHighestUtilization: Int {
        var values = [data.highestUtilization]
        if let copilot = copilotData {
            values.append(copilot.highestUtilization)
        }
        return values.max() ?? 0
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(UsageColor.forUtilization(overallHighestUtilization))
                    .frame(width: 6, height: 6)
                Text("AI Meter")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(updatedText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                gaugeColumn(
                    label: "Session",
                    limit: data.fiveHour,
                    resetStyle: .countdown
                )

                gaugeColumn(
                    label: "Weekly",
                    limit: data.sevenDay,
                    resetStyle: .dayTime
                )

                if let sonnet = data.sevenDaySonnet {
                    gaugeColumn(
                        label: "Sonnet",
                        limit: sonnet,
                        resetStyle: .dayTime
                    )
                }

                if let credits = data.extraCredits {
                    VStack(spacing: 4) {
                        CircularGaugeView(
                            percentage: credits.utilization,
                            lineWidth: gaugeLineWidth,
                            size: gaugeSize
                        )
                        Text("Credits")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                        Text(String(format: "$%.0f/$%.0f", credits.used / 100, credits.limit / 100))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }

                if let copilot = copilotData, !copilot.premiumInteractions.unlimited {
                    VStack(spacing: 4) {
                        CircularGaugeView(
                            percentage: copilot.premiumInteractions.utilization,
                            lineWidth: gaugeLineWidth,
                            size: gaugeSize
                        )
                        Text("Copilot")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                        if let resetText = ResetTimeFormatter.format(copilot.resetDate, style: .dayTime, timeZone: configuredTimeZone) {
                            Text(resetText)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var gaugeSize: CGFloat {
        gaugeCount > 3 ? 48 : 56
    }

    private var gaugeLineWidth: CGFloat {
        gaugeCount > 3 ? 4 : 5
    }

    private func gaugeColumn(label: String, limit: RateLimit, resetStyle: ResetTimeFormatter.Style) -> some View {
        VStack(spacing: 4) {
            CircularGaugeView(percentage: limit.utilization, lineWidth: gaugeLineWidth, size: gaugeSize)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
            if let resetText = ResetTimeFormatter.format(limit.resetsAt, style: resetStyle, timeZone: configuredTimeZone) {
                Text(resetText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var updatedText: String {
        let seconds = Int(Date().timeIntervalSince(data.fetchedAt))
        if seconds < 60 { return "< 1 min ago" }
        return "\(seconds / 60)m ago"
    }
}
