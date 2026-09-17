import Foundation
import UserNotifications

/// The seam between the app and whatever actually wakes the phone up. Backed by
/// `AlarmKitScheduler`, so alarms ring through silent mode and Focus.
protocol AlarmScheduling {
    func requestAuthorization() async -> Bool
    @MainActor func schedule(_ alarm: AlarmItem) async
    /// By id, so it's safe to call after the model is deleted.
    func cancel(alarmID: UUID)
    /// Ring again after a delay — the in-app snooze button.
    @MainActor func scheduleFollowUp(for alarm: AlarmItem, after seconds: TimeInterval) async
    /// The wake is settled: stop anything still ringing and clear follow-ups.
    func settleWake(for alarmID: UUID)
}

enum NotificationBudget {
    /// iOS keeps only 64 pending local notifications per app, so everything is
    /// scheduled about a day ahead and topped up on launch and background refresh.
    /// Alarms live in AlarmKit and don't count against this.
    static let systemLimit = 64
    static let maxNudgesPerPrayer = 6
    static let horizonDays = 1
}

/// Ordinary notifications: task reminders and prayer nudges. Alarms are not here —
/// a notification respects the ringer, and an alarm must not.
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let center = UNUserNotificationCenter.current()

    private enum Prefix {
        static let task = "task."
        static let prayer = "prayer."
        /// Earlier builds scheduled alarms as notifications under these.
        static let legacy = ["alarm.", "followup."]
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func registerCategories() {
        // "Prayed" checks a prayer off and cancels its remaining nudges without
        // opening the app.
        let prayed = UNNotificationAction(identifier: "PRAYED", title: "Prayed", options: [])
        let prayer = UNNotificationCategory(identifier: "PRAYER", actions: [prayed],
                                            intentIdentifiers: [], options: [])
        let complete = UNNotificationAction(identifier: "COMPLETE", title: "Mark done", options: [])
        let task = UNNotificationCategory(identifier: "TASK", actions: [complete],
                                          intentIdentifiers: [], options: [])
        center.setNotificationCategories([prayer, task])
    }

    /// Alarms moved to AlarmKit. Clear any old notification copies so nothing
    /// rings twice.
    func removeLegacyAlarmNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { id in
            Prefix.legacy.contains { id.hasPrefix($0) }
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    // MARK: - Task reminders

    func scheduleReminder(for task: TaskItem) async {
        cancelReminder(for: task)
        guard let fire = task.reminderDate, task.reminderKind != .none, fire > .now else { return }

        if task.reminderKind == .alarm {
            await AlarmKitScheduler.shared.scheduleTaskAlarm(id: task.id,
                                                             title: "\(task.emoji) \(task.title)",
                                                             at: fire)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(task.emoji) \(task.title)"
        content.body = "Reminder"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "TASK"
        content.userInfo = ["taskID": task.id.uuidString]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        await add(id: "\(Prefix.task)\(task.id.uuidString)", content: content, trigger: trigger)
    }

    func cancelReminder(for task: TaskItem) {
        center.removePendingNotificationRequests(withIdentifiers: ["\(Prefix.task)\(task.id.uuidString)"])
        AlarmKitScheduler.shared.cancelTaskAlarm(id: task.id)
    }

    // MARK: - Prayer nudges

    /// Today: one notification at each prayer time, then nudges at the chosen
    /// interval until the next prayer begins. Tomorrow: just the times, so a day
    /// without opening the app still gets its reminders. Capped to fit the 64
    /// slot budget; background refresh tops it up.
    func schedulePrayers(_ entries: [PrayerService.Entry], tomorrow: [PrayerService.Entry] = [],
                         settings: PrayerSettings) async {
        cancelPrayers()
        guard settings.isEnabled else { return }
        for entry in tomorrow where entry.time > .now {
            let content = UNMutableNotificationContent()
            content.title = "🕌 \(entry.title)"
            content.body = "It's time for \(entry.title)."
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = "PRAYER"
            content.userInfo = ["prayer": entry.prayer.rawValue]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: entry.time)
            await add(id: "\(Prefix.prayer)next.\(entry.prayer.rawValue)", content: content,
                      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        }
        let sorted = entries.sorted { $0.time < $1.time }
        for (index, entry) in sorted.enumerated() {
            let nextPrayer = index + 1 < sorted.count ? sorted[index + 1].time : entry.time.addingTimeInterval(4 * 3600)
            var fire = entry.time
            var nudge = 0
            while fire > .now && nudge <= NotificationBudget.maxNudgesPerPrayer && fire < nextPrayer {
                let content = UNMutableNotificationContent()
                content.title = "🕌 \(entry.title)"
                content.body = nudge == 0 ? "It's time for \(entry.title)." : "\(entry.title) is still unmarked."
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                content.categoryIdentifier = "PRAYER"
                content.userInfo = ["prayer": entry.prayer.rawValue]
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                await add(id: "\(Prefix.prayer)\(entry.prayer.rawValue).\(nudge)",
                          content: content,
                          trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                nudge += 1
                fire = fire.addingTimeInterval(Double(settings.nudgeIntervalMinutes) * 60)
            }
        }
    }

    func cancelPrayers() {
        let ids = PrayerName.allCases.flatMap { prayer in
            (0...NotificationBudget.maxNudgesPerPrayer).map { "\(Prefix.prayer)\(prayer.rawValue).\($0)" }
                + ["\(Prefix.prayer)next.\(prayer.rawValue)"]
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Cancels the remaining nudges for one prayer, used by the "Prayed" action.
    func cancelNudges(for prayer: PrayerName) {
        let ids = (0...NotificationBudget.maxNudgesPerPrayer).map { "\(Prefix.prayer)\(prayer.rawValue).\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Plumbing

    private func add(id: String, content: UNNotificationContent, trigger: UNNotificationTrigger) async {
        let pending = await center.pendingNotificationRequests()
        guard pending.count < NotificationBudget.systemLimit else { return }
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func pendingCount() async -> Int { await center.pendingNotificationRequests().count }
}
