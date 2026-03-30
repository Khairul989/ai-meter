import Foundation

enum PeakHoursHelper {
    // Peak hours: weekdays 5 AM – 11 AM PT (8 AM – 2 PM ET / 1 PM – 7 PM GMT)
    // During these hours, Claude session limits drain faster than off-peak.
    private static let peakTimeZone = TimeZone(identifier: "America/Los_Angeles")!
    private static let peakStartHour = 5
    private static let peakEndHour = 11

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
}
