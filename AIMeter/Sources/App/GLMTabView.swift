import SwiftUI

struct GLMTabView: View {
    @ObservedObject var glmService: GLMService
    var onKeySaved: (() -> Void)? = nil

    var body: some View {
        if glmService.error == .noKey {
            APIKeyInputView(
                providerName: "GLM",
                placeholder: "GLM_API_KEY…",
                accentColor: ProviderTheme.glm.accentColor
            ) { key in
                APIKeyKeychainHelper.glm.saveAPIKey(key)
                onKeySaved?()
            }
        } else {
            VStack(spacing: 8) {
                    if case .fetchFailed = glmService.error {
                        ErrorBannerView(message: "Failed to fetch GLM data") {
                            Task { await glmService.fetch() }
                        }
                    }
                    if case .rateLimited = glmService.error {
                        ErrorBannerView(message: "Rate limited — backing off")
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
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    }
                }
        }
    }


}
