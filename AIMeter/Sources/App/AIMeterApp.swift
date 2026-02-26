import SwiftUI

@main
struct AIMeterApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var copilotService = CopilotService()
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60

    var body: some Scene {
        MenuBarExtra {
            PopoverView(service: service, copilotService: copilotService)
                .task {
                    service.start(interval: refreshInterval)
                    copilotService.start(interval: refreshInterval)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    service.stop()
                    service.start(interval: newValue)
                    copilotService.stop()
                    copilotService.start(interval: newValue)
                }
        } label: {
            MenuBarLabel(utilization: max(service.usageData.highestUtilization, copilotService.copilotData.highestUtilization))
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let utilization: Int

    var body: some View {
        Image(systemName: "sparkles")
            .foregroundStyle(UsageColor.forUtilization(utilization))
    }
}
