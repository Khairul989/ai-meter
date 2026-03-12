import SwiftUI

struct GLMTabView: View {
    @ObservedObject var glmService: GLMService
    var onKeySaved: (() -> Void)? = nil
    @State private var keyInput: String = ""
    @State private var keySaved: Bool = false

    var body: some View {
        if glmService.error == .noKey {
            noKeyView
        } else {
            VStack(spacing: 8) {
                    UsageCardView(
                        icon: "z.square",
                        title: "5hr Token Quota",
                        subtitle: "5h sliding window",
                        percentage: glmService.glmData.tokensPercent,
                        resetText: nil
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
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
        }
    }

    private var noKeyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No GLM API key found")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text("Paste your API key below or add it in Settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                SecureField("GLM_API_KEY…", text: $keyInput)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if !keyInput.isEmpty {
                    Button(keySaved ? "Saved ✓" : "Save") {
                        GLMKeychainHelper.saveAPIKey(keyInput)
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
