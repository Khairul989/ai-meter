import SwiftUI
import Charts

struct QuotaChartView: View {
    @ObservedObject var historyService: QuotaHistoryService
    @State private var selectedRange: QuotaTimeRange = .day1
    @State private var hoverDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trend")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Picker("", selection: $selectedRange) {
                    ForEach(QuotaTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }

            let points = historyService.downsampledPoints(for: selectedRange)

            if points.isEmpty {
                Text("No history yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                chartView(points: points)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(AppRadius.card)
    }

    @ViewBuilder
    private func chartView(points: [QuotaDataPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.session * 100)
                )
                .foregroundStyle(by: .value("Metric", "Session"))
                .interpolationMethod(.monotone)
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.weekly * 100)
                )
                .foregroundStyle(by: .value("Metric", "Weekly"))
                .interpolationMethod(.monotone)
            }

            if let hoverDate {
                RuleMark(x: .value("Hover", hoverDate))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center) {
                        if let nearest = nearestPoint(to: hoverDate, in: points) {
                            VStack(spacing: 2) {
                                Text(String(format: "S: %.0f%%", nearest.session * 100))
                                    .font(.system(size: 8))
                                    .foregroundColor(.blue)
                                Text(String(format: "W: %.0f%%", nearest.weekly * 100))
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                            }
                            .padding(4)
                            .background(Color.black.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
                        }
                    }
            }
        }
        .chartXScale(domain: Date.now.addingTimeInterval(-selectedRange.interval)...Date.now)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)%")
                            .font(.system(size: 9))
                    }
                }
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.white.opacity(0.1))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: xAxisFormat)
                    .font(.system(size: 9))
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                    .foregroundStyle(Color.white.opacity(0.1))
            }
        }
        .chartForegroundStyleScale([
            "Session": Color.blue,
            "Weekly": Color.orange
        ])
        .chartLegend(.visible)
        .chartLegend(position: .bottom, spacing: 4)
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

    private func nearestPoint(to date: Date, in points: [QuotaDataPoint]) -> QuotaDataPoint? {
        points.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedRange {
        case .hour1:
            return .dateTime.hour().minute()
        case .hour6, .day1:
            return .dateTime.hour()
        case .day7:
            return .dateTime.weekday(.abbreviated)
        }
    }
}
