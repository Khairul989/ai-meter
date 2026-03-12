import SwiftUI
import Charts

struct TrendChartView: View {
    @ObservedObject var statsService: ClaudeCodeStatsService
    @State private var hoverDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with range picker
            HStack {
                Text("Trend")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(TrendRange.allCases, id: \.self) { range in
                        Button {
                            statsService.trendRange = range
                        } label: {
                            Text(range.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(statsService.trendRange == range ? .white : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    statsService.trendRange == range
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
            }

            if statsService.isLoading && statsService.trendPoints.allSatisfy({ $0.messages == 0 }) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading trend data...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                chartView
                summaryRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(AppRadius.card)
    }

    // MARK: - Chart

    private var chartView: some View {
        let points = statsService.trendPoints
        let maxMessages = points.map(\.messages).max() ?? 1
        let maxTokens = points.map(\.tokens).max() ?? 1

        return Chart {
            ForEach(points) { point in
                // Bar for messages
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Messages", point.messages)
                )
                .foregroundStyle(Color.orange.opacity(0.7))
                .cornerRadius(2)
            }

            ForEach(points) { point in
                // Line for tokens (scaled to bar axis)
                let scaledTokens = maxMessages > 0 && maxTokens > 0
                    ? Double(point.tokens) / Double(maxTokens) * Double(maxMessages)
                    : 0.0
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Tokens", scaledTokens)
                )
                .foregroundStyle(Color.cyan)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            if let hoverDate {
                RuleMark(x: .value("Hover", hoverDate))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center) {
                        if let nearest = nearestTrendPoint(to: hoverDate, in: points) {
                            VStack(spacing: 2) {
                                Text("\(nearest.messages) msgs")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                                Text("\(formatCompact(nearest.tokens)) tok")
                                    .font(.system(size: 8))
                                    .foregroundColor(.cyan)
                            }
                            .padding(4)
                            .background(Color.black.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
                        }
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(dayLabel(date))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text(formatCompact(v))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .chartYScale(domain: 0...(max(maxMessages, 1)))
        .chartLegend(.hidden)
        .frame(height: 80)
        .chartOverlay { proxy in
            GeometryReader { _ in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoverDate = proxy.value(atX: location.x, as: Date.self)
                        case .ended:
                            hoverDate = nil
                        }
                    }
            }
        }
    }

    private func nearestTrendPoint(to date: Date, in points: [DailyTrendPoint]) -> DailyTrendPoint? {
        points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    private var xAxisStride: Int {
        switch statsService.trendRange {
        case .sevenDay: return 1
        case .fourteenDay: return 2
        case .thirtyDay: return 5
        }
    }

    // MARK: - Summary

    private var summaryRow: some View {
        let points = statsService.trendPoints
        let totalMsgs = points.reduce(0) { $0 + $1.messages }
        let totalTokens = points.reduce(0) { $0 + $1.tokens }
        let daysWithData = points.filter { $0.messages > 0 }.count
        let avgMsgs = daysWithData > 0 ? totalMsgs / daysWithData : 0

        return HStack(spacing: 0) {
            summaryPill(icon: "circle", color: .orange, text: "\(avgMsgs) msgs/day")
            summaryPill(icon: "sum", color: .white, text: "\(formatCompact(totalMsgs)) total msgs")
            summaryPill(icon: "number", color: .cyan, text: "\(formatCompact(totalTokens)) tokens")
        }
    }

    private func summaryPill(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7))
                .foregroundColor(color.opacity(0.7))
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.03))
        .cornerRadius(AppRadius.badge)
    }

    // MARK: - Formatting

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return String(formatter.string(from: date).prefix(2))
    }

    private func formatCompact(_ value: Int) -> String {
        switch value {
        case ..<1_000:
            return "\(value)"
        case ..<1_000_000:
            let k = Double(value) / 1_000
            return k >= 100 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
        default:
            let m = Double(value) / 1_000_000
            return m >= 100 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        }
    }
}
