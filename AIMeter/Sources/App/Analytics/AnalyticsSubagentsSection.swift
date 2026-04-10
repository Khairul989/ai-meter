import SwiftUI

struct AnalyticsSubagentsSection: View {
    let result: AnalyticsResult

    private let claudeAccent = Color(red: 0.85, green: 0.55, blue: 0.35)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subagents")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text(percentString(result.subagentOverhead.overallSharePercent))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(percentColor(result.subagentOverhead.overallSharePercent))
                Text("\(ModelPricing.formatTokens(result.subagentOverhead.grandSubTokens)) tokens out of \(ModelPricing.formatTokens(result.subagentOverhead.grandCombinedTokens))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            headerRow

            ForEach(result.subagentOverhead.perProject) { entry in
                HStack(spacing: 10) {
                    Text(entry.projectName)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(width: 180, alignment: .leading)

                    Text(percentString(entry.overheadPercent))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(percentColor(entry.overheadPercent))
                        .frame(width: 62, alignment: .trailing)

                    GeometryReader { geometry in
                        let fraction = entry.overheadPercent / 100
                        RoundedRectangle(cornerRadius: 2)
                            .fill(percentColor(entry.overheadPercent))
                            .frame(width: max(geometry.size.width * CGFloat(fraction), fraction > 0 ? 2 : 0), height: 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                    Text(ModelPricing.formatTokens(entry.subTokens))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(claudeAccent)
                        .frame(width: 74, alignment: .trailing)

                    Text(ModelPricing.formatTokens(entry.mainTokens))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 74, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Project")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 180, alignment: .leading)
            Text("Overhead%")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 62, alignment: .trailing)
            Text("Share")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Sub Tokens")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 74, alignment: .trailing)
            Text("Main Tokens")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 74, alignment: .trailing)
        }
    }

    private func percentString(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func percentColor(_ value: Double) -> Color {
        if value > 50 { return .red }
        if value >= 20 { return .yellow }
        return .green
    }
}
