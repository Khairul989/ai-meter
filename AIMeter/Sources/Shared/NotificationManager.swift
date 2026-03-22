import AppKit
import Foundation
import UserNotifications

// MARK: - Types

enum NotificationLevel: Int, Codable, Comparable {
    case none = 0
    case warning = 1
    case critical = 2

    static func < (lhs: NotificationLevel, rhs: NotificationLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct MetricSnapshot {
    let key: String        // e.g. "claude.session"
    let label: String      // e.g. "Claude Session" — used in notification title
    let utilization: Int   // 0-100
    let detail: String?    // used as notification body, e.g. "Resets in 3h" or "42/300 remaining"
}

struct NotificationTracker: Codable {
    var levels: [String: NotificationLevel] = [:]

    func level(for key: String) -> NotificationLevel {
        levels[key] ?? .none
    }

    mutating func set(_ key: String, to level: NotificationLevel) {
        levels[key] = level
    }
}

// MARK: - Manager

final class NotificationManager {
    static let shared = NotificationManager()

    @MainActor
    private static let quotaTracker = SessionQuotaTracker()

    private let defaults = UserDefaults.standard
    private var trackerCache: NotificationTracker?

    // Internal so tests can read it directly
    var tracker: NotificationTracker {
        get {
            if let cached = trackerCache { return cached }
            guard let data = defaults.data(forKey: "notificationTracker"),
                  let decoded = try? JSONDecoder().decode(NotificationTracker.self, from: data)
            else { return NotificationTracker() }
            trackerCache = decoded
            return decoded
        }
        set {
            trackerCache = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "notificationTracker")
            }
        }
    }

    func requestPermission() {
        // NSUserNotification doesn't require explicit permission.
        // Register UNUserNotification categories for when we switch to signed builds.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("[NotificationManager] UNAuth granted: \(granted), error: \(String(describing: error))")
        }

        // Register categories
        let snooze1h = UNNotificationAction(identifier: "SNOOZE_1H", title: "Snooze 1h", options: [])
        let snoozeReset = UNNotificationAction(identifier: "SNOOZE_RESET", title: "Snooze until reset", options: [])
        let usageAlertCategory = UNNotificationCategory(identifier: "USAGE_ALERT", actions: [snooze1h, snoozeReset], intentIdentifiers: [])
        let viewRecap = UNNotificationAction(identifier: "VIEW_RECAP", title: "View Recap", options: [.foreground])
        let recapCategory = UNNotificationCategory(identifier: "RECAP_READY", actions: [viewRecap], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([usageAlertCategory, recapCategory])

    }

    func fireTestNotification() {
        fireViaOsascript(title: "⚠️ Claude Session at 85%", body: "Resets in 2h 30m")
    }

    func fireRecapNotification(for month: Date) {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM"
        let monthName = fmt.string(from: month)
        fireViaOsascript(
            title: "Your \(monthName) recap is ready!",
            body: "See how you used AI this month."
        )
    }

    func check(metrics: [MetricSnapshot]) {
        let snoozeUntil = defaults.double(forKey: "snoozeUntil")
        guard Date().timeIntervalSince1970 > snoozeUntil else { return }
        guard defaults.bool(forKey: "notificationsEnabled") else { return }
        let warnThreshold = defaults.integer(forKey: "notifyWarning").nonZeroOrDefault(80)
        let critThreshold = defaults.integer(forKey: "notifyCritical").nonZeroOrDefault(90)

        var tracker = self.tracker
        for metric in metrics {
            let current = level(for: metric.utilization, warning: warnThreshold, critical: critThreshold)
            let previous = tracker.level(for: metric.key)

            if current > previous {
                fire(metric: metric, level: current)
                tracker.set(metric.key, to: current)
            } else if current == .none {
                // Reset so future crossings notify again
                tracker.set(metric.key, to: .none)
            }
        }
        self.tracker = tracker
    }

    // Internal so tests can call directly
    func level(for utilization: Int, warning: Int, critical: Int) -> NotificationLevel {
        // Ensure warning < critical to prevent logic inversion
        let safeWarning = min(warning, critical - 1)
        if utilization >= critical { return .critical }
        if utilization >= safeWarning { return .warning }
        return .none
    }

    private func fire(metric: MetricSnapshot, level: NotificationLevel) {
        let prefix = level == .critical ? "⚠️ " : ""
        let title = "\(prefix)\(metric.label) at \(metric.utilization)%"
        fireViaOsascript(title: title, body: metric.detail)
    }

