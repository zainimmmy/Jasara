import Foundation
import SwiftData

// SwiftData on the device is the source of truth. Anything that would sync to a
// backend carries `updatedAt` so a future sync queue can resolve last-write-wins.

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var emoji: String = "✅"
    var colorName: String = Palette.sky.rawValue
    var priorityRaw: Int = Priority.none.rawValue
    var notes: String = ""
    /// Day the task is planned for. Nil means it only lives in the To do tab.
    var date: Date?
    var sectionRaw: Int = DaySection.anytime.rawValue
    var durationMinutes: Int?
    var repeatRuleRaw: Int = RepeatRule.never.rawValue
    /// Bit per weekday, 1 = Sunday … 64 = Saturday. Only read for `.custom`.
    var customDaysMask: Int = 0
    var reminderDate: Date?
    var reminderKindRaw: Int = ReminderKind.none.rawValue
    /// Challenge used when the reminder is an alarm.
    var reminderChallengeRaw: String?
    var completedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var autoCompleteWithSubtasks: Bool = true
    /// Set on the task generated from the "Daily prayers 🕌" suggestion.
    var isPrayerAnchor: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Subtask.parent)
    var subtasks: [Subtask] = []

    init(title: String, emoji: String = "✅", color: Palette = .sky, priority: Priority = .none) {
        self.title = title
        self.emoji = emoji
        self.colorName = color.rawValue
        self.priorityRaw = priority.rawValue
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue; updatedAt = .now }
    }
    var section: DaySection {
        get { DaySection(rawValue: sectionRaw) ?? .anytime }
        set { sectionRaw = newValue.rawValue; updatedAt = .now }
    }
    var palette: Palette {
        get { Palette.named(colorName) }
        set { colorName = newValue.rawValue; updatedAt = .now }
    }
    var repeatRule: RepeatRule {
        get { RepeatRule(rawValue: repeatRuleRaw) ?? .never }
        set { repeatRuleRaw = newValue.rawValue; updatedAt = .now }
    }
    var reminderKind: ReminderKind {
        get { ReminderKind(rawValue: reminderKindRaw) ?? .none }
        set { reminderKindRaw = newValue.rawValue; updatedAt = .now }
    }
    var isDone: Bool { completedAt != nil }
    var doneSubtasks: Int { subtasks.filter(\.done).count }
    var orderedSubtasks: [Subtask] { subtasks.sorted { $0.order < $1.order } }
}

@Model
final class Subtask {
    var id: UUID = UUID()
    var title: String = ""
    var done: Bool = false
    var order: Int = 0
    var parent: TaskItem?

    init(title: String, order: Int) {
        self.title = title
        self.order = order
    }
}

@Model
final class AlarmItem {
    var id: UUID = UUID()
    var hour: Int = 7
    var minute: Int = 0
    var label: String = "Alarm"
    var isEnabled: Bool = true
    /// Bit per weekday, 1 = Sunday … 64 = Saturday. Zero means a one-shot alarm.
    var weekdaysMask: Int = 0
    var soundName: String = "Dawn"
    var modeRaw: Int = AlarmMode.regular.rawValue
    var challengeRaw: String = Challenge.math.rawValue
    var tierRaw: Int = Tier.normal.rawValue
    var rounds: Int = 3
    var typingWordCount: Int = 6
    var snoozeEnabled: Bool = true
    var snoozeMinutes: Int = 9
    var maxSnoozes: Int = 3
    /// Phrases are generated when the alarm is saved and refreshed nightly, so
    /// nothing has to be produced while the alarm is screaming at 6am.
    var preparedPhrases: [String] = []
    var groupID: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(hour: Int, minute: Int, label: String = "Alarm") {
        self.hour = hour
        self.minute = minute
        self.label = label
    }

    var mode: AlarmMode {
        get { AlarmMode(rawValue: modeRaw) ?? .regular }
        set { modeRaw = newValue.rawValue; updatedAt = .now }
    }
    var challenge: Challenge {
        get { Challenge(rawValue: challengeRaw) ?? .math }
        set { challengeRaw = newValue.rawValue; updatedAt = .now }
    }
    var tier: Tier {
        get { Tier(rawValue: tierRaw) ?? .normal }
        set { tierRaw = newValue.rawValue; updatedAt = .now }
    }
    /// The tier's cap wins over the user's setting when it is stricter.
    var effectiveMaxSnoozes: Int {
        guard mode == .challenge else { return snoozeEnabled ? maxSnoozes : 0 }
        if challenge == .overstimulated { return 0 }
        guard let cap = tier.snoozeCap else { return snoozeEnabled ? maxSnoozes : 0 }
        return snoozeEnabled ? min(maxSnoozes, cap) : 0
    }
    var repeatsWeekly: Bool { weekdaysMask != 0 }
}

@Model
final class WakeEvent {
    var id: UUID = UUID()
    var alarmID: UUID = UUID()
    var scheduledAt: Date = Date()
    var dismissedAt: Date?
    var snoozes: Int = 0
    var tierRaw: Int = Tier.normal.rawValue
    var emergencyStopped: Bool = false
    /// Offline events are trusted locally and re-checked against server time at
    /// the next sync. A large device clock jump sets this back to false.
    var verified: Bool = false

