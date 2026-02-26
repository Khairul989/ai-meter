import SwiftUI

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = 0

    private var configuredTimeZone: TimeZone {
        TimeZone(secondsFromGMT: timezoneOffset * 3600) ?? .current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundColor(UsageColor.forUtilization(service.usageData.highestUtilization))
                    .font(.system(size: 10))
                Text("AI Meter")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.bottom, 8)

            if let error = service.error, error == .noToken {
                noTokenView
            } else {
                usageCards
            }

            Divider().background(Color.gray.opacity(0.3))

            // Footer
            HStack {
                Text(updatedText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                if service.isStale {
                    Text("(stale)")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                Spacer()
                Button(action: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }) {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private var usageCards: some View {
        let data = service.usageData

        UsageCardView(
            icon: "timer",
            title: "Session",
            subtitle: "5h sliding window",
            percentage: data.fiveHour.utilization,
            resetText: ResetTimeFormatter.format(data.fiveHour.resetsAt, style: .countdown, timeZone: configuredTimeZone)
        )

        UsageCardView(
            icon: "chart.bar.fill",
            title: "Weekly",
            subtitle: "Opus + Sonnet + Haiku",
            percentage: data.sevenDay.utilization,
            resetText: ResetTimeFormatter.format(data.sevenDay.resetsAt, style: .dayTime, timeZone: configuredTimeZone)
        )

        if let sonnet = data.sevenDaySonnet {
            UsageCardView(
                icon: "sparkles",
                title: "Sonnet",
                subtitle: "Dedicated limit",
                percentage: sonnet.utilization,
                resetText: ResetTimeFormatter.format(sonnet.resetsAt, style: .dayTime, timeZone: configuredTimeZone)
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

    private var noTokenView: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No token found")
                .font(.headline)
                .foregroundColor(.white)
            Text("Sign into Claude Code to get started")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var updatedText: String {
        let seconds = Int(Date().timeIntervalSince(service.usageData.fetchedAt))
        if seconds < 60 { return "Updated less than a minute ago" }
        let minutes = seconds / 60
        return "Updated \(minutes)m ago"
    }
}
