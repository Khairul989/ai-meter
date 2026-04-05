import SwiftUI

struct GLMTabView: View {
    @ObservedObject var glmService: GLMService
    @ObservedObject var historyService: GLMHistoryService
    @EnvironmentObject private var apiKeyAuthManagers: APIKeyAuthManagers
    var onKeySaved: (() -> Void)? = nil

    private var authManager: APIKeyAuthManager { apiKeyAuthManagers.glm }

    var body: some View {
        if glmService.error == .noKey {
            APIKeyInputView(
                providerName: "GLM",
                placeholder: "GLM_API_KEY…",
                accentColor: ProviderTheme.glm.accentColor
            ) { key in
                authManager.addAccount(label: "Default", apiKey: key)
                onKeySaved?()
            }
        } else {
            VStack(spacing: 8) {
                    if authManager.accounts.count > 1 {
                        accountSwitcher
                    }
                    if case .fetchFailed = glmService.error {
                        ErrorBannerView(message: "Failed to fetch GLM data") {
                            Task { await glmService.fetch() }
                        }
                    }
                    if case .rateLimited = glmService.error {
                        ErrorBannerView(message: "Rate limited — retrying", retryDate: glmService.retryDate)
                    }
                    UsageCardView(
                        icon: "z.square",
                        title: "5hr Token Quota",
                        subtitle: "5h sliding window",
                        percentage: glmService.glmData.tokensPercent,
                        resetText: nil,
                        accentColor: ProviderTheme.glm.accentColor
                    )
                    if !glmService.glmData.tier.isEmpty {
                        HStack {
                            Text("Account")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(glmService.glmData.tier.capitalized)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    }
                    UsageHistoryChartView(
                        title: "Token % History",
                        dataPoints: historyService.history.dataPoints.map {
                            (date: $0.timestamp, value: Double($0.tokensPercent), label: shortDateLabel($0.timestamp))
                        },
                        valueFormatter: { "\(Int($0))%" },
                        accentColor: ProviderTheme.glm.accentColor
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
