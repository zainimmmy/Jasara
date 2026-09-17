import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Backend.self) private var backend
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showPrayerSetup = false
    @State private var showExplainer = false
    @State private var confirmingWipe = false
    @State private var confirmingAccountDeletion = false
    @State private var showAccount = false
    @State private var accountError: String?
    @State private var pendingNotifications = 0

    var body: some View {
        @Bindable var profile = store.profile

        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Display name", text: $profile.displayName)
                    HStack {
                        Text("Username")
                        Spacer()
                        Text(profile.username.isEmpty ? "Not set" : "@\(profile.username)")
                            .foregroundStyle(Ink.muted)
                    }
                    HStack {
                        Text("Avatar")
                        Spacer()
                        Menu(profile.avatarEmoji) {
                            ForEach(["🌤️", "🌙", "🔥", "🌱", "⚡️", "🫧", "🦊", "🐢"], id: \.self) { option in
                                Button(option) { profile.avatarEmoji = option; store.save() }
                            }
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Appearance", selection: Binding(
                        get: { profile.colorScheme },
                        set: { profile.colorScheme = $0; store.save() }
                    )) {
                        ForEach(ColorSchemePreference.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Toggle("Haptics", isOn: $profile.hapticsOn)
                    Text("Text size follows the system setting, so Dynamic Type just works.")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }

                Section("App settings") {
                    Toggle("Week starts on Monday", isOn: $profile.firstWeekdayIsMonday)
                    Toggle("Timeline calendar layout", isOn: $profile.calendarTimelineView)
                    if profile.calendarTimelineView {
                        Text("The timeline view is still to come — the list view is what's built.")
                            .font(Face.caption).foregroundStyle(Palette.butter.ink)
                    }
                    HStack {
                        Text("Scheduled notifications")
                        Spacer()
                        Text("\(pendingNotifications) of \(NotificationBudget.systemLimit)")
                            .foregroundStyle(Ink.muted).monospacedDigit()
                    }
                }

                Section("Alarms") {
                    Picker("Default challenge", selection: Binding(
                        get: { profile.defaultChallenge },
                        set: { profile.defaultChallenge = $0; store.save() }
                    )) {
                        ForEach(Challenge.allCases.filter(\.isImplemented)) { option in
                            Text("\(option.emoji)  \(option.title)").tag(option)
                        }
                    }
                    Picker("Default difficulty", selection: Binding(
                        get: { profile.defaultTier },
                        set: { profile.defaultTier = $0; store.save() }
                    )) {
                        ForEach(Tier.allCases) { Text($0.title).tag($0) }
                    }
                    Button("How challenge alarms work") { showExplainer = true }
                    Label("Emergency stop: hold the button for 10 seconds on the alarm screen. It always works.",
                          systemImage: "sos")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }

                Section("Prayer") {
                    Button(store.prayerSettings.isEnabled ? "Prayer settings" : "Set up daily prayers") {
                        showPrayerSetup = true
                    }
                    if store.prayerSettings.isEnabled {
                        HStack {
                            Text("Counts toward XP")
                            Spacer()
                            Text(store.prayerSettings.countsForXP ? "Yes" : "No")
                                .foregroundStyle(Ink.muted)
                        }
                    }
                }

                Section("Privacy and safety") {
                    Text("Block and report from any person in Friends, and unblock people there too. Calendar sharing arrives with group alarms.")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }

                Section("Purchases") {
                    HStack {
                        Text("Pro")
                        Spacer()
                        Text(profile.isPro ? "Unlocked" : "Not yet available")
                            .foregroundStyle(Ink.muted)
                    }
                    Text("One-time unlock and cosmetic packs only. No ads, no subscriptions, no paid XP or streak freezes. Safety features are never behind a purchase.")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }

                Section("Account") {
                    if backend.isSignedIn {
                        LabeledContent("Signed in as", value: backend.email ?? "—")
                        if let me = backend.me {
                            LabeledContent("Username", value: "@\(me.username)")
                        }
                        Button("Sign out") {
                            Task {
                                await backend.signOut()
                                GroupAlarmSync.shared.removeAllGroupAlarms(store: store)
                                profile.isGuest = true
                                store.save()
                            }
                        }
                        Button("Delete account", role: .destructive) { confirmingAccountDeletion = true }
                    } else {
                        Text("You're using the app without an account. Everything lives on this phone.")
                            .font(Face.caption).foregroundStyle(Ink.muted)
                        if backend.isConfigured {
                            Button("Create an account or sign in") { showAccount = true }
                        }
                    }
                    Button("Delete everything on this device", role: .destructive) {
                        confirmingWipe = true
                    }
                    if let accountError {
                        Text(accountError).font(Face.caption).foregroundStyle(Palette.blush.ink)
                    }
                }

                Section("Legal") {
                    Text("Privacy policy, terms of service and open source licences go here before release.")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                    Text(PrayerService.disclaimer)
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.save(); dismiss() }
                }
            }
            .sheet(isPresented: $showPrayerSetup) { PrayerSetupView() }
            .sheet(isPresented: $showExplainer) { ChallengeExplainer() }
            .confirmationDialog("Delete everything?", isPresented: $confirmingWipe, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { wipe() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Tasks, alarms, prayer logs, XP and streaks are erased from this phone. This can't be undone.")
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmingAccountDeletion,
                                titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    Task {
                        do {
                            try await backend.deleteAccount()
                            GroupAlarmSync.shared.removeAllGroupAlarms(store: store)
                            profile.isGuest = true
                            profile.username = ""
                            wipe()
                        } catch {
                            accountError = Backend.describe(error)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your account, username, friends and everything on this phone are deleted. This can't be undone.")
            }
            .sheet(isPresented: $showAccount) {
                NavigationStack {
                    ScrollView {
                        AccountView(mode: .signIn) { showAccount = false }
                            .padding(Metric.gutter)
                    }
                    .background(Ink.background)
                    .navigationTitle("Account")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { showAccount = false } }
                    }
                }
            }
            .task { pendingNotifications = await NotificationScheduler.shared.pendingCount() }
        }
    }

    /// Account deletion has to erase local data too, not just the server copy.
    private func wipe() {
        for alarm in (try? context.fetch(FetchDescriptor<AlarmItem>())) ?? [] {
            store.scheduler.cancel(alarmID: alarm.id)
        }
        NotificationScheduler.shared.cancelPrayers()
        try? context.delete(model: TaskItem.self)
        try? context.delete(model: Subtask.self)
        try? context.delete(model: AlarmItem.self)
        try? context.delete(model: WakeEvent.self)
        try? context.delete(model: FocusSession.self)
        try? context.delete(model: PrayerLog.self)
        try? context.delete(model: XPEvent.self)
        store.profile.totalXP = 0
        for kind in [StreakKind.daily, .wake] {
            let record = store.streak(kind)
            record.count = 0
            record.best = 0
            record.lastDay = nil
            record.freezes = 0
        }
        store.prayerSettings.isEnabled = false
        store.save()
        dismiss()
    }
}
