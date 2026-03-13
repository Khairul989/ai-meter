import SwiftUI

struct KimiTabView: View {
    @ObservedObject var kimiService: KimiService
    var onKeySaved: (() -> Void)? = nil

    var body: some View {
        if kimiService.error == .noKey {
            APIKeyInputView(
                providerName: "Kimi",
                placeholder: "KIMI_API_KEY…",
                accentColor: ProviderTheme.kimi.accentColor
            ) { key in
                APIKeyKeychainHelper.kimi.saveAPIKey(key)
                onKeySaved?()
            }
        } else {
            VStack(spacing: 8) {
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
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))

                    if case .fetchFailed = kimiService.error {
                        ErrorBannerView(message: "Failed to fetch balance") {
                            Task { await kimiService.fetch() }
                        }
                    }
                    if case .rateLimited = kimiService.error {
                        ErrorBannerView(message: "Rate limited — backing off")
                    }
                }
        }
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


}
