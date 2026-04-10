import SwiftUI

struct AnalyticsCacheSection: View {
    let result: AnalyticsResult

    private let claudeAccent = Color(red: 0.85, green: 0.55, blue: 0.35)

    private var totals: (cacheRead: Int, cacheCreate: Int, freshInput: Int) {
        result.cacheHitRatio.perProject.reduce(into: (cacheRead: 0, cacheCreate: 0, freshInput: 0)) { accumulator, entry in
            accumulator.cacheRead += entry.cacheRead
            accumulator.cacheCreate += entry.cacheCreate
            accumulator.freshInput += entry.freshInput
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cache")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%.1f%%", result.cacheHitRatio.overallHitRatio * 100))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(hitRatioColor(result.cacheHitRatio.overallHitRatio))

                Text(result.cacheHitRatio.qualityLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(result.cacheHitRatio.qualityColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(result.cacheHitRatio.qualityColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            GeometryReader { geometry in
                let total = max(totals.cacheRead + totals.cacheCreate + totals.freshInput, 1)
                HStack(spacing: 1) {
                    segment(width: geometry.size.width * CGFloat(Double(totals.cacheRead) / Double(total)), color: .cyan)
                    segment(width: geometry.size.width * CGFloat(Double(totals.cacheCreate) / Double(total)), color: .green)
                    segment(width: geometry.size.width * CGFloat(Double(totals.freshInput) / Double(total)), color: claudeAccent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 8)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.1))
            )

            Text("Higher cache hit = less money burned on re-reading context")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            headerRow

            ForEach(result.cacheHitRatio.perProject) { entry in
                HStack(spacing: 10) {
                    Text(entry.projectName)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(width: 180, alignment: .leading)

                    Text(String(format: "%.1f%%", entry.hitRatio * 100))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(hitRatioColor(entry.hitRatio))
                        .frame(width: 54, alignment: .trailing)

                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(hitRatioColor(entry.hitRatio))
                            .frame(width: max(geometry.size.width * CGFloat(entry.hitRatio), entry.hitRatio > 0 ? 2 : 0), height: 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                    Text(ModelPricing.formatTokens(entry.cacheRead))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.cyan)
                        .frame(width: 70, alignment: .trailing)

                    Text(ModelPricing.formatTokens(entry.freshInput))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(claudeAccent)
                        .frame(width: 70, alignment: .trailing)
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
            Text("Hit%")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 54, alignment: .trailing)
            Text("Mix")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Cache Read")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text("Fresh Input")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: width > 0 ? max(width, 2) : 0, height: 8)
    }

    private func hitRatioColor(_ ratio: Double) -> Color {
        if ratio >= 0.8 { return .green }
        if ratio >= 0.5 { return .yellow }
        return .red
    }
}
