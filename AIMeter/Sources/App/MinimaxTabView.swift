import SwiftUI

struct MinimaxTabView: View {
    @ObservedObject var minimaxService: MinimaxService
    @ObservedObject var historyService: MinimaxHistoryService
    @EnvironmentObject private var apiKeyAuthManagers: APIKeyAuthManagers
    var onKeySaved: (() -> Void)? = nil

    private var authManager: APIKeyAuthManager { apiKeyAuthManagers.minimax }

    var body: some View {
        if minimaxService.error == .noKey {
            APIKeyInputView(
                providerName: "MiniMax",
                placeholder: "MINIMAX_API_KEY…",
                accentColor: ProviderTheme.minimax.accentColor
            ) { key in
                authManager.addAccount(label: "Default", apiKey: key)
                onKeySaved?()
            }
        } else {
            VStack(spacing: 8) {
                if authManager.accounts.count > 1 {
                    accountSwitcher
                }
                if case .fetchFailed = minimaxService.error {
                    ErrorBannerView(message: "Failed to fetch MiniMax data") {
                        Task { await minimaxService.fetch() }
                    }
                }
                if case .rateLimited = minimaxService.error {
                    ErrorBannerView(message: "Rate limited — retrying", retryDate: minimaxService.retryDate)
                }

                ForEach(minimaxService.minimaxData.models) { model in
                    Text(model.modelName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                    UsageCardView(
                        icon: "waveform.path",
                        title: "Interval Quota",
                        subtitle: "\(model.intervalUsed)/\(model.intervalTotal) used",
                        percentage: model.intervalPercent,
                        resetText: ResetTimeFormatter.format(model.resetsAt, style: .countdown),
                        accentColor: ProviderTheme.minimax.accentColor
                    )

                    UsageCardView(
                        icon: "calendar.badge.clock",
                        title: "Weekly Quota",
                        subtitle: "\(model.weeklyUsed)/\(model.weeklyTotal) used",
                        percentage: model.weeklyPercent,
                        resetText: ResetTimeFormatter.format(model.weeklyResetsAt, style: .dayTime),
                        accentColor: ProviderTheme.minimax.accentColor
                    )
                }

                UsageHistoryChartView(
                    title: "Interval % History",
                    dataPoints: historyService.history.dataPoints.map {
                        (date: $0.timestamp, value: Double($0.intervalPercent), label: shortDateLabel($0.timestamp))
                    },
                    valueFormatter: { "\(Int($0))%" },
                    accentColor: ProviderTheme.minimax.accentColor
                )
            }
        }
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var accountSwitcher: some View {
        HStack {
            Menu {
                ForEach(authManager.accounts) { account in
                    Button {
                        authManager.setActiveAccount(account.id)
                    } label: {
                        HStack {
                            Text(account.label)
                            if account.id == authManager.activeAccountId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(authManager.activeAccount?.label ?? "")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
    }
}
