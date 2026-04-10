import SwiftUI

struct AnalyticsEfficiencySection: View {
    let result: AnalyticsResult

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Efficiency")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            LazyVGrid(columns: columns, spacing: 8) {
                metricCard(
                    label: "Median tok/min",
                    value: rateString(result.sessionEfficiency.medianTokensPerMinute),
                    color: .white
                )
                metricCard(
                    label: "Avg tok/min",
                    value: rateString(result.sessionEfficiency.avgTokensPerMinute),
                    color: .white.opacity(0.85)
                )
                metricCard(
                    label: "Most efficient",
                    value: rateString(result.sessionEfficiency.mostEfficient?.tokensPerMinute ?? 0),
                    detail: result.sessionEfficiency.mostEfficient?.projectName ?? "n/a",
                    color: .green
                )
                metricCard(
                    label: "Least efficient",
                    value: rateString(result.sessionEfficiency.leastEfficient?.tokensPerMinute ?? 0),
                    detail: result.sessionEfficiency.leastEfficient?.projectName ?? "n/a",
                    color: .red
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                headerRow
                ForEach(result.sessionEfficiency.top10Longest) { session in
                    HStack(spacing: 10) {
                        Text(durationString(session.durationMinutes))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 66, alignment: .leading)

                        Text(ModelPricing.formatTokens(session.totalTokens))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 78, alignment: .trailing)

                        Text(rateString(session.tokensPerMinute))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 76, alignment: .trailing)

                        Text(session.projectName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Duration")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 66, alignment: .leading)
            Text("Tokens")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 78, alignment: .trailing)
            Text("Tok/min")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 76, alignment: .trailing)
            Text("Project")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricCard(label: String, value: String, detail: String? = nil, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func rateString(_ rate: Double) -> String {
        "\(Int(rate.rounded())) tok/min"
    }

    private func durationString(_ minutes: Double) -> String {
        if minutes >= 60 {
            return String(format: "%.1fh", minutes / 60)
        }
        return String(format: "%.0fm", minutes)
    }
}
