import SwiftUI
import SwiftData

@main
struct JasaraApp: App {
    private let container: ModelContainer
    @State private var store: AppStore

    init() {
        let schema = Schema([
            TaskItem.self, Subtask.self,
            AlarmItem.self, WakeEvent.self,
            FocusSession.self,
            PrayerSettings.self, PrayerLog.self,
            XPEvent.self, StreakRecord.self, Profile.self
        ])
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema,
                                           configurations: ModelConfiguration(schema: schema))
        } catch {
            // A corrupt store must never brick the alarm. Fall back to memory and
            // let the user keep using the app for this session.
            container = try! ModelContainer(for: schema,
                                            configurations: ModelConfiguration(schema: schema,
                                                                               isStoredInMemoryOnly: true))
        }
        self.container = container
        _store = State(initialValue: AppStore(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(Backend.shared)
                .modelContainer(container)
                .preferredColorScheme(store.profile.colorScheme.scheme)
                .tint(Ink.accent)
        }
    }
}

extension ColorSchemePreference {
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
