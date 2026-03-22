import SwiftUI

private let codexAccent = Color(red: 0.10, green: 0.75, blue: 0.55)

struct CodexTabView: View {
    @ObservedObject var codexService: CodexService
    @ObservedObject var codexAuthManager: CodexAuthManager
    let timeZone: TimeZone
    var providerStatus: ProviderStatusService.StatusInfo?

    var body: some View {
        if !codexAuthManager.isAuthenticated {
            signInView
        } else {
            let codexData = codexService.codexData
            VStack(alignment: .leading, spacing: 6) {
                if codexService.error == .fetchFailed {
                    ErrorBannerView(message: "Failed to fetch Codex data") {
                        Task { await codexService.fetch() }
                    }
                } else if case .rateLimited = codexService.error {
                    ErrorBannerView(message: "Rate limited — retrying", retryDate: codexService.retryDate)
                } else if codexService.error == .tokenExpired {
                    tokenExpiredBanner
                }

                if let status = providerStatus, status.indicator != "none" {
                    ProviderStatusBannerView(status: status)
                }

                UsageCardView(
                    icon: "clock",
                    title: "5hr Usage",
                    subtitle: "5h sliding window",
                    percentage: codexData.primaryPercent,
                    resetText: ResetTimeFormatter.format(codexData.primaryResetAt, style: .countdown, timeZone: timeZone),
                    accentColor: codexAccent,
                    isPrimary: true
                )

                UsageCardView(
                    icon: "calendar",
                    title: "7-day Usage",
                    subtitle: "7-day window",
                    percentage: codexData.secondaryPercent,
                    resetText: ResetTimeFormatter.format(codexData.secondaryResetAt, style: .dayTime, timeZone: timeZone),
                    accentColor: codexAccent
                )

                if codexData.codeReviewPercent > 0 {
                    UsageCardView(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "Code Review",
                        subtitle: "Code review quota",
                        percentage: codexData.codeReviewPercent,
                        resetText: nil,
                        accentColor: codexAccent
                    )
                }

                if !codexData.planType.isEmpty {
                    HStack {
                        Text("Plan")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(codexData.planType.capitalized)
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

    private var signInView: some View {
        VStack(spacing: 12) {
            Image("codex")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundColor(.secondary.opacity(0.5))
            Text("Not signed in")
                .font(.headline)
                .foregroundColor(.white)
            Text("Monitor your Codex usage in real time")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button {
                codexAuthManager.openLoginWindow()
            } label: {
                Text("Sign in with ChatGPT")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(codexAccent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(codexAuthManager.isLoggingIn)

            if codexAuthManager.isLoggingIn {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                    Text("Waiting for login...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            if let error = codexAuthManager.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var tokenExpiredBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 11))
            Text("Session expired — sign in again")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Spacer()
            Button("Sign in") {
                codexAuthManager.openLoginWindow()
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .foregroundColor(.orange)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }
}
