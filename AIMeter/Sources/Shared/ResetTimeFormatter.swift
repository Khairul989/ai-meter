import Foundation

enum ResetTimeFormatter {
    /// Format a reset date for display, relative to now.
    /// Short format: "3h01" for 5-hour resets (same day).
    /// Long format: "Thu 11am" for 7-day resets.
    static func format(_ date: Date?, style: Style, timeZone: TimeZone = .current) -> String? {
        guard let date else { return nil }

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.timeZone = timeZone

        switch style {
        case .countdown:
            let diff = calendar.dateComponents([.hour, .minute], from: Date(), to: date)
            guard let h = diff.hour, let m = diff.minute, h >= 0, m >= 0 else { return nil }
            return String(format: "%dh%02d", h, m)
        case .dayTime:
            formatter.dateFormat = "EEE h:mma"
            return formatter.string(from: date).lowercased()
        }
    }

    enum Style {
        case countdown  // "3h01"
        case dayTime    // "thu 11:00am"
    }
}
