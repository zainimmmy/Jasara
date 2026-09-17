import Foundation
import SwiftData
import Observation
import UIKit

/// One place that owns the singletons (profile, streaks, prayer settings) and
/// every write that touches XP. Views read models directly through @Query and
/// come here to *change* progress, so the rules can't drift between screens.
@Observable
@MainActor
final class AppStore {
    private(set) var profile: Profile
    private(set) var prayerSettings: PrayerSettings
    let context: ModelContext
    let prayers = PrayerService()
    let scheduler: AlarmScheduling = AlarmKitScheduler.shared

    /// Set when an alarm fires, which pushes the full-screen ring view over the app.
    var ringingAlarmID: UUID?
    /// Raised by the XP engine so the UI can show a little "+20" toast.
    var lastAward: (amount: Int, reason: XPReason, at: Date)?
    var levelUpTo: Int?
    /// The brief "Alarm set for … from now" note at the bottom of the screen.
    private(set) var alarmSetNote: AlarmSetNote?

    init(context: ModelContext) {
        self.context = context
        self.profile = AppStore.fetchOrCreate(context: context, make: Profile.init)
        self.prayerSettings = AppStore.fetchOrCreate(context: context, make: PrayerSettings.init)
        ensureStreaks()
    }

    private static func fetchOrCreate<T: PersistentModel>(context: ModelContext, make: () -> T) -> T {
        if let existing = try? context.fetch(FetchDescriptor<T>()).first { return existing }
        let fresh = make()
        context.insert(fresh)
        return fresh
    }

    private func ensureStreaks() {
        let existing = (try? context.fetch(FetchDescriptor<StreakRecord>())) ?? []
        for kind in [StreakKind.daily, .wake] where !existing.contains(where: { $0.kind == kind }) {
            context.insert(StreakRecord(kind: kind))
        }
    }

    func streak(_ kind: StreakKind) -> StreakRecord {
        let all = (try? context.fetch(FetchDescriptor<StreakRecord>())) ?? []
        if let found = all.first(where: { $0.kind == kind }) { return found }
        let fresh = StreakRecord(kind: kind)
        context.insert(fresh)
        return fresh
    }

    func save() { try? context.save() }

    // MARK: - XP

    @discardableResult
    func award(_ reason: XPReason, _ amount: Int, at date: Date = .now) -> Int {
        guard amount != 0 else { return 0 }
        let before = profile.level
        context.insert(XPEvent(reason: reason, amount: amount, date: date))
        profile.totalXP = max(0, profile.totalXP + amount)
        lastAward = (amount, reason, date)
        if profile.level > before { levelUpTo = profile.level }
        haptic(.success)
        save()
        return amount
    }

