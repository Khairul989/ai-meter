import SwiftUI

struct AnalyticsTopSessionsSection: View {
    let result: AnalyticsResult

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Sessions")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            ForEach(Array(result.topSessions.prefix(10).enumerated()), id: \.element.id) { index, session in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("#\(index + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)

                        Text(dateLabel(for: session.timestampStart))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text(session.projectName)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(width: 200, alignment: .leading)

                        Spacer(minLength: 0)

                        Text(ModelPricing.formatTokens(session.totalTokens))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.yellow)

                        Text(ModelPricing.formatCost(session.estimatedCostUSD))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Text(previewText(for: session.firstPromptPreview))
                        .font(.system(size: 10))
                        .italic()
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private func dateLabel(for date: Date?) -> String {
        guard let date else { return "unknown" }
        return Self.dateFormatter.string(from: date)
    }

    private func previewText(for preview: String) -> String {
        if preview.count <= 80 { return preview }
        return String(preview.prefix(80)) + "..."
    }
}
