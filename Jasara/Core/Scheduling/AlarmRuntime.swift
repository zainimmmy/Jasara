import Foundation

/// What the alarm intents need to know about an alarm. The intents can run while
/// the app is only launched in the background, before SwiftData or the UI exist,
/// so a small copy of each alarm is kept here instead.
struct AlarmSnapshot: Codable, Equatable {
    var alarmID: UUID
    var title: String
    var isChallenge: Bool
    var snoozeMinutes: Int
    /// Already reduced by the tier's cap.
    var maxSnoozes: Int
    /// For alarms that ring once: when. Lets the app tell a one-off has rung.
    var fireDate: Date?

    init(_ alarm: AlarmItem) {
        alarmID = alarm.id
        title = alarm.label.isEmpty ? "Alarm" : alarm.label
        isChallenge = alarm.mode == .challenge
        snoozeMinutes = alarm.snoozeMinutes
        maxSnoozes = alarm.effectiveMaxSnoozes
    }
}

/// A wake that finished while the app wasn't necessarily on screen. The app turns
/// these into WakeEvents and XP the next time it's in front.
struct PendingWake: Codable, Equatable {
    var alarmID: UUID
    var snoozes: Int
    var at: Date
}

/// Small, persisted state shared by the alarm intents and the app. It lives in
/// UserDefaults because the intents run in the app's process but may run first.
enum AlarmRuntime {
    /// Posted in-process whenever an intent changes something the UI shows.
    static let didChange = Notification.Name("JasaraAlarmRuntimeDidChange")

    private static let defaults = UserDefaults.standard
    private enum Key {
        static let snapshots = "alarm.snapshots"
        static let snoozes = "alarm.snoozes"
        static let followUps = "alarm.followUps"
        static let pendingChallenge = "alarm.pendingChallenge"
        static let pendingWakes = "alarm.pendingWakes"
    }

    // MARK: Snapshots

    static func save(_ snapshot: AlarmSnapshot) {
        var all = decode([String: AlarmSnapshot].self, Key.snapshots) ?? [:]
        all[snapshot.alarmID.uuidString] = snapshot
        encode(all, Key.snapshots)
    }

    static func snapshot(for id: UUID) -> AlarmSnapshot? {
        decode([String: AlarmSnapshot].self, Key.snapshots)?[id.uuidString]
    }

    static func forget(_ id: UUID) {
        var all = decode([String: AlarmSnapshot].self, Key.snapshots) ?? [:]
        all[id.uuidString] = nil
        encode(all, Key.snapshots)
        clearWake(for: id)
    }

    // MARK: Snoozes

    static func snoozes(for id: UUID) -> Int {
        (defaults.dictionary(forKey: Key.snoozes) as? [String: Int])?[id.uuidString] ?? 0
    }

    @discardableResult
    static func addSnooze(for id: UUID) -> Int {
        var all = (defaults.dictionary(forKey: Key.snoozes) as? [String: Int]) ?? [:]
        let count = (all[id.uuidString] ?? 0) + 1
        all[id.uuidString] = count
        defaults.set(all, forKey: Key.snoozes)
        return count
    }

    // MARK: Follow-ups

    static func followUpID(for id: UUID) -> UUID? {
        guard let raw = (defaults.dictionary(forKey: Key.followUps) as? [String: String])?[id.uuidString]
        else { return nil }
        return UUID(uuidString: raw)
    }

    static func setFollowUpID(_ followUp: UUID?, for id: UUID) {
        var all = (defaults.dictionary(forKey: Key.followUps) as? [String: String]) ?? [:]
        all[id.uuidString] = followUp?.uuidString
        defaults.set(all, forKey: Key.followUps)
    }

    // MARK: The challenge that still needs solving

    static var pendingChallenge: UUID? {
        get { defaults.string(forKey: Key.pendingChallenge).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.pendingChallenge) }
    }

    // MARK: Wakes to log

    static func enqueueWake(_ wake: PendingWake) {
        var queue = decode([PendingWake].self, Key.pendingWakes) ?? []
        queue.append(wake)
        encode(queue, Key.pendingWakes)
    }

    static func drainWakes() -> [PendingWake] {
        let queue = decode([PendingWake].self, Key.pendingWakes) ?? []
        defaults.removeObject(forKey: Key.pendingWakes)
        return queue
    }

    /// Everything about one ring is over: forget snoozes, follow-up and the
    /// pending challenge.
    static func clearWake(for id: UUID) {
        var snoozes = (defaults.dictionary(forKey: Key.snoozes) as? [String: Int]) ?? [:]
        snoozes[id.uuidString] = nil
        defaults.set(snoozes, forKey: Key.snoozes)
        setFollowUpID(nil, for: id)
        if pendingChallenge == id { pendingChallenge = nil }
    }

    static func notifyApp() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    // MARK: Plumbing

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
