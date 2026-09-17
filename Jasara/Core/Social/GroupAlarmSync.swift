import Foundation
import Observation
import SwiftData
import Supabase

/// A group wake waiting to reach the server. Wakes happen whether or not there's
/// signal, so they queue here and go up whenever the app next can.
struct PendingGroupCheckIn: Codable, Hashable {
    var groupID: UUID
    var occurrenceOn: String
    var wokeAt: Date
    var snoozes: Int
    var emergencyStopped: Bool
}

/// Keeps this phone's alarms in step with the groups it belongs to.
///
/// Each joined group becomes an ordinary local `AlarmItem` (tagged with its
/// `groupID`), so it rings through AlarmKit with no connection, uses the same
/// challenges, snooze caps and emergency stop, and logs XP the same way. The
/// server decides the schedule and who counts; the phone decides when to ring.
@Observable
@MainActor
final class GroupAlarmSync {
    static let shared = GroupAlarmSync()

    private(set) var groups: [GroupAlarm] = []
    private(set) var isRefreshing = false
    private(set) var lastError: String?
    /// Set after a group wake so the app can offer the wake photo.
    var photoPrompt: PendingGroupCheckIn?

    var joined: [GroupAlarm] { groups.filter(\.isJoined) }
    var invites: [GroupAlarm] { groups.filter { !$0.isJoined } }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let cache = "groups.cache"
        static let checkIns = "groups.pendingCheckIns"
        static let bonuses = "groups.awardedBonuses"
    }

    init() {
        if let data = defaults.data(forKey: Key.cache),
           let cached = try? JSONDecoder().decode([GroupAlarm].self, from: data) {
            groups = cached      // shown offline; the alarms themselves are local anyway
        }
    }

    // MARK: - Refresh

    func refresh(store: AppStore) async {
        let backend = Backend.shared
        // Not signed in (or the session hasn't been read yet) is never a reason to
        // remove alarms: only an explicit sign-out does that. Otherwise a cold
        // launch with no signal could delete group alarms before they ring.
        guard backend.isConfigured, backend.isSignedIn else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await flushCheckIns()
        do {
            let fresh = try await backend.myAlarmGroups()
            groups = fresh
            lastError = nil
            if let data = try? JSONEncoder().encode(fresh) { defaults.set(data, forKey: Key.cache) }
            await apply(fresh.filter(\.isJoined), store: store)
            await awardGroupBonuses(store: store)
        } catch {
            // Offline: keep the cached list and, crucially, leave local alarms alone.
            lastError = Backend.describe(error)
        }
    }

    /// Make the local alarms match the server. Only groups the server returned are
    /// touched, and nothing is removed unless the server said so.
    private func apply(_ joined: [GroupAlarm], store: AppStore) async {
        let context = store.context
        let local = ((try? context.fetch(FetchDescriptor<AlarmItem>())) ?? []).filter(\.isGroupAlarm)
        var changed: [AlarmItem] = []

        for group in joined {
            let alarm = local.first { $0.groupID == group.id } ?? {
                let fresh = AlarmItem(hour: group.hour, minute: group.minute, label: group.label)
                fresh.groupID = group.id
                context.insert(fresh)
                return fresh
            }()

            let lockedOn: Date? = (!group.isOn && group.countsNext) ? group.nextRingDate : nil
            let before = Signature(alarm)
            alarm.label = group.label
            alarm.hour = group.hour
            alarm.minute = group.minute
            alarm.weekdaysMask = group.onceOn == nil ? group.weekdaysMask : 0
            alarm.onceOn = group.onceDate
            alarm.mode = .challenge
            alarm.challenge = group.challengeKind
            alarm.tier = group.tierKind
            alarm.rounds = group.rounds
            alarm.isEnabled = group.isOn
            alarm.lockedOccurrence = lockedOn
            if alarm.challenge == .typing && alarm.preparedPhrases.isEmpty {
                alarm.preparedPhrases = PhraseFactory.prepare(for: alarm)
            }
            if Signature(alarm) != before { changed.append(alarm) }
        }

        let keep = Set(joined.map(\.id))
        for alarm in local where !keep.contains(alarm.groupID ?? UUID()) {
            store.scheduler.cancel(alarmID: alarm.id)
            context.delete(alarm)
        }
        store.save()
        for alarm in changed { await store.scheduler.schedule(alarm) }
    }

    /// Signing out or deleting the account stops group alarms ringing on this
    /// phone. Signing back in brings them back from the server.
    func removeAllGroupAlarms(store: AppStore) {
        let context = store.context
        let local = ((try? context.fetch(FetchDescriptor<AlarmItem>())) ?? []).filter(\.isGroupAlarm)
        guard !local.isEmpty || !groups.isEmpty else { return }
        for alarm in local {
            store.scheduler.cancel(alarmID: alarm.id)
            context.delete(alarm)
        }
        store.save()
        groups = []
        defaults.removeObject(forKey: Key.cache)
    }

    private struct Signature: Equatable {
        var hour: Int, minute: Int, mask: Int, once: Date?, enabled: Bool, locked: Date?
        var challenge: String, tier: Int, rounds: Int, label: String
        init(_ a: AlarmItem) {
            hour = a.hour; minute = a.minute; mask = a.weekdaysMask; once = a.onceOn
            enabled = a.isEnabled; locked = a.lockedOccurrence
            challenge = a.challengeRaw; tier = a.tierRaw; rounds = a.rounds; label = a.label
        }
    }

    // MARK: - Check-ins

    /// Called when a group alarm is dismissed. Works out which occurrence rang:
    /// the latest one at or before now (with a little slack for early solvers).
    func recordWake(alarm: AlarmItem, snoozes: Int, emergencyStopped: Bool, at wokeAt: Date = .now) {
        guard let groupID = alarm.groupID else { return }
        let calendar = Calendar.current
        let occurrence: Date
        if let once = alarm.onceOn {
            occurrence = once
        } else {
            let candidates = [0, -1].compactMap { offset -> Date? in
                let day = wokeAt.startOfDay.adding(days: offset)
                guard Weekdays.contains(alarm.weekdaysMask, weekday: calendar.component(.weekday, from: day)),
                      let ring = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: day),
                      ring <= wokeAt.addingTimeInterval(15 * 60) else { return nil }
                return day
            }
            guard let latest = candidates.first else { return }
            occurrence = latest
        }
        let checkIn = PendingGroupCheckIn(groupID: groupID,
                                          occurrenceOn: DayString.string(occurrence),
                                          wokeAt: wokeAt,
                                          snoozes: snoozes,
                                          emergencyStopped: emergencyStopped)
        var queue = pendingCheckIns
        queue.append(checkIn)
        pendingCheckIns = queue
        Task {
            await flushCheckIns()
            // Offer the photo once the ring screen has finished going away;
            // presenting during its dismissal can silently fail.
            if !emergencyStopped {
                try? await Task.sleep(for: .milliseconds(900))
                photoPrompt = checkIn
            }
        }
    }

    private var pendingCheckIns: [PendingGroupCheckIn] {
        get {
            guard let data = defaults.data(forKey: Key.checkIns) else { return [] }
            return (try? JSONDecoder().decode([PendingGroupCheckIn].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.checkIns) }
    }

    /// Sends queued wakes. Only a definite answer from the server removes one.
    @discardableResult
    func flushCheckIns() async -> Bool {
        let backend = Backend.shared
        guard backend.isSignedIn else { return false }
        var remaining: [PendingGroupCheckIn] = []
        for checkIn in pendingCheckIns {
            do {
                _ = try await backend.checkIn(checkIn)
            } catch is PostgrestError {
                // The server answered and said no — left the group, no alarm that
                // day. Retrying won't change that.
            } catch {
                // Anything else (offline, token refresh, timeouts) keeps it queued.
                remaining.append(checkIn)
            }
        }
        pendingCheckIns = remaining
        return remaining.isEmpty
    }

    // MARK: - Group bonus

    /// +10 XP each when everyone who was in woke on time. Checked for today and
    /// yesterday, and paid once per group per morning on this phone.
    private func awardGroupBonuses(store: AppStore) async {
        var awarded = Set(defaults.stringArray(forKey: Key.bonuses) ?? [])
        let backend = Backend.shared
        guard let me = backend.userID else { return }
        for group in joined {
            for day in [Date().startOfDay, Date().startOfDay.adding(days: -1)] {
                let key = "\(group.id.uuidString)|\(DayString.string(day))"
                guard !awarded.contains(key),
                      let board = try? await backend.groupDay(group.id, day: day) else { continue }
                let inToday = board.filter(\.participating)
                guard inToday.count >= 2,
                      inToday.contains(where: { $0.userID == me }),
                      inToday.allSatisfy({ $0.checkedIn && $0.onTime }) else { continue }
                store.award(.groupBonus, XPRules.groupBonus)
                awarded.insert(key)
            }
        }
        // Only the last few weeks matter.
        defaults.set(Array(awarded.suffix(200)), forKey: Key.bonuses)
    }
}
