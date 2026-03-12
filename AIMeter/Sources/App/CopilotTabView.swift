import SwiftUI

struct CopilotTabView: View {
    @ObservedObject var copilotService: CopilotService
    @ObservedObject var historyService: CopilotHistoryService
    let timeZone: TimeZone

    var body: some View {
        if copilotService.error == .noToken {
            connectGitHubView
        } else {
            let copilot = copilotService.copilotData
            VStack(alignment: .leading, spacing: 6) {
                    if let resetText = ResetTimeFormatter.format(copilot.resetDate, style: .dayTime, timeZone: timeZone) {
                        Text("Reset \(resetText)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                    }
                    CopilotChartView(historyService: historyService)
                    HStack(spacing: 4) {
                        Text("BETA")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text("Trend data is experimental — accuracy may vary.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 2)
                    copilotQuotaRow(title: "Chat", quota: copilot.chat)
                    copilotQuotaRow(title: "Completions", quota: copilot.completions)
                    copilotQuotaRow(title: "Premium", quota: copilot.premiumInteractions)
                }
        }
    }

    private var connectGitHubView: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            Text("Connect GitHub CLI to see Copilot usage")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func copilotQuotaRow(title: String, quota: CopilotQuota) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            if quota.unlimited {
                Text("Unlimited")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(quota.utilization)%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(UsageColor.forUtilization(quota.utilization))
                    Text("\(quota.remaining)/\(quota.entitlement) remaining")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) quota")
        .accessibilityValue(quota.unlimited ? "Unlimited" : "\(quota.utilization) percent, \(quota.remaining) of \(quota.entitlement) remaining")
    }
}