    init(alarmID: UUID, scheduledAt: Date, tier: Tier) {
        self.alarmID = alarmID
        self.scheduledAt = scheduledAt
        self.tierRaw = tier.rawValue
    }

    var tier: Tier { Tier(rawValue: tierRaw) ?? .normal }
    var wasOnTime: Bool { dismissedAt != nil && !emergencyStopped }
}

@Model
final class FocusSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var plannedMinutes: Int = 25
    var completedSeconds: Int = 0
    var taskTitle: String?
    var emoji: String = "⏳"

    init(plannedMinutes: Int, taskTitle: String? = nil, emoji: String = "⏳") {
        self.plannedMinutes = plannedMinutes
        self.taskTitle = taskTitle
        self.emoji = emoji
    }
}

@Model
final class PrayerSettings {
    var id: UUID = UUID()
    var isEnabled: Bool = false
    /// false = automatic from location, true = times typed from a masjid timetable.
    var manualTimes: Bool = false
    var manualMinutes: [Int] = [300, 780, 960, 1110, 1230]   // minutes past midnight
    var hanafiAsr: Bool = false
    var methodRaw: String = PrayerMethod.isna.rawValue
    /// Masjid adjustment in minutes, one per prayer.
    var offsets: [Int] = [0, 0, 0, 0, 0]
    var jumuahEnabled: Bool = false
    var jumuahMinutes: Int = 810                              // 13:30
    var reminderKindRaw: Int = ReminderKind.notification.rawValue
    var nudgeIntervalMinutes: Int = 15
    /// Off by default. Some users will not want worship gamified.
    var countsForXP: Bool = false
    var latitude: Double?
    var longitude: Double?
    var placeName: String?

    init() {}

    var reminderKind: ReminderKind {
        get { ReminderKind(rawValue: reminderKindRaw) ?? .notification }
        set { reminderKindRaw = newValue.rawValue }
    }
    var method: PrayerMethod {
        get { PrayerMethod(rawValue: methodRaw) ?? .isna }
        set { methodRaw = newValue.rawValue }
    }
}

@Model
final class PrayerLog {
    var id: UUID = UUID()
    var prayerRaw: Int = 0
    var day: Date = Date()          // start of day
    var statusRaw: Int = PrayerStatus.pending.rawValue
    var markedAt: Date?

    init(prayer: PrayerName, day: Date) {
        self.prayerRaw = prayer.rawValue
        self.day = day
    }

    var prayer: PrayerName { PrayerName(rawValue: prayerRaw) ?? .fajr }
    var status: PrayerStatus {
        get { PrayerStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

@Model
final class XPEvent {
    var id: UUID = UUID()
    var reasonRaw: String = XPReason.task.rawValue
    var amount: Int = 0
    var date: Date = Date()
    var verified: Bool = true

    init(reason: XPReason, amount: Int, date: Date = .now) {
        self.reasonRaw = reason.rawValue
        self.amount = amount
        self.date = date
    }

    var reason: XPReason { XPReason(rawValue: reasonRaw) ?? .task }
}

@Model
final class StreakRecord {
    var id: UUID = UUID()
    var kindRaw: Int = StreakKind.daily.rawValue
    var count: Int = 0
    var best: Int = 0
    var lastDay: Date?
    var freezes: Int = 0

    init(kind: StreakKind) { self.kindRaw = kind.rawValue }

    var kind: StreakKind { StreakKind(rawValue: kindRaw) ?? .daily }
}

@Model
final class Profile {
    var id: UUID = UUID()
    /// Guests get the whole solo app. An account is only needed for friends,
    /// group alarms, calendar sharing and backup.
    var isGuest: Bool = true
    var username: String = ""
    var displayName: String = ""
    var avatarEmoji: String = "🌤️"
    var totalXP: Int = 0
    var hasOnboarded: Bool = false
    var appearanceRaw: Int = 0          // 0 system, 1 light, 2 dark
    var hapticsOn: Bool = true
    var firstWeekdayIsMonday: Bool = false
    var calendarTimelineView: Bool = false
    var defaultChallengeRaw: String = Challenge.math.rawValue
    var defaultTierRaw: Int = Tier.normal.rawValue
    var seenChallengeExplainer: Bool = false
    var isPro: Bool = false

    init() {}

    var level: Int { Leveling.level(forTotalXP: totalXP) }
    var defaultChallenge: Challenge {
        get { Challenge(rawValue: defaultChallengeRaw) ?? .math }
        set { defaultChallengeRaw = newValue.rawValue }
    }
    var defaultTier: Tier {
        get { Tier(rawValue: defaultTierRaw) ?? .normal }
        set { defaultTierRaw = newValue.rawValue }
    }
    var colorScheme: ColorSchemePreference {
        get { ColorSchemePreference(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }
}

enum ColorSchemePreference: Int, CaseIterable, Identifiable {
    case system = 0, light = 1, dark = 2
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

