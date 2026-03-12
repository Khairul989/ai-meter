import SwiftUI
import Charts

struct CopilotChartView: View {
    @ObservedObject var historyService: CopilotHistoryService
    @State private var selectedRange: QuotaTimeRange = .hour6
    @State private var selectedMetric: CopilotChartMetric = .utilization

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

            Picker("", selection: $selectedMetric) {
                ForEach(CopilotChartMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            let points = historyService.downsampledPoints(for: selectedRange)

            if points.isEmpty {
                Text("No history yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            } else {
                CopilotInnerChart(
                    points: points,
                    selectedRange: selectedRange,
                    selectedMetric: selectedMetric
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(AppRadius.card)
    }
}

private struct CopilotInnerChart: View {
    let points: [CopilotHistoryDataPoint]
    let selectedRange: QuotaTimeRange
    let selectedMetric: CopilotChartMetric
    @State private var hoverDate: Date?

    private var chatPoints: [ChartPoint] { makePoints("Chat") }
    private var completionsPoints: [ChartPoint] { makePoints("Completions") }
    private var premiumPoints: [ChartPoint] { makePoints("Premium") }

    var body: some View {
        let chat = chatPoints
        let completions = completionsPoints
        let premium = premiumPoints

        if selectedMetric == .utilization {
            baseChart(chat: chat, completions: completions, premium: premium)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%").font(.system(size: 9))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                            .foregroundStyle(Color.white.opacity(0.1))
                    }
                }
        } else {
            let maxRemaining = points.flatMap {
                [$0.chatRemaining, $0.completionsRemaining, $0.premiumRemaining].compactMap { $0 }
            }.max() ?? 1
            baseChart(chat: chat, completions: completions, premium: premium)
                .chartYScale(domain: 0...max(maxRemaining, 1))
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)").font(.system(size: 9))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2]))
                            .foregroundStyle(Color.white.opacity(0.1))
                    }
                }
        }
    }

    @ChartContentBuilder
    private func seriesMarks(_ pts: [ChartPoint]) -> some ChartContent {
        ForEach(pts) { pt in
            LineMark(
                x: .value("Time", pt.timestamp),
                y: .value("Value", pt.value)
            )
            .foregroundStyle(by: .value("Series", pt.series))
            .interpolationMethod(.monotone)

            PointMark(
                x: .value("Time", pt.timestamp),
                y: .value("Value", pt.value)
            )
            .foregroundStyle(by: .value("Series", pt.series))
            .symbolSize(16)
        }
    }

    private func baseChart(chat: [ChartPoint], completions: [ChartPoint], premium: [ChartPoint]) -> some View {
        Chart {
            seriesMarks(chat)
            seriesMarks(completions)
            seriesMarks(premium)

            if let hoverDate {
                RuleMark(x: .value("Hover", hoverDate))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center) {
                        if let nearest = nearestCopilotPoint(to: hoverDate, in: points) {
                            VStack(spacing: 2) {
                                if let chat = nearest.chatUtilization {
                                    Text("Chat: \(chat)%")
                                        .font(.system(size: 8))
                                        .foregroundColor(.blue)
                                }
                                if let premium = nearest.premiumUtilization {
                                    Text("Premium: \(premium)%")
                                        .font(.system(size: 8))
                                        .foregroundColor(.purple)
                                }
                            }
                            .padding(4)
                            .background(Color.black.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.badge))
                        }
                    }
            }
        }
        .chartXScale(domain: Date.now.addingTimeInterval(-selectedRange.interval)...Date.now)
        .chartXAxis(.hidden)
        .chartForegroundStyleScale([
            "Chat": Color.blue,
            "Completions": Color.green,
            "Premium": Color.purple
        ])
        .chartLegend(.visible)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 4)
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

    private func nearestCopilotPoint(to date: Date, in points: [CopilotHistoryDataPoint]) -> CopilotHistoryDataPoint? {
        points.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }

    private func makePoints(_ series: String) -> [ChartPoint] {
        points.compactMap { pt -> ChartPoint? in
            let value: Int?
            switch (series, selectedMetric) {
            case ("Chat", .utilization): value = pt.chatUtilization
            case ("Chat", .remaining): value = pt.chatRemaining
            case ("Completions", .utilization): value = pt.completionsUtilization
            case ("Completions", .remaining): value = pt.completionsRemaining
            case ("Premium", .utilization): value = pt.premiumUtilization
            case ("Premium", .remaining): value = pt.premiumRemaining
            default: value = nil
            }
            guard let v = value else { return nil }
            return ChartPoint(id: pt.id, timestamp: pt.timestamp, value: v, series: series)
        }
    }
}

private struct ChartPoint: Identifiable {
    let id: UUID
    let timestamp: Date
    let value: Int
    let series: String
}
