import SwiftUI

struct KimiTabView: View {
    @ObservedObject var kimiService: KimiService
    var onKeySaved: (() -> Void)? = nil
    @State private var keyInput: String = ""
    @State private var keySaved: Bool = false

    var body: some View {
        if kimiService.error == .noKey {
            noKeyView
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if kimiService.error == .fetchFailed {
                        Text("Failed to fetch balance")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var noKeyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No Kimi API key found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("Paste your API key below or add it in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                SecureField("KIMI_API_KEY…", text: $keyInput)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if !keyInput.isEmpty {
                    Button(keySaved ? "Saved ✓" : "Save") {
                        KimiKeychainHelper.saveAPIKey(keyInput)
                        keySaved = true
                        keyInput = ""
                        onKeySaved?()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(keySaved ? .green : .accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
