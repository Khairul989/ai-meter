import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let data: UsageData

    private var configuredTimeZone: TimeZone {
        let offset = UserDefaults(suiteName: SharedDefaults.suiteName)?.integer(forKey: "timezoneOffset") ?? 0
        return TimeZone(secondsFromGMT: offset * 3600) ?? .current
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(UsageColor.forUtilization(data.highestUtilization))
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
            }
        }
    }

    private var gaugeSize: CGFloat {
        data.extraCredits != nil ? 48 : 56
    }

    private var gaugeLineWidth: CGFloat {
        data.extraCredits != nil ? 4 : 5
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
