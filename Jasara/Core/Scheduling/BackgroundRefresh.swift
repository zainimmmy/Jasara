import Foundation
import BackgroundTasks

/// A daily wake-up from iOS, so prayer reminders and group alarm changes stay
/// current on days the app isn't opened. Alarms themselves don't need it:
/// AlarmKit rings them regardless.
enum BackgroundRefresh {
    /// Must match BGTaskSchedulerPermittedIdentifiers in Config/Info.plist.
    static let identifier = "com.Zoon.Jasara.refresh"

    /// Asks for a run a little after midnight. iOS picks the real time.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        let tomorrow = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 3600 + 15 * 60)
        request.earliestBeginDate = tomorrow
        try? BGTaskScheduler.shared.submit(request)
    }
}
