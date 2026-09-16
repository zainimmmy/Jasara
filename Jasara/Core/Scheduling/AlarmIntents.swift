import Foundation
import AlarmKit
import AppIntents

// The intents AlarmKit runs when someone stops or snoozes a ringing alarm. They
// run inside the app's process, possibly with no UI yet, so they only touch
// AlarmRuntime and AlarmManager and leave SwiftData to the app.

/// Regular alarm stopped: that's a wake. Log it for the app to turn into XP.
struct StopRegularAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop alarm"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Alarm") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        AlarmRuntime.enqueueWake(PendingWake(alarmID: id, snoozes: AlarmRuntime.snoozes(for: id), at: .now))
        AlarmKitScheduler.settle(id)
        AlarmRuntime.notifyApp()
        return .result()
    }
}

/// Challenge alarm stopped before the challenge was solved. Open the app on the
/// challenge and arm a follow-up, so going back to sleep isn't an option.
struct StopChallengeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open challenge"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Alarm") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        AlarmRuntime.pendingChallenge = id
        if let snapshot = AlarmRuntime.snapshot(for: id) {
            await AlarmKitScheduler.scheduleFollowUp(snapshot,
                                                     after: AlarmKitScheduler.challengeFollowUpDelay,
                                                     snoozesUsed: AlarmRuntime.snoozes(for: id))
        }
        AlarmRuntime.notifyApp()
        return .result()
    }
}

/// Snooze from the alarm itself, without opening the app. Counts toward the
/// tier's snooze cap and the XP penalty.
struct SnoozeAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Snooze alarm"
    static var isDiscoverable: Bool { false }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Alarm") var alarmID: String

    init() {}
    init(alarmID: String) { self.alarmID = alarmID }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID),
              let snapshot = AlarmRuntime.snapshot(for: id) else { return .result() }
        let used = AlarmRuntime.addSnooze(for: id)
        await AlarmKitScheduler.scheduleFollowUp(snapshot,
                                                 after: Double(snapshot.snoozeMinutes) * 60,
                                                 snoozesUsed: used)
        AlarmRuntime.notifyApp()
        return .result()
    }
}
