import AppKit
import SwiftUI

// Dedicated settings window — opened separately from the popover, never reuses the main panel.
final class SettingsWindowController: NSWindowController {
    private static var instance: SettingsWindowController?
    private static var hostingView: NSHostingView<SettingsView>?

    static func show(
        updaterManager: UpdaterManager,
        authManager: SessionAuthManager,
        codexAuthManager: CodexAuthManager,
        kimiAuthManager: KimiAuthManager,
        historyService: QuotaHistoryService,
        copilotHistoryService: CopilotHistoryService
    ) {
        if let existing = instance {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            hostingView?.rootView = SettingsView(
                updaterManager: updaterManager,
                authManager: authManager,
                codexAuthManager: codexAuthManager,
                kimiAuthManager: kimiAuthManager,
                historyService: historyService,
                copilotHistoryService: copilotHistoryService
            )
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.styleMask.remove(.resizable)
        window.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        window.center()

        let view = SettingsView(
            updaterManager: updaterManager,
            authManager: authManager,
            codexAuthManager: codexAuthManager,
            kimiAuthManager: kimiAuthManager,
            historyService: historyService,
            copilotHistoryService: copilotHistoryService
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        window.contentView = hosting
        hostingView = hosting

        let controller = SettingsWindowController(window: window)
        instance = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
