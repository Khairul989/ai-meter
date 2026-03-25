import SwiftUI

struct MinimaxTabView: View {
    @ObservedObject var minimaxService: MinimaxService
    @ObservedObject var historyService: MinimaxHistoryService
    var onKeySaved: (() -> Void)? = nil

    var body: some View {
        if minimaxService.error == .noKey {
            APIKeyInputView(
                providerName: "MiniMax",
                placeholder: "MINIMAX_API_KEY…",
                accentColor: ProviderTheme.minimax.accentColor
            ) { key in
                APIKeyKeychainHelper.minimax.saveAPIKey(key)
                onKeySaved?()
            }
        } else {
            VStack(spacing: 8) {
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
                        resetText: model.resetsAt.map { shortDateLabel($0) },
                        accentColor: ProviderTheme.minimax.accentColor
                    )

                    UsageCardView(
                        icon: "calendar.badge.clock",
                        title: "Weekly Quota",
                        subtitle: "\(model.weeklyUsed)/\(model.weeklyTotal) used",
                        percentage: model.weeklyPercent,
                        resetText: model.weeklyResetsAt.map { shortDateLabel($0) },
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
}
