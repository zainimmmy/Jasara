import Foundation

extension Calendar {
    /// One calendar for the whole app so "today" means the same thing everywhere.
    static func app(firstWeekdayIsMonday: Bool = false) -> Calendar {
        var cal = Calendar.current
        cal.firstWeekday = firstWeekdayIsMonday ? 2 : 1
        return cal
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    var minutesSinceMidnight: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func today(atMinutes minutes: Int, on day: Date = .now) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                              second: 0, of: day.startOfDay) ?? day
    }

    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}

enum TimeUntil {
    /// "Alarm set for 7 hr and 30 min from now". Minutes round up, so an alarm
    /// 29 minutes 50 seconds away reads as 30 min, the way people think of it.
    static func alarmSetMessage(until date: Date, from now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds >= 60 else { return "Alarm set for less than a minute from now" }
        let total = Int((seconds / 60).rounded(.up))
        let days = total / 1440
        let hours = (total % 1440) / 60
        let minutes = total % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days) \(days == 1 ? "day" : "days")") }
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 { parts.append("\(minutes) min") }

        let joined: String
        switch parts.count {
        case 1: joined = parts[0]
        case 2: joined = "\(parts[0]) and \(parts[1])"
        default: joined = "\(parts[0]), \(parts[1]) and \(parts[2])"
        }
        return "Alarm set for \(joined) from now"
    }
}

enum Weekdays {
    static let symbols = ["S", "M", "T", "W", "T", "F", "S"]
    static let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Mask bit for a Calendar weekday (1 = Sunday).
    static func bit(_ weekday: Int) -> Int { 1 << (weekday - 1) }

    static func contains(_ mask: Int, weekday: Int) -> Bool { mask & bit(weekday) != 0 }

    static func toggle(_ mask: Int, weekday: Int) -> Int { mask ^ bit(weekday) }

    static let weekdayMask = (2...6).reduce(0) { $0 | bit($1) }
    static let everyDay = (1...7).reduce(0) { $0 | bit($1) }

    static func describe(_ mask: Int) -> String {
        switch mask {
        case 0: return "Once"
        case everyDay: return "Every day"
        case weekdayMask: return "Weekdays"
        default:
            let days = (1...7).filter { contains(mask, weekday: $0) }.map { names[$0 - 1] }
            return days.isEmpty ? "Once" : days.joined(separator: " ")
        }
    }
}

extension Int {
    /// 90 -> "1h 30m", 25 -> "25m"
    var durationLabel: String {
        if self < 60 { return "\(self)m" }
        let h = self / 60, m = self % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
    /// Seconds -> "24:59"
    var clockLabel: String {
        let total = Swift.max(0, self)
        let m = total / 60, s = total % 60
        if m >= 60 { return String(format: "%d:%02d:%02d", m / 60, m % 60, s) }
        return String(format: "%d:%02d", m, s)
    }
}
