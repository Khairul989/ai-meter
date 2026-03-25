import SwiftUI

struct KimiTabView: View {
    @ObservedObject var kimiService: KimiService
    @ObservedObject var historyService: KimiHistoryService
    @ObservedObject var authManager: KimiAuthManager

    var body: some View {
        if !authManager.isAuthenticated {
            signInPromptView
        } else {
            usageContentView
        }
    }

    private var signInPromptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Sign in to Kimi")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Text("Access your Kimi for Coding usage data")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Sign in with Kimi") {
                authManager.openLoginWindow()
            }
            .font(.system(size: 13, weight: .medium))
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            if let error = authManager.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var usageContentView: some View {
        VStack(spacing: 12) {
            if case .fetchFailed = kimiService.error {
                ErrorBannerView(message: "Failed to fetch usage") {
                    Task { await kimiService.fetch() }
                }
            }
            if case .rateLimited = kimiService.error {
                ErrorBannerView(message: "Rate limited — retrying", retryDate: kimiService.retryDate)
            }

            // Main usage card - Weekly
            UsageCardView(
                icon: "chart.bar.fill",
                title: "Weekly",
                subtitle: "Total usage",
                percentage: kimiService.kimiData.utilizationPercent,
                resetText: kimiService.kimiData.resetTimeFormatted,
                accentColor: ProviderTheme.kimi.accentColor,
                isPrimary: true
            )

            // Rate limit windows
            ForEach(kimiService.kimiData.limits.indices, id: \.self) { index in
                let limit = kimiService.kimiData.limits[index]
                let percentage = limit.detail.limit > 0 ? Int((Double(limit.detail.used) / Double(limit.detail.limit)) * 100) : 0
                UsageCardView(
                    icon: "clock.fill",
                    title: windowTitle(for: limit.window.duration),
                    subtitle: "\(limit.detail.remaining) remaining",
                    percentage: percentage,
                    resetText: limit.detail.resetTime.map { formatResetTime($0) },
                    accentColor: ProviderTheme.kimi.accentColor
                )
            }

            // History chart
            if !historyService.history.dataPoints.isEmpty {
                UsageHistoryChartView(
                    title: "Usage History",
                    dataPoints: historyService.history.dataPoints.map {
                        (date: $0.timestamp, value: Double($0.utilization), label: shortDateLabel($0.timestamp))
                    },
                    valueFormatter: { "\(Int($0))%" },
                    accentColor: ProviderTheme.kimi.accentColor
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func windowTitle(for duration: Int) -> String {
        if duration == 300 {
            return "5-hour Window"
        }
        return "\(duration)-minute Window"
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatResetTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
