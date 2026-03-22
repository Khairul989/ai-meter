import SwiftUI

struct CopilotTabView: View {
    @ObservedObject var copilotService: CopilotService
    @ObservedObject var historyService: CopilotHistoryService
    let timeZone: TimeZone
    var providerStatus: ProviderStatusService.StatusInfo?

    var body: some View {
        if copilotService.error == .noToken {
            connectGitHubView
        } else {
            let copilot = copilotService.copilotData
            VStack(alignment: .leading, spacing: 6) {
                    if copilotService.error == .fetchFailed {
                        ErrorBannerView(message: "Failed to fetch Copilot data") {
                            Task { await copilotService.fetch() }
                        }
                    } else if case .rateLimited = copilotService.error {
                        ErrorBannerView(message: "Rate limited — retrying", retryDate: copilotService.retryDate)
                    }

                    if let status = providerStatus, status.indicator != "none" {
                        ProviderStatusBannerView(status: status)
                    }
                    if let resetText = ResetTimeFormatter.format(copilot.resetDate, style: .dateTime, timeZone: timeZone) {
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
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
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
        VStack(spacing: 12) {
            Image("copilot")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundColor(.secondary.opacity(0.5))
            Text("Not connected")
                .font(.headline)
                .foregroundColor(.white)
            Text("Monitor your Copilot usage in real time")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("Run `gh auth login` in Terminal first")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
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
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .frame(width: 2)
                .foregroundColor(ProviderTheme.copilot.accentColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) quota")
        .accessibilityValue(quota.unlimited ? "Unlimited" : "\(quota.utilization) percent, \(quota.remaining) of \(quota.entitlement) remaining")
    }
}
