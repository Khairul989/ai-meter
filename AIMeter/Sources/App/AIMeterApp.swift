import SwiftUI

@main
struct AIMeterApp: App {
    @StateObject private var service = UsageService()
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60

    var body: some Scene {
        MenuBarExtra {
            PopoverView(service: service)
                .task {
                    service.start(interval: refreshInterval)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    service.stop()
                    service.start(interval: newValue)
                }
        } label: {
            MenuBarLabel(utilization: service.usageData.highestUtilization)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarLabel: View {
    let utilization: Int

    var body: some View {
        Image(systemName: "sparkles")
            .foregroundStyle(UsageColor.forUtilization(utilization))
    }
}
