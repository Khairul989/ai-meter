import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let data: UsageData
    let copilotData: CopilotUsageData?

    private var configuredTimeZone: TimeZone {
        let offset = UserDefaults(suiteName: SharedDefaults.suiteName)?.integer(forKey: "timezoneOffset") ?? 0
        return TimeZone(secondsFromGMT: offset * 3600) ?? .current
    }

    // Highest utilization across all providers (for status dot color)
    private var overallHighestUtilization: Int {
        var values = [data.highestUtilization]
        if let copilot = copilotData {
            values.append(copilot.highestUtilization)
        }
        return values.max() ?? 0
    }

    // The single limit to display in the gauge — highest across Claude + Copilot premium
    private var highestLimit: (String, RateLimit) {
        var candidates: [(String, RateLimit)] = [
            ("Session", data.fiveHour),
            ("Weekly", data.sevenDay)
        ]
        if let sonnet = data.sevenDaySonnet {
            candidates.append(("Sonnet", sonnet))
        }
        // Include Copilot premium as a synthetic RateLimit for comparison
        if let copilot = copilotData,
           !copilot.premiumInteractions.unlimited {
            let synthetic = RateLimit(utilization: copilot.premiumInteractions.utilization, resetsAt: copilot.resetDate)
            candidates.append(("Copilot", synthetic))
        }
        return candidates.max(by: { $0.1.utilization < $1.1.utilization }) ?? ("Session", data.fiveHour)
    }

    var body: some View {
        let (label, limit) = highestLimit

        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(UsageColor.forUtilization(overallHighestUtilization))
                    .frame(width: 6, height: 6)
                Text("AI Meter")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            CircularGaugeView(percentage: limit.utilization, lineWidth: 6, size: 64)

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)

            if let resetText = ResetTimeFormatter.format(limit.resetsAt, style: .countdown, timeZone: configuredTimeZone) {
                Text("Reset \(resetText)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}