    private func fireViaOsascript(title: String, body: String?, sound: Bool = true) {
        DispatchQueue.global(qos: .utility).async {
            // Escape double quotes for AppleScript
            let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedBody = (body ?? "").replacingOccurrences(of: "\"", with: "\\\"")

            var script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""
            if sound {
                script += " sound name \"default\""
            }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", script]
            try? task.run()
        }
    }

    func handleSnoozeAction(_ actionIdentifier: String) {
        switch actionIdentifier {
        case "SNOOZE_1H":
            defaults.set(Date().addingTimeInterval(3600).timeIntervalSince1970, forKey: "snoozeUntil")
        case "SNOOZE_RESET":
            // Snooze for 5 hours (typical reset window)
            defaults.set(Date().addingTimeInterval(18000).timeIntervalSince1970, forKey: "snoozeUntil")
        default:
            break
        }
    }

    func handleNotificationAction(_ actionIdentifier: String, for categoryIdentifier: String) {
        if categoryIdentifier == "RECAP_READY" && actionIdentifier == "VIEW_RECAP" {
            NotificationCenter.default.post(name: .openLatestRecap, object: nil)
        } else {
            handleSnoozeAction(actionIdentifier)
        }
    }

    // MARK: - Session depletion tracking

    @MainActor
    func checkSessionDepletion(provider: String, usagePercent: Double) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else { return }
        guard let transition = NotificationManager.quotaTracker.update(provider: provider, usagePercent: usagePercent) else { return }
        switch transition {
        case .depleted:
            fireViaOsascript(
                title: "\(provider) Session Depleted",
                body: "Usage at 100% — will notify when available again."
            )
        case .restored:
            fireViaOsascript(
                title: "\(provider) Session Restored",
                body: "Session quota is available again."
            )
        }
    }

    // MARK: - MetricSnapshot factories

    static func metrics(from data: UsageData) -> [MetricSnapshot] {
        var result: [MetricSnapshot] = [
            MetricSnapshot(
                key: "claude.session",
                label: "Claude Session",
                utilization: data.fiveHour.utilization,
                detail: ResetTimeFormatter.format(data.fiveHour.resetsAt, style: .countdown, timeZone: .current)
            ),
            MetricSnapshot(
                key: "claude.weekly",
                label: "Claude Weekly",
                utilization: data.sevenDay.utilization,
                detail: ResetTimeFormatter.format(data.sevenDay.resetsAt, style: .dayTime, timeZone: .current)
            )
        ]
        if let sonnet = data.sevenDaySonnet {
            result.append(MetricSnapshot(
                key: "claude.sonnet",
                label: "Claude Sonnet",
                utilization: sonnet.utilization,
                detail: ResetTimeFormatter.format(sonnet.resetsAt, style: .dayTime, timeZone: .current)
            ))
        }
        if let credits = data.extraCredits {
            result.append(MetricSnapshot(
                key: "claude.credits",
                label: "Claude Credits",
                utilization: credits.utilization,
                detail: String(format: "$%.2f remaining", (credits.limit - credits.used) / 100)
            ))
        }
        return result
    }

    static func metrics(from data: CopilotUsageData) -> [MetricSnapshot] {
        guard !data.premiumInteractions.unlimited else { return [] }
        return [MetricSnapshot(
            key: "copilot.premium",
            label: "Copilot Premium",
            utilization: data.premiumInteractions.utilization,
            detail: "\(data.premiumInteractions.remaining)/\(data.premiumInteractions.entitlement) remaining"
        )]
    }

    static func metrics(from data: GLMUsageData) -> [MetricSnapshot] {
        return [MetricSnapshot(
            key: "glm.tokens",
            label: "GLM Tokens",
            utilization: data.tokensPercent,
            detail: data.tier.isEmpty ? "" : "\(data.tier.capitalized) tier"
        )]
    }

    static func metrics(from data: KimiUsageData) -> [MetricSnapshot] {
        // Kimi reports balance (CNY), not utilization %.
        // We surface this as an informational metric only (0% utilization so no threshold alerts).
        return [MetricSnapshot(
            key: "kimi.balance",
            label: "Kimi Balance",
            utilization: 0,
            detail: String(format: "¥%.4f available", data.totalBalance)
        )]
    }
}

// MARK: - Helpers

private extension Int {
    func nonZeroOrDefault(_ value: Int) -> Int {
        self == 0 ? value : self
    }
}

extension Notification.Name {
    static let openLatestRecap = Notification.Name("com.khairul.aimeter.openLatestRecap")
}
