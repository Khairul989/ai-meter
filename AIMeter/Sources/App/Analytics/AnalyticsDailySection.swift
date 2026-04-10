import SwiftUI
import Charts

private enum AnalyticsDailyRange: String, CaseIterable {
    case sevenDays = "7d"
    case fourteenDays = "14d"
    case thirtyDays = "30d"
    case all = "All"

    var dayCount: Int? {
        switch self {
        case .sevenDays: return 7
        case .fourteenDays: return 14
        case .thirtyDays: return 30
        case .all: return nil
        }
    }
}

private struct AnalyticsDailySegment: Identifiable {
    let id: String
    let date: Date
    let label: String
    let start: Int
    let end: Int
    let color: Color
}

struct AnalyticsDailySection: View {
    let result: AnalyticsResult

    @State private var selectedRange: AnalyticsDailyRange = .thirtyDays
    @State private var hoverDate: Date?

    private let claudeAccent = Color(red: 0.85, green: 0.55, blue: 0.35)
    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    private var filteredUsage: [DailyAnalytics] {
        let sorted = result.dailyUsage.sorted { $0.date < $1.date }
        guard let days = selectedRange.dayCount else { return sorted }
        return Array(sorted.suffix(days))
    }

    var body: some View {
        let usage = filteredUsage

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Usage")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(AnalyticsDailyRange.allCases, id: \.rawValue) { range in
                        Button {
                            selectedRange = range
                        } label: {
                            Text(range.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(selectedRange == range ? .white : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(selectedRange == range ? Color.white.opacity(0.15) : .clear)
                                .cornerRadius(AppRadius.badge)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.white.opacity(0.05))
                .cornerRadius(AppRadius.button)
            }

            chartView(usage: usage)
            summaryPills(usage: usage)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private func chartView(usage: [DailyAnalytics]) -> some View {
        let points = usage
        let maxTokens = max(points.map(\.totalTokens).max() ?? 0, 1)
        let maxCost = max(points.map(\.estimatedCostUSD).max() ?? 0, 0.01)

        return Chart {
            ForEach(dailySegments(usage: usage)) { segment in
                BarMark(
                    x: .value("Date", segment.date, unit: .day),
                    yStart: .value("Start", segment.start),
                    yEnd: .value("Tokens", segment.end)
                )
                .foregroundStyle(segment.color)
            }

            ForEach(points) { point in
                let scaledCost = point.estimatedCostUSD / maxCost * Double(maxTokens)
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Cost", scaledCost)
                )
                .foregroundStyle(Color.white.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 1.2))
                .interpolationMethod(.catmullRom)
            }

            if let hoverDate, let nearest = nearestPoint(to: hoverDate, in: usage) {
                RuleMark(x: .value("Hover", nearest.date))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dayLabel(nearest.date))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white)
                            Text(ModelPricing.formatTokens(nearest.totalTokens))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(claudeAccent)
                            Text(ModelPricing.formatCost(nearest.estimatedCostUSD))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.cyan)
                        }
                        .padding(6)
                        .background(Color.black.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(max(usage.count, 2), 6))) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(shortDayLabel(date))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let tokens = value.as(Int.self) {
                        Text(ModelPricing.formatTokens(tokens))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    } else if let tokens = value.as(Double.self) {
                        Text(ModelPricing.formatTokens(Int(tokens)))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 140)
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

    private func dailySegments(usage: [DailyAnalytics]) -> [AnalyticsDailySegment] {
        usage.reduce(into: [AnalyticsDailySegment]()) { segments, day in
            let inputEnd = day.inputTokens
            let cacheCreateEnd = inputEnd + day.cacheCreateTokens
            let cacheReadEnd = cacheCreateEnd + day.cacheReadTokens
            let outputEnd = cacheReadEnd + day.outputTokens
            segments.append(contentsOf: [
                AnalyticsDailySegment(id: "\(day.id)-input", date: day.date, label: "Input", start: 0, end: inputEnd, color: claudeAccent),
                AnalyticsDailySegment(id: "\(day.id)-cacheCreate", date: day.date, label: "Cache Create", start: inputEnd, end: cacheCreateEnd, color: .green),
                AnalyticsDailySegment(id: "\(day.id)-cacheRead", date: day.date, label: "Cache Read", start: cacheCreateEnd, end: cacheReadEnd, color: .cyan),
                AnalyticsDailySegment(id: "\(day.id)-output", date: day.date, label: "Output", start: cacheReadEnd, end: outputEnd, color: Color.white.opacity(0.8)),
            ])
        }
    }

    private func summaryPills(usage: [DailyAnalytics]) -> some View {
        let points = usage
        let totalTokens = points.reduce(0) { $0 + $1.totalTokens }
        let totalCost = points.reduce(0.0) { $0 + $1.estimatedCostUSD }
        let days = max(points.count, 1)
        let avgTokensPerDay = totalTokens / days
        let avgCostPerDay = totalCost / Double(days)
        let peak = points.max { $0.totalTokens < $1.totalTokens }

        return HStack(spacing: 8) {
            summaryPill(icon: "waveform.path.ecg", color: claudeAccent, text: "avg/day \(ModelPricing.formatTokens(avgTokensPerDay))")
            summaryPill(
                icon: "flame.fill",
                color: .yellow,
                text: peak.map { "peak \(shortDayLabel($0.date)) \(ModelPricing.formatTokens($0.totalTokens))" } ?? "peak n/a"
            )
            summaryPill(icon: "dollarsign.circle", color: .green, text: "avg cost/day \(ModelPricing.formatCost(avgCostPerDay))")
        }
    }

    private func summaryPill(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 7))
                .foregroundColor(color.opacity(0.8))
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.03))
        .cornerRadius(AppRadius.badge)
    }

    private func nearestPoint(to date: Date, in usage: [DailyAnalytics]) -> DailyAnalytics? {
        usage.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func shortDayLabel(_ date: Date) -> String {
        Self.shortDayFormatter.string(from: date)
    }

    private func dayLabel(_ date: Date) -> String {
        Self.fullDayFormatter.string(from: date)
    }
}
