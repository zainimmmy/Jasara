import Foundation
import UserNotifications
import SwiftData

/// Turns a delivered notification into something the app does: "Prayed" ticks a
/// prayer off without opening anything, "Mark done" completes a task. Alarms
/// don't come through here — they belong to AlarmKit and its intents.
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    weak var store: AppStore?

    func attach(to store: AppStore) {
        self.store = store
        UNUserNotificationCenter.current().delegate = self
    }

    /// Show reminders and prayer nudges even while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        await handle(notification.request.content.userInfo, action: nil)
        return [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await handle(response.notification.request.content.userInfo,
                     action: response.actionIdentifier)
    }

    private func handle(_ userInfo: [AnyHashable: Any], action: String?) {
        guard let store else { return }

        if let raw = userInfo["prayer"] as? Int, let prayer = PrayerName(rawValue: raw) {
            if action == "PRAYED" {
                let entry = store.prayers.entries(for: .now, settings: store.prayerSettings)?
                    .first { $0.prayer == prayer }
                store.mark(prayer, on: .now, as: .prayed, scheduledAt: entry?.time)
            }
            return
        }

        if action == "COMPLETE", let raw = userInfo["taskID"] as? String,
           let id = UUID(uuidString: raw) {
            let task = (try? store.context.fetch(FetchDescriptor<TaskItem>()))?
                .first { $0.id == id }
            if let task, !task.isDone { store.toggle(task) }
        }
    }
}