    /// XP already earned today for one reason, used to enforce the daily caps.
    func xpToday(for reason: XPReason) -> Int {
        let start = Date().startOfDay
        let raw = reason.rawValue
        let descriptor = FetchDescriptor<XPEvent>(
            predicate: #Predicate { $0.date >= start && $0.reasonRaw == raw })
        let events = (try? context.fetch(descriptor)) ?? []
        return events.reduce(0) { $0 + $1.amount }
    }

    private func awardCapped(_ reason: XPReason, _ amount: Int, cap: Int) {
        let remaining = max(0, cap - xpToday(for: reason))
        award(reason, min(amount, remaining))
    }

    // MARK: - Tasks

    func toggle(_ task: TaskItem) {
        if task.isDone {
            task.completedAt = nil
            task.updatedAt = .now
            save()
            return
        }
        task.completedAt = .now
        task.updatedAt = .now
        NotificationScheduler.shared.cancelReminder(for: task)
        // Freshly created and instantly ticked off? That's not a day's work. And a
        // task only ever pays once, however many times it's unticked and reticked.
        let age = Date().timeIntervalSince(task.createdAt)
        if age >= XPRules.minimumTaskAge && !task.xpAwarded {
            awardCapped(.task, XPRules.task, cap: XPRules.taskDailyCap)
            task.xpAwarded = true
        }
        spawnNextRepeat(of: task)
        touchDailyStreak()
        save()
    }

    /// Completing a repeating task puts the next one on its day, with fresh
    /// subtasks and the reminder moved along by the same number of days.
    private func spawnNextRepeat(of task: TaskItem) {
        guard task.repeatRule != .never, !task.repeatSpawned else { return }
        let today = Date().startOfDay
        let base = max(task.date?.startOfDay ?? today, today)
        guard let next = task.nextOccurrence(after: base) else { return }

        let copy = TaskItem(title: task.title, emoji: task.emoji, color: task.palette, priority: task.priority)
        copy.notes = task.notes
        copy.date = next
        copy.section = task.section
        copy.durationMinutes = task.durationMinutes
        copy.repeatRule = task.repeatRule
        copy.customDaysMask = task.customDaysMask
        copy.autoCompleteWithSubtasks = task.autoCompleteWithSubtasks
        copy.reminderKind = task.reminderKind
        if let reminder = task.reminderDate {
            let shift = Calendar.current.dateComponents([.day], from: task.date?.startOfDay ?? reminder.startOfDay, to: next).day ?? 1
            copy.reminderDate = reminder.adding(days: max(shift, 1))
        }
        context.insert(copy)
        for step in task.orderedSubtasks {
            let fresh = Subtask(title: step.title, order: step.order)
            fresh.parent = copy
            context.insert(fresh)
        }
        task.repeatSpawned = true
        if copy.reminderKind != .none {
            Task { await NotificationScheduler.shared.scheduleReminder(for: copy) }
        }
    }

    /// Subtasks never earn XP, so splitting a task into ten doesn't pay ten times.
    func toggle(_ subtask: Subtask) {
        subtask.done.toggle()
        if let parent = subtask.parent,
           parent.autoCompleteWithSubtasks,
           !parent.subtasks.isEmpty,
           parent.subtasks.allSatisfy(\.done),
           !parent.isDone {
            toggle(parent)
        }
        save()
    }

    // MARK: - Wake events

    func recordWake(alarm: AlarmItem, snoozes: Int, emergencyStopped: Bool) {
        let event = WakeEvent(alarmID: alarm.id, scheduledAt: .now, tier: alarm.tier)
        event.snoozes = snoozes
        event.dismissedAt = .now
        event.emergencyStopped = emergencyStopped
        context.insert(event)

        if alarm.isGroupAlarm {
            GroupAlarmSync.shared.recordWake(alarm: alarm, snoozes: snoozes, emergencyStopped: emergencyStopped)
        } else if !alarm.repeatsWeekly {
            // A one-off has done its job. Left enabled, it would ring again tomorrow.
            alarm.isEnabled = false
        }
        // Fresh phrases for next time, so nobody types the same words every morning.
        if alarm.challenge == .typing {
            alarm.preparedPhrases = PhraseFactory.prepare(for: alarm)
        }

        // The emergency stop always works, and always costs the streak. That is
        // the deal that keeps the app safe to use.
        guard !emergencyStopped else {
            breakStreak(.wake)
            save()
            return
        }
        award(.wake, XPRules.wakeXP(snoozes: snoozes))
        if alarm.mode == .challenge {
            let bonus = alarm.challenge == .overstimulated ? Tier.hell.xpBonus : alarm.tier.xpBonus
            award(.tierBonus, bonus)
        }
        extendStreak(.wake)
        touchDailyStreak()
        save()
    }


    // MARK: - Alarm set note

    /// Call after an alarm has been scheduled. Says how long until it rings, or
    /// that it can't ring, because claiming "set" with permission off would be a lie.
    func announceAlarmSet(ringsAt date: Date?) {
        let text: String
        if AlarmKitScheduler.shared.isDenied {
            text = "Alarms are off for Jasara. Allow them in Settings to ring."
        } else if !AlarmKitScheduler.shared.isAuthorized {
            return      // iOS is still asking; the answer decides what to say
        } else if let date, date > .now {
            text = TimeUntil.alarmSetMessage(until: date)
        } else {
            return
        }
        alarmSetNote = AlarmSetNote(text: text)
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    func dismissAlarmSetNote(_ id: UUID) {
        if alarmSetNote?.id == id { alarmSetNote = nil }
    }

    // MARK: - Scheduling

    /// Brings AlarmKit in line with the alarms on this phone. Run whenever the app
    /// comes forward. A one-off that has already rung is switched off first —
    /// rescheduling it would quietly turn it into tomorrow's alarm.
    func rescheduleAlarms() async {
        let alarms = (try? context.fetch(FetchDescriptor<AlarmItem>())) ?? []
        for alarm in alarms {
            guard let fired = AlarmRuntime.snapshot(for: alarm.id)?.fireDate, fired <= .now else { continue }
            if alarm.lockedOccurrence.map({ $0 <= .now }) == true {
                alarm.lockedOccurrence = nil
            } else if alarm.isEnabled && !alarm.repeatsWeekly {
                alarm.isEnabled = false
            }
        }
        save()
        for alarm in alarms { await scheduler.schedule(alarm) }
    }

    /// Today's prayer notifications and nudges, plus tomorrow's times.
    func refreshPrayerNotifications() async {
        guard prayerSettings.isEnabled, prayerSettings.reminderKind != .none else {
            NotificationScheduler.shared.cancelPrayers()
            return
        }
        guard let today = prayers.entries(for: .now, settings: prayerSettings) else { return }
        let tomorrow = prayers.entries(for: Date().adding(days: 1), settings: prayerSettings) ?? []
        await NotificationScheduler.shared.schedulePrayers(today, tomorrow: tomorrow, settings: prayerSettings)
    }

    // MARK: - Alarm intents

    /// Picks up what the AlarmKit intents did while the app was closed or in the
    /// background: wakes to log, and a challenge that still needs solving.
    func ingestAlarmRuntime() {
        let alarms = (try? context.fetch(FetchDescriptor<AlarmItem>())) ?? []
        for wake in AlarmRuntime.drainWakes() {
            guard let alarm = alarms.first(where: { $0.id == wake.alarmID }) else { continue }
            recordWake(alarm: alarm, snoozes: wake.snoozes, emergencyStopped: false)
        }
        if let pending = AlarmRuntime.pendingChallenge {
            if alarms.contains(where: { $0.id == pending }) {
                ringingAlarmID = pending
            } else {
                AlarmRuntime.clearWake(for: pending)      // the alarm was deleted mid-ring
            }
        }
    }

    // MARK: - Focus timer

    func recordFocus(seconds: Int, plannedMinutes: Int, taskTitle: String?, emoji: String) {
        let session = FocusSession(plannedMinutes: plannedMinutes, taskTitle: taskTitle, emoji: emoji)
        session.completedSeconds = seconds
        session.endedAt = .now
        context.insert(session)
        awardCapped(.timer, XPRules.timerXP(seconds: seconds), cap: XPRules.timerDailyCap)
        touchDailyStreak()
        save()
    }

    // MARK: - Prayers

    /// Read-only lookup, safe to call while a view is rendering.
    func existingLog(for prayer: PrayerName, on day: Date) -> PrayerLog? {
        let start = day.startOfDay
        let raw = prayer.rawValue
        let descriptor = FetchDescriptor<PrayerLog>(
            predicate: #Predicate { $0.prayerRaw == raw && $0.day == start })
        return try? context.fetch(descriptor).first
    }

    func log(for prayer: PrayerName, on day: Date) -> PrayerLog {
        let start = day.startOfDay
        let raw = prayer.rawValue
        let descriptor = FetchDescriptor<PrayerLog>(
            predicate: #Predicate { $0.prayerRaw == raw && $0.day == start })
        if let found = try? context.fetch(descriptor).first { return found }
        let fresh = PrayerLog(prayer: prayer, day: start)
        context.insert(fresh)
        return fresh
    }

    func mark(_ prayer: PrayerName, on day: Date, as status: PrayerStatus, scheduledAt: Date?) {
        let log = self.log(for: prayer, on: day)
        log.status = status
        log.markedAt = .now
        NotificationScheduler.shared.cancelNudges(for: prayer)
        if status == .prayed, prayerSettings.countsForXP, !log.xpAwarded, let scheduledAt,
           Date() >= scheduledAt {
            award(.prayer, XPRules.prayer)
            log.xpAwarded = true
        }
        touchDailyStreak()
        save()
    }

    // MARK: - Streaks

    /// Any single action keeps the daily streak alive. It should be hard to break
    /// by accident and impossible to break on purpose in one distracted evening.
    func touchDailyStreak() { extendStreak(.daily) }

    private func extendStreak(_ kind: StreakKind) {
        let record = streak(kind)
        let today = Date().startOfDay
        if let last = record.lastDay {
            if last.isSameDay(as: today) { return }
            let yesterday = today.adding(days: -1)
            record.count = last.isSameDay(as: yesterday) ? record.count + 1 : 1
        } else {
            record.count = 1
        }
        record.lastDay = today
        record.best = max(record.best, record.count)
        if let reward = XPRules.milestones[record.count] {
            award(.milestone, reward)
        }
        save()
    }

    private func breakStreak(_ kind: StreakKind) {
        let record = streak(kind)
        if record.freezes > 0 {
            record.freezes -= 1        // earned with XP, never sold
        } else {
            record.count = 0
        }
        record.lastDay = Date().startOfDay
        save()
    }

    /// Called on launch: a day with no scheduled alarm never breaks the wake streak,
    /// but a missed day does.
    func reconcileStreaks() {
        let daily = streak(.daily)
        if let last = daily.lastDay, !last.isSameDay(as: Date().startOfDay),
           !last.isSameDay(as: Date().adding(days: -1).startOfDay) {
            daily.count = 0
        }
        save()
    }

    // MARK: - Feedback

    func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard profile.hapticsOn else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    func tap() {
        guard profile.hapticsOn else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct AlarmSetNote: Equatable {
    let id = UUID()
    let text: String
}
