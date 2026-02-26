import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let data: UsageData

    private var configuredTimeZone: TimeZone {
        let offset = UserDefaults(suiteName: SharedDefaults.suiteName)?.integer(forKey: "timezoneOffset") ?? 0
        return TimeZone(secondsFromGMT: offset * 3600) ?? .current
    }

    private var highestLimit: (String, RateLimit) {
        var candidates: [(String, RateLimit)] = [
            ("Session", data.fiveHour),
            ("Weekly", data.sevenDay)
        ]
        if let sonnet = data.sevenDaySonnet {
            candidates.append(("Sonnet", sonnet))
        }
        return candidates.max(by: { $0.1.utilization < $1.1.utilization }) ?? ("Session", data.fiveHour)
    }

    var body: some View {
        let (label, limit) = highestLimit

        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(UsageColor.forUtilization(data.highestUtilization))
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
