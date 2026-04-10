import SwiftUI

struct AnalyticsByProjectSection: View {
    let result: AnalyticsResult

    private let claudeAccent = Color(red: 0.85, green: 0.55, blue: 0.35)

    private var rows: [ProjectAnalytics] {
        Array(result.byProject.sorted { $0.totalTokens > $1.totalTokens }.prefix(30))
    }

    private var maxTokens: Int {
        rows.map(\.totalTokens).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Project")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            headerRow

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, project in
                HStack(spacing: 10) {
                    Text("#\(index + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 28, alignment: .leading)

                    Text(project.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 200, alignment: .leading)

                    GeometryReader { geometry in
                        let fraction = Double(project.totalTokens) / Double(max(maxTokens, 1))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(claudeAccent)
                            .frame(width: max(geometry.size.width * CGFloat(fraction), fraction > 0 ? 2 : 0), height: 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                    Text(ModelPricing.formatTokens(project.totalTokens))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 78, alignment: .trailing)

                    Text(percentString(project.percentOfAll))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(percentColor(project.percentOfAll))
                        .frame(width: 54, alignment: .trailing)

                    Text("\(project.sessionCount)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)

                    Text(ModelPricing.formatCost(project.estimatedCostUSD))
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
            Text("Rank")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
            Text("Project")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 200, alignment: .leading)
            Text("Share")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Tokens")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 78, alignment: .trailing)
            Text("%")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 54, alignment: .trailing)
            Text("Sess")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)
            Text("Cost")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func percentString(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func percentColor(_ value: Double) -> Color {
        if value >= 25 { return .red }
        if value >= 10 { return .yellow }
        return .green
    }
}
