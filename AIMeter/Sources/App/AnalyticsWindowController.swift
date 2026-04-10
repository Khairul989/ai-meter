import Cocoa
import SwiftUI

final class AnalyticsWindowController: NSWindowController {
    private static var instance: AnalyticsWindowController?
    private static var hostingView: NSHostingView<AnalyticsView>?
    static let analyticsService = SessionAnalyticsService()

    static func show() {
        if let existing = instance {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Code Analytics"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 650)
        window.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
        window.center()

        let view = AnalyticsView(service: analyticsService)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
        window.contentView = hosting
        hostingView = hosting

        let controller = AnalyticsWindowController(window: window)
        instance = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
