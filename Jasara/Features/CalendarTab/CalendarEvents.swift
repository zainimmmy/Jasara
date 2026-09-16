import Foundation
import EventKit
import Observation

/// Read-only bridge to Apple Calendar (and anything synced into it). Access is
/// asked for the first time someone opens the Calendar tab and taps Connect, not
/// during onboarding, and the app is fully usable if it's refused.
@Observable
@MainActor
final class CalendarEvents {
    struct Item: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        var section: DaySection {
            isAllDay ? .anytime : DaySection.forHour(Calendar.current.component(.hour, from: start))
        }
    }

    private(set) var items: [Item] = []
    private(set) var isConnected = false
    private let store = EKEventStore()

    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        isConnected = granted
    }

    func refresh(for day: Date) {
        guard isConnected || EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        isConnected = true
        let start = day.startOfDay
        let end = start.adding(days: 1)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        items = store.events(matching: predicate).map {
            Item(id: $0.eventIdentifier ?? UUID().uuidString,
                 title: $0.title ?? "Event",
                 start: $0.startDate,
                 end: $0.endDate,
                 isAllDay: $0.isAllDay)
        }
    }
}
