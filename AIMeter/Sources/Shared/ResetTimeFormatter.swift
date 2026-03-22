import Foundation

enum ResetTimeFormatter {
    /// Format a reset date for display, relative to a reference date.
    /// Countdown format: "3h 1m" for 5-hour resets.
    /// Day/time format: "Thu 11am" for 7-day resets.
    static func format(_ date: Date?, style: Style, timeZone: TimeZone = .current, now: Date = Date()) -> String? {
        guard let date else { return nil }

        switch style {
        case .countdown:
            let diff = Calendar.current.dateComponents([.hour, .minute], from: now, to: date)
            guard let h = diff.hour, let m = diff.minute, h >= 0, m >= 0 else { return nil }
            return "\(h)h \(m)m"
        case .dayTime:
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.dateFormat = "EEE h:mma"
            return formatter.string(from: date).lowercased()
        case .dateTime:
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.dateFormat = "MMM d, h:mma"
            return formatter.string(from: date).lowercased()
        }
    }

    enum Style {
        case countdown  // "3h 1m"
        case dayTime    // "thu 11:00am"
        case dateTime   // "mar 1, 8:00am"
    }
}
