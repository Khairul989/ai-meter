import SwiftUI
import AppKit

// Thin wrapper — opens the dedicated settings window instead of rendering inline.
// Kept as a fallback while PopoverView still references it; Task #2 will remove this reference.
struct InlineSettingsView: View {
    @ObservedObject var updaterManager: UpdaterManager
    @ObservedObject var authManager: SessionAuthManager
    @ObservedObject var codexAuthManager: CodexAuthManager
    @ObservedObject var kimiAuthManager: KimiAuthManager
    @Binding var selectedTab: Tab
    @EnvironmentObject var historyService: QuotaHistoryService
    @EnvironmentObject var copilotHistoryService: CopilotHistoryService

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Button {
                SettingsWindowController.show(
                    updaterManager: updaterManager,
                    authManager: authManager,
                    codexAuthManager: codexAuthManager,
                    kimiAuthManager: kimiAuthManager,
                    historyService: historyService,
                    copilotHistoryService: copilotHistoryService
                )
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 13))
                    Text("Open Settings")
                        .font(.system(size: 13))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
