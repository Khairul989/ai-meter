import Foundation

enum PeakHoursHelper {
    // Peak hours: weekdays 1 PM – 7 PM GMT (per Anthropic's Thariq announcement Mar 27, 2026)
    // GMT is UTC with no offset in Etc/GMT convention
    static func isPeakHours(now: Date = .now) -> Bool {
        var gmtCalendar = Calendar(identifier: .gregorian)
        gmtCalendar.timeZone = TimeZone(identifier: "Etc/GMT")!
        let components = gmtCalendar.dateComponents([.hour, .weekday], from: now)
        guard let hour = components.hour, let weekday = components.weekday else { return false }
        // weekday: 1 = Sunday, 7 = Saturday
        let isWeekday = weekday >= 2 && weekday <= 6
        let isDuringPeakHours = hour >= 13 && hour < 19
        return isWeekday && isDuringPeakHours
    }
}
