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
        ScrollView {
            VStack(spacing: 12) {
                if case .fetchFailed = kimiService.error {
                    ErrorBannerView(message: "Failed to fetch usage") {
                        Task { await kimiService.fetch() }
                    }
                }
                if case .rateLimited = kimiService.error {
                    ErrorBannerView(message: "Rate limited — retrying", retryDate: kimiService.retryDate)
                }

                // Main usage card
                usageCard

                // Rate limit windows
                ForEach(kimiService.kimiData.limits.indices, id: \.self) { index in
                    limitWindowCard(kimiService.kimiData.limits[index])
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
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("Weekly Usage")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                if let resetTime = kimiService.kimiData.resetTimeFormatted {
                    Text("Resets: \(resetTime)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(kimiService.kimiData.detail.used)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("/ \(kimiService.kimiData.detail.limit)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(kimiService.kimiData.utilizationPercent)%")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(utilizationColor)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let progress = min(Double(kimiService.kimiData.detail.used) / Double(max(kimiService.kimiData.detail.limit, 1)), 1.0)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(utilizationColor)
                        .frame(width: width * progress, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .frame(width: 3)
                .foregroundColor(ProviderTheme.kimi.accentColor)
        }
    }

    private func limitWindowCard(_ limit: KimiLimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("\(limit.window.duration)-minute Window")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }

            HStack {
                Text("\(limit.detail.used) / \(limit.detail.limit)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(limit.detail.remaining) remaining")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let progress = min(Double(limit.detail.used) / Double(max(limit.detail.limit, 1)), 1.0)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(utilizationColor(for: limit.detail))
                        .frame(width: width * progress, height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var utilizationColor: Color {
        utilizationColor(for: kimiService.kimiData.detail)
    }

    private func utilizationColor(for detail: KimiUsageDetail) -> Color {
        let pct = Double(detail.used) / Double(max(detail.limit, 1)) * 100
        if pct < 50 { return .green }
        if pct < 80 { return .yellow }
        return .red
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
