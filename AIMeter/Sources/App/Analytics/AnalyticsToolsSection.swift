import SwiftUI

struct AnalyticsToolsSection: View {
    let result: AnalyticsResult

    private let claudeAccent = Color(red: 0.85, green: 0.55, blue: 0.35)
    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private var rows: [ToolUsageEntry] {
        Array(result.toolUsage.sorted { $0.callCount > $1.callCount }.prefix(20))
    }

    private var maxCalls: Int {
        rows.map(\.callCount).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tools")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            headerRow

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 10) {
                    Text("#\(index + 1)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 28, alignment: .leading)

                    Text(entry.id)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)

                    GeometryReader { geometry in
                        let fraction = Double(entry.callCount) / Double(max(maxCalls, 1))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(claudeAccent)
                            .frame(width: max(geometry.size.width * CGFloat(fraction), fraction > 0 ? 2 : 0), height: 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                    Text(formattedCount(entry.callCount))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
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
            Text("Tool")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 220, alignment: .leading)
            Text("Calls")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Count")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func formattedCount(_ count: Int) -> String {
        Self.countFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}
