import Foundation
import SwiftData

#if DEBUG
/// Debug-only scaffolding. `-JasaraDemo` fills a fresh install with a believable
/// day so screens can be checked without tapping through onboarding every time,
/// and `-JasaraTab <todo|calendar|alarm|timer>` picks the tab to land on.
/// App Review's demo notes will want the same seed, but it never ships in a
/// release build.
enum DemoSeed {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-JasaraDemo")
    }

    static var startTab: AppTab? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-JasaraTab"),
              index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "todo": return .todo
        case "calendar": return .calendar
        case "alarm": return .alarm
        case "timer": return .timer
        default: return nil
        }
    }

    @MainActor
    static func apply(to store: AppStore) {
        guard isRequested else { return }
        let context = store.context
        guard ((try? context.fetch(FetchDescriptor<TaskItem>()))?.isEmpty ?? true) else { return }

        let profile = store.profile
        profile.hasOnboarded = true
        profile.isGuest = true
        profile.displayName = "Zain"
        profile.avatarEmoji = "🌤️"
        profile.totalXP = 812

        let daily = store.streak(.daily)
        daily.count = 12
        daily.best = 21
        daily.lastDay = Date().startOfDay
        let wake = store.streak(.wake)
        wake.count = 5
        wake.best = 9
        wake.lastDay = Date().startOfDay

        for seed in samples {
            let task = TaskItem(title: seed.title, emoji: seed.emoji,
                                color: seed.color, priority: seed.priority)
            task.durationMinutes = seed.minutes
            task.date = seed.scheduled ? Date() : nil
            task.section = seed.section
            task.createdAt = Date().addingTimeInterval(-3600)
            context.insert(task)
            for (index, step) in seed.steps.enumerated() {
                let subtask = Subtask(title: step, order: index)
                subtask.done = index == 0
                subtask.parent = task
                context.insert(subtask)
            }
        }

        let weekday = AlarmItem(hour: 6, minute: 30, label: "Gym, no excuses")
        weekday.weekdaysMask = Weekdays.weekdayMask
        weekday.mode = .challenge
        weekday.challenge = .math
        weekday.tier = .hard
        weekday.rounds = 3
        context.insert(weekday)

        let weekend = AlarmItem(hour: 9, minute: 0, label: "Saturday, gently")
        weekend.weekdaysMask = Weekdays.bit(7)
        weekend.snoozeMinutes = 10
        context.insert(weekend)

        let chaos = AlarmItem(hour: 7, minute: 15, label: "The full nonsense")
        chaos.weekdaysMask = Weekdays.everyDay
        chaos.mode = .challenge
        chaos.challenge = .overstimulated
        context.insert(chaos)

        let prayers = store.prayerSettings
        prayers.isEnabled = true
        // A plausible spot on the device's own timezone meridian, so seeded prayer
        // times land at believable local hours wherever this demo is run.
        let offsetHours = Double(TimeZone.current.secondsFromGMT()) / 3600
        prayers.latitude = 51.5
        prayers.longitude = offsetHours * 15
        prayers.placeName = TimeZone.current.identifier.split(separator: "/").last.map(String.init) ?? "Here"
        prayers.method = .mwl

        store.save()
    }

    private struct Sample {
        var title: String
        var emoji: String
        var color: Palette
        var priority: Priority
        var minutes: Int?
        var section: DaySection = .anytime
        var scheduled = true
        var steps: [String] = []
    }

    private static let samples: [Sample] = [
        Sample(title: "Finish the coursework draft", emoji: "✏️", color: .sky, priority: .high,
               minutes: 90, section: .morning,
               steps: ["Outline", "First half", "Second half", "Read it back"]),
        Sample(title: "Gym session", emoji: "🏋️", color: .blush, priority: .high,
               minutes: 60, section: .morning),
        Sample(title: "Reply to the group chat", emoji: "📧", color: .sky, priority: .medium,
               minutes: 10, section: .afternoon),
        Sample(title: "Groceries", emoji: "🛒", color: .butter, priority: .medium,
               minutes: 30, section: .afternoon,
               steps: ["Oats", "Eggs", "Something green"]),
        Sample(title: "Tidy the desk", emoji: "🧹", color: .mint, priority: .low,
               minutes: 10, section: .evening),
        Sample(title: "Read 10 pages", emoji: "📚", color: .sand, priority: .low,
               minutes: 15, section: .evening),
        Sample(title: "Book the dentist", emoji: "💊", color: .blush, priority: .none,
               minutes: nil, scheduled: false)
    ]
}
#endif

#if DEBUG
extension DemoSeed {
    /// `-JasaraRing <math|shake|typing|tiles|overstimulated>` opens the alarm ring
    /// screen straight away, which is how the challenges get checked without
    /// waiting for 6:30am to come round.
    static var ringChallenge: Challenge? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-JasaraRing"),
              index + 1 < arguments.count else { return nil }
        return Challenge(rawValue: arguments[index + 1])
    }

    @MainActor
    static func ringIfRequested(_ store: AppStore) {
        guard let challenge = ringChallenge else { return }
        let alarms = (try? store.context.fetch(FetchDescriptor<AlarmItem>())) ?? []
        if let existing = alarms.first(where: { $0.challenge == challenge && $0.mode == .challenge }) {
            store.ringingAlarmID = existing.id
            return
        }
        let alarm = AlarmItem(hour: 6, minute: 30, label: "Demo \(challenge.title)")
        alarm.mode = .challenge
        alarm.challenge = challenge
        alarm.tier = .normal
        alarm.rounds = 3
        alarm.preparedPhrases = PhraseFactory.prepare(for: alarm)
        store.context.insert(alarm)
        store.save()
        store.ringingAlarmID = alarm.id
    }
}
#endif

#if DEBUG
extension DemoSeed {
    /// `-JasaraFireIn <seconds>` asks AlarmKit to ring the first challenge alarm
    /// that many seconds from now — the quickest way to see a real system alarm,
    /// its snooze button and its stop intent without waiting for the morning.
    @MainActor
    static func fireIfRequested(_ store: AppStore) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-JasaraFireIn"),
              index + 1 < arguments.count,
              let seconds = Double(arguments[index + 1]) else { return }
        let alarms = (try? store.context.fetch(FetchDescriptor<AlarmItem>())) ?? []
        guard let alarm = alarms.first(where: { $0.mode == .challenge }) ?? alarms.first else { return }
        guard await AlarmKitScheduler.shared.requestAuthorization() else {
            print("JasaraFireIn: AlarmKit permission not granted")
            return
        }
        let snapshot = AlarmSnapshot(alarm)
        AlarmRuntime.save(snapshot)
        await AlarmKitScheduler.scheduleFollowUp(snapshot, after: seconds, snoozesUsed: 0)
        print("JasaraFireIn: '\(snapshot.title)' rings in \(Int(seconds))s")
    }
}
#endif
