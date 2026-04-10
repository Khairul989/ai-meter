import SwiftUI

struct AnalyticsByModelSection: View {
    let result: AnalyticsResult

    private let claudeAccent = Color(red: 0.85, green: 0.55, blue: 0.35)

    private var rows: [ModelAnalytics] {
        result.byModel.sorted { $0.totalTokens > $1.totalTokens }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Model")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            headerRow

            ForEach(rows) { model in
                HStack(spacing: 10) {
                    Text(model.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 120, alignment: .leading)

                    GeometryReader { geometry in
                        let total = max(model.totalTokens, 1)
                        HStack(spacing: 1) {
                            segment(width: geometry.size.width * CGFloat(Double(model.inputTokens) / Double(total)), color: claudeAccent)
                            segment(width: geometry.size.width * CGFloat(Double(model.cacheCreateTokens) / Double(total)), color: .green)
                            segment(width: geometry.size.width * CGFloat(Double(model.cacheReadTokens) / Double(total)), color: .cyan)
                            segment(width: geometry.size.width * CGFloat(Double(model.outputTokens) / Double(total)), color: Color.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: 8)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                    )

                    Text(ModelPricing.formatTokens(model.totalTokens))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 90, alignment: .trailing)

                    Text(ModelPricing.formatCost(model.estimatedCostUSD))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Model")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text("Mix")
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
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: width > 0 ? max(width, 2) : 0, height: 8)
    }
}
