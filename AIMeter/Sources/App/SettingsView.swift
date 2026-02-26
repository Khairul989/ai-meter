import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 60
    @AppStorage("timezoneOffset") private var timezoneOffset: Int = 8 // UTC+8 Malaysia
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Picker("Refresh interval", selection: $refreshInterval) {
                Text("30 seconds").tag(30.0)
                Text("60 seconds").tag(60.0)
                Text("120 seconds").tag(120.0)
            }

            Picker("Timezone", selection: $timezoneOffset) {
                Text("UTC-8 (PST)").tag(-8)
                Text("UTC-5 (EST)").tag(-5)
                Text("UTC+0 (GMT)").tag(0)
                Text("UTC+1 (CET)").tag(1)
                Text("UTC+8 (MYT)").tag(8)
                Text("UTC+9 (JST)").tag(9)
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }

            Button("Quit AIMeter") {
                NSApp.terminate(nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 300, height: 200)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
