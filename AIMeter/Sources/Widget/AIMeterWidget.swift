import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let usageData: UsageData
    let copilotData: CopilotUsageData?

    static let placeholder = UsageEntry(
        date: Date(),
        usageData: UsageData(
            fiveHour: RateLimit(utilization: 37, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: RateLimit(utilization: 54, resetsAt: Date().addingTimeInterval(86400)),
            sevenDaySonnet: RateLimit(utilization: 3, resetsAt: Date().addingTimeInterval(86400)),
            extraCredits: nil,
            fetchedAt: Date()
        ),
        copilotData: CopilotUsageData(
            plan: "individual",
            chat: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            completions: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            premiumInteractions: CopilotQuota(utilization: 88, remaining: 35, entitlement: 300, unlimited: false),
            resetDate: Date().addingTimeInterval(86400 * 3),
            fetchedAt: Date()
        )
    )
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let data = SharedDefaults.load() ?? .empty
        let copilot = SharedDefaults.loadCopilot()
        completion(UsageEntry(date: Date(), usageData: data, copilotData: copilot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let data = SharedDefaults.load() ?? .empty
        let copilot = SharedDefaults.loadCopilot()
        let entry = UsageEntry(date: Date(), usageData: data, copilotData: copilot)
        // Refresh every 5 minutes
        let nextUpdate = Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

@main
struct AIMeterWidget: Widget {
    let kind = "AIMeterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            WidgetEntryView(entry: entry)
                .containerBackground(.black.gradient, for: .widget)
        }
        .configurationDisplayName("AI Meter")
        .description("Monitor Claude API usage limits")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: UsageEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(data: entry.usageData, copilotData: entry.copilotData)
        case .systemMedium:
            MediumWidgetView(data: entry.usageData, copilotData: entry.copilotData)
        default:
            SmallWidgetView(data: entry.usageData, copilotData: entry.copilotData)
        }
    }
}
