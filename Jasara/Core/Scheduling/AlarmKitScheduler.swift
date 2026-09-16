import Foundation
import SwiftUI
import AlarmKit
import AppIntents

/// Travels with every AlarmKit alarm so the system UI and our intents can tell
/// which of the user's alarms is ringing.
struct JasaraAlarmMetadata: AlarmMetadata {
    var alarmID: UUID
    var isChallenge: Bool
}

/// Real alarms. AlarmKit is the only public way to ring through silent mode and
/// Focus, and it keeps working when the app has been quit or the phone restarted.
///
/// How a challenge alarm is enforced: the system always offers a stop control, so
/// its stop intent opens the app, straight into the challenge, and arms a
/// follow-up alarm a minute out. Stopping that one does the same again. Only
/// finishing the challenge (or the emergency stop) cancels the follow-up.
final class AlarmKitScheduler: AlarmScheduling {
    static let shared = AlarmKitScheduler()

    /// How long a stopped-but-unsolved challenge alarm waits before ringing again.
    static let challengeFollowUpDelay: TimeInterval = 60

    private let manager = AlarmManager.shared

    var isAuthorized: Bool { manager.authorizationState == .authorized }

    func requestAuthorization() async -> Bool {
        switch manager.authorizationState {
        case .authorized: return true
        case .denied: return false
        case .notDetermined:
            return (try? await manager.requestAuthorization()) == .authorized
        @unknown default: return false
        }
    }

    // MARK: - AlarmScheduling

    func schedule(_ alarm: AlarmItem) async {
        try? manager.cancel(id: alarm.id)
        let snapshot = AlarmSnapshot(alarm)
        AlarmRuntime.save(snapshot)
        guard alarm.isEnabled, await requestAuthorization() else { return }

        let time = Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        let repeats: Alarm.Schedule.Relative.Recurrence = alarm.repeatsWeekly
            ? .weekly(Self.weekdays(from: alarm.weekdaysMask))
            : .never
        let configuration = Self.configuration(for: snapshot,
                                               schedule: .relative(.init(time: time, repeats: repeats)),
                                               snoozesUsed: 0)
        do {
            _ = try await manager.schedule(id: alarm.id, configuration: configuration)
        } catch {
            print("AlarmKit refused to schedule \(alarm.id): \(error)")
        }
    }

    func cancel(_ alarm: AlarmItem) async {
        try? manager.cancel(id: alarm.id)
        await cancelFollowUps(for: alarm)
        AlarmRuntime.forget(alarm.id)
    }

    /// Used by the in-app snooze button on the ring screen.
    func scheduleFollowUp(for alarm: AlarmItem, after seconds: TimeInterval) async {
        let snapshot = AlarmSnapshot(alarm)
        AlarmRuntime.save(snapshot)
        await Self.scheduleFollowUp(snapshot, after: seconds, snoozesUsed: AlarmRuntime.snoozes(for: alarm.id))
    }

    /// The wake is settled — solved, stopped, or emergency-stopped.
    func cancelFollowUps(for alarm: AlarmItem) async {
        Self.settle(alarm.id)
    }

    // MARK: - Shared with the intents

    static func scheduleFollowUp(_ snapshot: AlarmSnapshot, after seconds: TimeInterval, snoozesUsed: Int) async {
        let manager = AlarmManager.shared
        if let previous = AlarmRuntime.followUpID(for: snapshot.alarmID) {
            try? manager.cancel(id: previous)
        }
        let followUpID = UUID()
        AlarmRuntime.setFollowUpID(followUpID, for: snapshot.alarmID)
        let configuration = configuration(for: snapshot,
                                          schedule: .fixed(Date().addingTimeInterval(max(seconds, 5))),
                                          snoozesUsed: snoozesUsed)
        do {
            _ = try await manager.schedule(id: followUpID, configuration: configuration)
        } catch {
            print("AlarmKit refused the follow-up for \(snapshot.alarmID): \(error)")
        }
    }

    /// Stops anything still ringing for this alarm and clears its runtime state.
    static func settle(_ alarmID: UUID) {
        let manager = AlarmManager.shared
        if let followUp = AlarmRuntime.followUpID(for: alarmID) {
            try? manager.cancel(id: followUp)
        }
        // A repeating alarm must only be *stopped*: cancelling it would delete
        // tomorrow's occurrence too.
        if (try? manager.alarms)?.contains(where: { $0.id == alarmID && $0.state == .alerting }) == true {
            try? manager.stop(id: alarmID)
        }
        AlarmRuntime.clearWake(for: alarmID)
    }

    static func configuration(for snapshot: AlarmSnapshot,
                              schedule: Alarm.Schedule,
                              snoozesUsed: Int) -> AlarmManager.AlarmConfiguration<JasaraAlarmMetadata> {
        let canSnooze = snoozesUsed < snapshot.maxSnoozes
        let snoozeButton = AlarmButton(text: "Snooze",
                                       textColor: .white,
                                       systemImageName: "zzz")
        let title = LocalizedStringResource(stringLiteral: snapshot.title)

        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title,
                                            secondaryButton: canSnooze ? snoozeButton : nil,
                                            secondaryButtonBehavior: canSnooze ? .custom : nil)
        } else {
            alert = AlarmPresentation.Alert(title: title,
                                            stopButton: AlarmButton(text: "Stop",
                                                                    textColor: .white,
                                                                    systemImageName: "stop.circle"),
                                            secondaryButton: canSnooze ? snoozeButton : nil,
                                            secondaryButtonBehavior: canSnooze ? .custom : nil)
        }

        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: JasaraAlarmMetadata(alarmID: snapshot.alarmID,
                                                                       isChallenge: snapshot.isChallenge),
                                         tintColor: Color(red: 0.216, green: 0.251, blue: 0.769))

        let id = snapshot.alarmID.uuidString
        let stopIntent: any LiveActivityIntent = snapshot.isChallenge
            ? StopChallengeAlarmIntent(alarmID: id)
            : StopRegularAlarmIntent(alarmID: id)

        return .alarm(schedule: schedule,
                      attributes: attributes,
                      stopIntent: stopIntent,
                      secondaryIntent: canSnooze ? SnoozeAlarmIntent(alarmID: id) : nil,
                      sound: .default)
    }

    /// Mask bit per Calendar weekday (1 = Sunday) → AlarmKit's weekday list.
    static func weekdays(from mask: Int) -> [Locale.Weekday] {
        let order: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
        return (1...7).filter { Weekdays.contains(mask, weekday: $0) }.map { order[$0 - 1] }
    }

    // MARK: - Task reminders set to "Alarm"

    /// A task reminder set to Alarm rings like an alarm, through silent and Focus.
    func scheduleTaskAlarm(id: UUID, title: String, at date: Date) async {
        try? manager.cancel(id: id)
        guard date > .now, await requestAuthorization() else { return }
        let resource = LocalizedStringResource(stringLiteral: title)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: resource)
        } else {
            alert = AlarmPresentation.Alert(title: resource,
                                            stopButton: AlarmButton(text: "Stop",
                                                                    textColor: .white,
                                                                    systemImageName: "stop.circle"))
        }
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: JasaraAlarmMetadata(alarmID: id, isChallenge: false),
                                         tintColor: Color(red: 0.216, green: 0.251, blue: 0.769))
        do {
            _ = try await manager.schedule(id: id,
                                           configuration: .alarm(schedule: .fixed(date),
                                                                 attributes: attributes))
        } catch {
            print("AlarmKit refused the task alarm \(id): \(error)")
        }
    }

    func cancelTaskAlarm(id: UUID) {
        try? manager.cancel(id: id)
    }
}
