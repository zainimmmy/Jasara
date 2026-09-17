import SwiftUI
import SwiftData

enum AppTab: Hashable { case todo, calendar, alarm, timer }

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(GroupAlarmSync.self) private var groupSync
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @State private var tab: AppTab = DemoSeed.startTab ?? .todo
    #else
    @State private var tab: AppTab = .todo
    #endif
    @State private var showProfile = false
    @State private var ringingAlarm: AlarmItem?
    @Query private var alarms: [AlarmItem]

    /// Onboarding and a ringing alarm both take the whole screen, and SwiftUI
    /// will only honour one presentation per view — two `fullScreenCover`
    /// modifiers on the same view silently present an empty one. So they share a
    /// single cover, driven by this.
    private enum Cover: Identifiable {
        case onboarding
        case ringing(AlarmItem)

        var id: String {
            switch self {
            case .onboarding: return "onboarding"
            case .ringing(let alarm): return "ring-\(alarm.id.uuidString)"
            }
        }
    }

    private var activeCover: Cover? {
        if !store.profile.hasOnboarded { return .onboarding }
        if let ringingAlarm { return .ringing(ringingAlarm) }
        return nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $tab) {
                Tab("To do", systemImage: "checkmark.circle", value: AppTab.todo) {
                    TodoView(showProfile: $showProfile)
                }
                Tab("Calendar", systemImage: "calendar", value: AppTab.calendar) {
                    CalendarTabView(showProfile: $showProfile)
                }
                Tab("Alarm", systemImage: "alarm", value: AppTab.alarm) {
                    AlarmListView(showProfile: $showProfile)
                }
                Tab("Timer", systemImage: "timer", value: AppTab.timer) {
                    FocusTimerView(showProfile: $showProfile)
                }
            }
            .background(Ink.background)
            // The profile sheet lives on the TabView so it never competes with
            // the cover below for the same view's presentation slot.
            .sheet(isPresented: $showProfile) { ProfileView() }

            XPToast()
            AlarmSetToast()
        }
        // After a group alarm is solved, offer the wake photo once the ring screen is gone.
        .background {
            Color.clear.sheet(item: Binding(get: { ringingAlarm == nil ? groupSync.photoPrompt : nil },
                                            set: { groupSync.photoPrompt = $0 })) { checkIn in
                WakePhotoSheet(checkIn: checkIn)
            }
        }
        .fullScreenCover(item: Binding(get: { activeCover },
                                       set: { if $0 == nil { ringingAlarm = nil } })) { cover in
            switch cover {
            case .onboarding: OnboardingView()
            case .ringing(let alarm): AlarmRingView(alarm: alarm)
            }
        }
        .task {
            NotificationScheduler.shared.registerCategories()
            NotificationRouter.shared.attach(to: store)
            await NotificationScheduler.shared.removeLegacyAlarmNotifications()
            store.reconcileStreaks()
            #if DEBUG
            DemoSeed.apply(to: store)
            DemoSeed.ringIfRequested(store)
            await DemoSeed.fireIfRequested(store)
            Task { await DemoSeed.toastIfRequested(store) }
            #endif
            store.ingestAlarmRuntime()
        }
        .onChange(of: scenePhase) { _, phase in
            // Rolling one-day schedule: top notifications back up every time the
            // app comes forward, so the 64 slot budget never runs dry.
            guard phase == .active else { return }
            store.ingestAlarmRuntime()
            Task { await refreshSchedules() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AlarmRuntime.didChange)) { _ in
            store.ingestAlarmRuntime()
        }
        .onChange(of: store.ringingAlarmID) { _, id in
            guard let id else { return }
            // Fetch rather than read @Query, which can lag a cold launch from an alarm.
            let all = (try? store.context.fetch(FetchDescriptor<AlarmItem>())) ?? []
            ringingAlarm = all.first { $0.id == id }
        }
    }

    private func refreshSchedules() async {
        await store.rescheduleAlarms()
        await store.refreshPrayerNotifications()
        await GroupAlarmSync.shared.refresh(store: store)
        BackgroundRefresh.schedule()
    }
}

/// Streak and level on the left, profile on the right. No "Get Pro" up here.
struct TopBar: ToolbarContent {
    @Environment(AppStore.self) private var store
    @Binding var showProfile: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 6) {
                StreakFlame(count: store.streak(.daily).count)
                LevelBadge(level: store.profile.level,
                           fraction: Leveling.progress(forTotalXP: store.profile.totalXP).fraction)
            }
            // Without this, the toolbar squeezes both pills down to nothing.
            .fixedSize()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showProfile = true } label: {
                Text(store.profile.avatarEmoji)
                    .font(.system(size: 18))
                    .frame(width: 32, height: 32)
                    .background(Palette.sky.fill, in: Circle())
            }
            .accessibilityLabel("Profile, friends and settings")
        }
    }
}

/// A small "+20 Woke up on time" that fades in and out. Rewards should never nag.
struct XPToast: View {
    @Environment(AppStore.self) private var store
    @State private var shown: (amount: Int, reason: XPReason)?

    var body: some View {
        Group {
            if let shown {
                HStack(spacing: 8) {
                    Text(shown.amount >= 0 ? "+\(shown.amount)" : "\(shown.amount)")
                        .font(Face.title(17)).monospacedDigit()
                    Text(shown.reason.title).font(Face.caption)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Palette.mint.fill, in: Capsule())
                .foregroundStyle(Palette.mint.ink)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: shown?.amount)
        .onChange(of: store.lastAward?.at) { _, _ in
            guard let award = store.lastAward else { return }
            shown = (award.amount, award.reason)
            Task {
                try? await Task.sleep(for: .seconds(1.8))
                shown = nil
            }
        }
        .accessibilityHidden(true)
    }
}
