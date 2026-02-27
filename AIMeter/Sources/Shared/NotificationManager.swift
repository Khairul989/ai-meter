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

    private let defaults = UserDefaults.standard

    // Internal so tests can read it directly
    var tracker: NotificationTracker {
        get {
            guard let data = defaults.data(forKey: "notificationTracker"),
                  let decoded = try? JSONDecoder().decode(NotificationTracker.self, from: data)
            else { return NotificationTracker() }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "notificationTracker")
            }
        }
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(metrics: [MetricSnapshot]) {
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
        if utilization >= critical { return .critical }
        if utilization >= warning { return .warning }
        return .none
    }

    private func fire(metric: MetricSnapshot, level: NotificationLevel) {
        let content = UNMutableNotificationContent()
        let prefix = level == .critical ? "⚠️ " : ""
        content.title = "\(prefix)\(metric.label) at \(metric.utilization)%"
        if let detail = metric.detail { content.body = detail }
        let request = UNNotificationRequest(
            identifier: "\(metric.key).\(level.rawValue)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
}

// MARK: - Helpers

private extension Int {
    func nonZeroOrDefault(_ value: Int) -> Int {
        self == 0 ? value : self
    }
}
