import SwiftUI

struct AnalyticsOverviewSection: View {
    let result: AnalyticsResult

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private let claudeAccent = Color(red: 0.85, green: 0.55, blue: 0.35)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            LazyVGrid(columns: columns, spacing: 8) {
                statCard(
                    label: "Projects",
                    value: "\(result.grandTotals.projectCount)",
                    icon: "chart.pie",
                    color: claudeAccent
                )
                statCard(
                    label: "Sessions",
                    value: "\(result.grandTotals.sessionCount)",
                    icon: "text.bubble",
                    color: .cyan
                )
                statCard(
                    label: "Total Tokens",
                    value: ModelPricing.formatTokens(result.grandTotals.totalTokens),
                    icon: "sum",
                    color: .white
                )
                statCard(
                    label: "Estimated Cost",
                    value: ModelPricing.formatCost(result.grandTotals.estimatedCostUSD),
                    icon: "dollarsign.circle",
                    color: .green
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                tokenBreakdownBar
                legend
            }

            VStack(alignment: .leading, spacing: 8) {
                headerRow
                ForEach(result.grandTotals.costByModel) { entry in
                    HStack(spacing: 8) {
                        Text(entry.displayName)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(ModelPricing.formatTokens(entry.totalTokens))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .trailing)

                        Text(ModelPricing.formatCost(entry.costUSD))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                            .frame(width: 72, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private var tokenBreakdownBar: some View {
        GeometryReader { geometry in
            let total = max(result.grandTotals.totalTokens, 1)
            HStack(spacing: 1) {
                breakdownSegment(
                    width: geometry.size.width * CGFloat(Double(result.grandTotals.inputTokens) / Double(total)),
                    color: claudeAccent
                )
                breakdownSegment(
                    width: geometry.size.width * CGFloat(Double(result.grandTotals.cacheCreateTokens) / Double(total)),
                    color: .green
                )
                breakdownSegment(
                    width: geometry.size.width * CGFloat(Double(result.grandTotals.cacheReadTokens) / Double(total)),
                    color: .cyan
                )
                breakdownSegment(
                    width: geometry.size.width * CGFloat(Double(result.grandTotals.outputTokens) / Double(total)),
                    color: Color.white.opacity(0.8)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 8)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.1))
        )
    }

    private func breakdownSegment(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: width > 0 ? max(width, 2) : 0, height: 8)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(label: "Input", color: claudeAccent)
            legendItem(label: "Cache Create", color: .green)
            legendItem(label: "Cache Read", color: .cyan)
            legendItem(label: "Output", color: Color.white.opacity(0.8))
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Model")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Tokens")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text("Cost")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
        }
    }

    private func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    private func statCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color.opacity(0.8))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
