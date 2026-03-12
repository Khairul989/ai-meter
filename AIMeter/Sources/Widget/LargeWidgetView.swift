import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let data: UsageData
    let copilotData: CopilotUsageData?
    let glmData: GLMUsageData?

    private var configuredTimeZone: TimeZone {
        let offset = UserDefaults(suiteName: SharedDefaults.suiteName)?.integer(forKey: "timezoneOffset") ?? 0
        return SharedDefaults.configuredTimeZone(for: offset)
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
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                gaugeCell(
                    label: "Session",
                    percentage: data.fiveHour.utilization,
                    resetText: ResetTimeFormatter.format(data.fiveHour.resetsAt, style: .countdown, timeZone: configuredTimeZone),
                    accentColor: ProviderTheme.claude.accentColor
                )
                gaugeCell(
                    label: "Weekly",
                    percentage: data.sevenDay.utilization,
                    resetText: ResetTimeFormatter.format(data.sevenDay.resetsAt, style: .dayTime, timeZone: configuredTimeZone),
                    accentColor: ProviderTheme.claude.accentColor
                )
                gaugeCell(
                    label: "Copilot",
                    percentage: copilotData?.premiumInteractions.utilization ?? 0,
                    resetText: copilotData.flatMap { ResetTimeFormatter.format($0.resetDate, style: .dayTime, timeZone: configuredTimeZone) },
                    accentColor: ProviderTheme.copilot.accentColor
                )
                gaugeCell(
                    label: "GLM",
                    percentage: glmData?.tokensPercent ?? 0,
                    resetText: nil,
                    accentColor: ProviderTheme.glm.accentColor
                )
            }
        }
        .widgetURL(URL(string: "aimeter://tab/claude")!)
    }

    private var overallHighestUtilization: Int {
        var values = [data.highestUtilization]
        if let copilot = copilotData {
            values.append(copilot.highestUtilization)
        }
        if let glm = glmData {
            values.append(glm.tokensPercent)
        }
        return values.max() ?? 0
    }

    private func gaugeCell(label: String, percentage: Int, resetText: String?, accentColor: Color) -> some View {
        VStack(spacing: 4) {
            CircularGaugeView(percentage: percentage, lineWidth: 5, size: 56)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
            if let resetText {
                Text(resetText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityLabel("\(label) at \(percentage) percent")
    }
}
