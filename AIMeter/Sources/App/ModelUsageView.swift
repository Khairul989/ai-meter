import SwiftUI

struct ModelUsageView: View {
    @ObservedObject var statsService: ClaudeCodeStatsService

    private static let modelColors: [Color] = [.orange, .blue, .green, .gray]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with range picker
            HStack {
                Text("Models")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(formatTokens(statsService.totalTokens))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            // Range picker
            HStack(spacing: 0) {
                ForEach(ModelTimeRange.allCases, id: \.self) { range in
                    Button {
                        statsService.selectedRange = range
                    } label: {
                        Text(range.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(statsService.selectedRange == range ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                statsService.selectedRange == range
                                    ? Color.white.opacity(0.15)
                                    : Color.clear
                            )
                            .cornerRadius(AppRadius.badge)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.white.opacity(0.05))
            .cornerRadius(AppRadius.button)

            if statsService.isLoading && statsService.models.isEmpty && statsService.selectedRange != .allTime {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning logs…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else if statsService.models.isEmpty {
                Text("No usage in this period")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                // Multi-color bar
                if statsService.totalTokens > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 1) {
                            ForEach(statsService.models) { model in
                                let fraction = CGFloat(model.totalTokens) / CGFloat(statsService.totalTokens)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(colorFor(model))
                                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? 2 : 0))
                            }
                        }
                    }
                    .frame(height: 6)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                    )
                }

                // Per-model rows
                ForEach(statsService.models) { model in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(colorFor(model))
                            .frame(width: 6, height: 6)
                        Text(model.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                        Text(formatTokens(model.inputTokens))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("in")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                        Text(formatTokens(model.outputTokens))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                        Text("out")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(AppRadius.card)
    }

    private func colorFor(_ model: ModelTokenUsage) -> Color {
        Self.modelColors[min(model.colorIndex, Self.modelColors.count - 1)]
    }

    private func formatTokens(_ count: Int) -> String {
        switch count {
        case 0:
            return "0"
        case ..<1_000:
            return "\(count)"
        case ..<1_000_000:
            let k = Double(count) / 1_000
            return k >= 100 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
        case ..<1_000_000_000:
            let m = Double(count) / 1_000_000
            return m >= 100 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        default:
            let b = Double(count) / 1_000_000_000
            return String(format: "%.1fB", b)
        }
    }
}
