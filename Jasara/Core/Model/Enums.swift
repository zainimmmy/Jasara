import Foundation

/// Raw values are persisted, so they are fixed forever. Add cases, never renumber.

enum Priority: Int, CaseIterable, Identifiable, Codable {
    case none = 0, low = 1, medium = 2, high = 3

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: return "To do"
        case .low: return "Low priority"
        case .medium: return "Medium priority"
        case .high: return "High priority"
        }
    }
    var shortTitle: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
    var palette: Palette {
        switch self {
        case .none: return .sand
        case .low: return .sky
        case .medium: return .butter
        case .high: return .blush
        }
    }
    /// High first, unsorted last.
    static var displayOrder: [Priority] { [.high, .medium, .low, .none] }
}

enum DaySection: Int, CaseIterable, Identifiable, Codable {
    case anytime = 0, morning = 1, afternoon = 2, evening = 3

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .anytime: return "Anytime"
        case .morning: return "Morning"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }
    var symbol: String {
        switch self {
        case .anytime: return "tray"
        case .morning: return "sunrise"
        case .afternoon: return "sun.max"
        case .evening: return "moon.stars"
        }
    }
    /// Which section a wall-clock time belongs to.
    static func forHour(_ hour: Int) -> DaySection {
        switch hour {
        case 0..<12: return .morning
        case 12..<17: return .afternoon
        default: return .evening
        }
    }
}

enum ReminderKind: Int, CaseIterable, Codable {
    case none = 0, notification = 1, alarm = 2
    var title: String {
        switch self {
        case .none: return "None"
        case .notification: return "Notification"
        case .alarm: return "Alarm"
        }
    }
}

enum RepeatRule: Int, CaseIterable, Identifiable, Codable {
    case never = 0, daily = 1, weekdays = 2, weekly = 3, custom = 4
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .never: return "Never"
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly: return "Every week"
        case .custom: return "Custom days"
        }
    }
}

enum AlarmMode: Int, Codable { case regular = 0, challenge = 1 }

enum Challenge: String, CaseIterable, Identifiable, Codable {
    case math, shake, typing, tiles, nfc, photo, overstimulated

    var id: String { rawValue }
    var title: String {
        switch self {
        case .math: return "Math"
        case .shake: return "Shake"
        case .typing: return "Typing"
        case .tiles: return "Color tiles"
        case .nfc: return "NFC scan"
        case .photo: return "Photo"
        case .overstimulated: return "Overstimulated"
        }
    }
    var blurb: String {
        switch self {
        case .math: return "Solve problems before the alarm stops."
        case .shake: return "Shake the phone until the counter fills."
        case .typing: return "Type the phrase exactly as shown."
        case .tiles: return "Memorise the lit tiles, then tap them back."
        case .nfc: return "Scan a sticker you stuck somewhere annoying."
        case .photo: return "Photograph a spot you registered in advance."
        case .overstimulated: return "A joke gauntlet of fake sign-in hoops. No snooze."
        }
    }
    var emoji: String {
        switch self {
        case .math: return "➗"
        case .shake: return "📳"
        case .typing: return "⌨️"
        case .tiles: return "🟪"
        case .nfc: return "📶"
        case .photo: return "📷"
        case .overstimulated: return "🤪"
        }
    }
    /// Tiers and round counts only apply to the four tunable challenges.
    var supportsTiers: Bool {
        switch self {
        case .math, .shake, .typing, .tiles: return true
        case .nfc, .photo, .overstimulated: return false
        }
    }
    /// Built in this slice and playable end to end.
    var isImplemented: Bool {
        switch self {
        case .math, .shake, .typing, .tiles, .overstimulated: return true
        case .nfc, .photo: return false
        }
    }
}

enum Tier: Int, CaseIterable, Identifiable, Codable {
    case veryEasy = 0, easy, normal, hard, veteran, general, hell

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .veryEasy: return "Very easy"
        case .easy: return "Easy"
        case .normal: return "Normal"
        case .hard: return "Hard"
        case .veteran: return "Veteran"
        case .general: return "General"
        case .hell: return "Hell"
        }
    }
    /// 5 XP per tier, so Very easy adds nothing and Hell adds 30.
    var xpBonus: Int { rawValue * 5 }
    /// Harder tiers cap snoozing regardless of the user's own setting.
    var snoozeCap: Int? {
        switch self {
        case .veryEasy, .easy, .normal: return nil   // user's setting wins
        case .hard, .veteran: return 2
        case .general: return 1
        case .hell: return 0
        }
    }
    var palette: Palette {
        switch self {
        case .veryEasy, .easy: return .mint
        case .normal: return .sky
        case .hard, .veteran: return .butter
        case .general, .hell: return .blush
        }
    }
}

enum PrayerName: Int, CaseIterable, Identifiable, Codable {
    case fajr = 0, dhuhr, asr, maghrib, isha
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .fajr: return "Fajr"
        case .dhuhr: return "Dhuhr"
        case .asr: return "Asr"
        case .maghrib: return "Maghrib"
        case .isha: return "Isha"
        }
    }
}

enum PrayerStatus: Int, Codable { case pending = 0, prayed = 1, qada = 2, missed = 3 }

enum StreakKind: Int, Codable { case daily = 0, wake = 1 }

enum XPReason: String, Codable {
    case wake, snoozePenalty, tierBonus, task, timer, prayer, groupBonus, milestone
    var title: String {
        switch self {
        case .wake: return "Woke up on time"
        case .snoozePenalty: return "Snoozed"
        case .tierBonus: return "Challenge tier bonus"
        case .task: return "Task done"
        case .timer: return "Focus session"
        case .prayer: return "Prayer on time"
        case .groupBonus: return "Whole group woke up"
        case .milestone: return "Streak milestone"
        }
    }
}
