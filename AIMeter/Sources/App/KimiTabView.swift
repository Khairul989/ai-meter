import SwiftUI

struct KimiTabView: View {
    @ObservedObject var kimiService: KimiService
    @ObservedObject var historyService: KimiHistoryService
    @EnvironmentObject private var apiKeyAuthManagers: APIKeyAuthManagers
    var onKeySaved: (() -> Void)? = nil

    private var authManager: APIKeyAuthManager { apiKeyAuthManagers.kimi }

    var body: some View {
        if kimiService.error == .noKey {
            APIKeyInputView(
                providerName: "Kimi",
                placeholder: "KIMI_API_KEY…",
                accentColor: ProviderTheme.kimi.accentColor
            ) { key in
                authManager.addAccount(label: "Default", apiKey: key)
                onKeySaved?()
            }
        } else {
            VStack(spacing: 8) {
                    if authManager.accounts.count > 1 {
                        accountSwitcher
                    }
                    if case .fetchFailed = kimiService.error {
                        ErrorBannerView(message: "Failed to fetch balance") {
                            Task { await kimiService.fetch() }
                        }
                    }
                    if case .rateLimited = kimiService.error {
                        ErrorBannerView(message: "Rate limited — retrying", retryDate: kimiService.retryDate)
                    }
                    balanceRow(
                        icon: "yensign.circle.fill",
                        title: "Cash Balance",
                        value: kimiService.kimiData.cashBalance
                    )
                    balanceRow(
                        icon: "ticket.fill",
                        title: "Voucher Balance",
                        value: kimiService.kimiData.voucherBalance
                    )
                    HStack {
                        Text("Total Available")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "¥%.4f", kimiService.kimiData.totalBalance))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(kimiService.kimiData.totalBalance > 0 ? .green : .red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))

                    UsageHistoryChartView(
                        title: "Balance History",
                        dataPoints: historyService.history.dataPoints.map {
                            (date: $0.timestamp, value: $0.totalBalance, label: shortDateLabel($0.timestamp))
                        },
                        // Currency y-axis: show 2 decimal places
                        valueFormatter: { String(format: "¥%.2f", $0) },
                        accentColor: ProviderTheme.kimi.accentColor
                    )
                }
        }
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func balanceRow(icon: String, title: String, value: Double) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Text(String(format: "¥%.4f", value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(value > 0 ? .white : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .frame(width: 2)
                .foregroundColor(ProviderTheme.kimi.accentColor)
        }
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
