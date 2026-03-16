import Foundation

enum PeakHoursHelper {
    // Promotion period: March 13-27, 2026 (inclusive, in ET)
    private static let peakTimeZone = TimeZone(identifier: "America/New_York")!

    // Peak hours: weekdays 8 AM – 2 PM ET
    private static let peakStartHour = 8
    private static let peakEndHour = 14

    static func isPromotionActive(now: Date = .now) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = peakTimeZone
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = components.year, let month = components.month, let day = components.day else { return false }
        return year == 2026 && month == 3 && day >= 13 && day <= 27
    }

    static func isPeakHours(now: Date = .now) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = peakTimeZone
        let components = calendar.dateComponents([.hour, .weekday], from: now)
        guard let hour = components.hour, let weekday = components.weekday else { return false }
        // weekday: 1 = Sunday, 7 = Saturday
        let isWeekday = weekday >= 2 && weekday <= 6
        let isDuringPeakHours = hour >= peakStartHour && hour < peakEndHour
        return isWeekday && isDuringPeakHours
    }

    static func isDoubledUsage(now: Date = .now) -> Bool {
        isPromotionActive(now: now) && !isPeakHours(now: now)
    }
}
