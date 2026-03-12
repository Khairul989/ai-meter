import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let usageData: UsageData
    let copilotData: CopilotUsageData?
    let glmData: GLMUsageData?

    static let placeholder = UsageEntry(
        date: Date(),
        usageData: UsageData(
            fiveHour: RateLimit(utilization: 37, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: RateLimit(utilization: 54, resetsAt: Date().addingTimeInterval(86400)),
            sevenDaySonnet: RateLimit(utilization: 3, resetsAt: Date().addingTimeInterval(86400)),
            extraCredits: nil,
            planName: nil,
            fetchedAt: Date()
        ),
        copilotData: CopilotUsageData(
            plan: "individual",
            chat: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            completions: CopilotQuota(utilization: 0, remaining: 0, entitlement: 0, unlimited: true),
            premiumInteractions: CopilotQuota(utilization: 88, remaining: 35, entitlement: 300, unlimited: false),
            resetDate: Date().addingTimeInterval(86400 * 3),
            fetchedAt: Date()
        ),
        glmData: GLMUsageData(tokensPercent: 12, tier: "free", fetchedAt: Date())
    )
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let data = SharedDefaults.load() ?? .empty
        let copilot = SharedDefaults.loadCopilot()
        let glm = SharedDefaults.loadGLM()
        completion(UsageEntry(date: Date(), usageData: data, copilotData: copilot, glmData: glm))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let data = SharedDefaults.load() ?? .empty
        let copilot = SharedDefaults.loadCopilot()
        let glm = SharedDefaults.loadGLM()
        let entry = UsageEntry(date: Date(), usageData: data, copilotData: copilot, glmData: glm)
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
                .containerBackground(for: .widget) {
                    let highest = max(
                        entry.usageData.highestUtilization,
                        entry.copilotData?.highestUtilization ?? 0,
                        entry.glmData?.tokensPercent ?? 0
                    )
                    let bgColor: Color = if highest >= 95 {
                        Color(hue: 0.0, saturation: 0.4, brightness: 0.12)
                    } else if highest >= 80 {
                        Color(hue: 0.08, saturation: 0.4, brightness: 0.12)
                    } else {
                        Color.black
                    }
                    LinearGradient(colors: [bgColor, bgColor.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("AI Meter")
        .description("Monitor AI usage — Claude and Copilot")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
        case .systemLarge:
            LargeWidgetView(data: entry.usageData, copilotData: entry.copilotData, glmData: entry.glmData)
        default:
            SmallWidgetView(data: entry.usageData, copilotData: entry.copilotData)
        }
    }
}
