import SwiftUI

/// Create a group alarm, or (for its creator) change one.
struct GroupAlarmEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Nil when creating.
    var existing: GroupAlarm?

    @State private var draft = GroupAlarmDraft()
    @State private var time = Date()
    @State private var isOneOff = false
    @State private var onceDate = Date().adding(days: 1)
    @State private var cutoff = Date.today(atMinutes: 21 * 60)
    @State private var mine = MemberChallenge()
    @State private var friends: [Connection] = []
    @State private var invited: Set<UUID> = []
    @State private var working = false
    @State private var error: String?

    private var isNew: Bool { existing == nil }
    private var canSave: Bool {
        !draft.label.trimmingCharacters(in: .whitespaces).isEmpty
            && (isOneOff || draft.weekdaysMask != 0) && !working
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's it for?", text: $draft.label)
                        .font(Face.rowStrong)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }

                Section {
                    Picker("Repeats", selection: $isOneOff.animation()) {
                        Text("On days").tag(false)
                        Text("Once").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if isOneOff {
                        DatePicker("Day", selection: $onceDate, in: Date().startOfDay..., displayedComponents: .date)
                    } else {
                        WeekdayPicker(mask: $draft.weekdaysMask).padding(.vertical, 4)
                    }
                }

                Section {
                    DatePicker("Lock toggles at", selection: $cutoff, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("The night before each alarm, at this time, everyone's on/off choice locks. Stops anyone switching off at 6am to save the streak.")
                }

                if isNew {
                    Section {
                        MemberChallengeFields(value: $mine)
                    } header: {
                        Text("Your challenge")
                    } footer: {
                        Text("Friends pick their own when they join.")
                    }

                    Section("Invite friends") {
                        if friends.isEmpty {
                            Text("Add friends from your profile first, then invite them here or later.")
                                .font(Face.caption).foregroundStyle(Ink.muted)
                        }
                        ForEach(friends) { friend in
                            Button {
                                if invited.contains(friend.userID) { invited.remove(friend.userID) }
                                else { invited.insert(friend.userID) }
                            } label: {
                                HStack {
                                    Text(friend.avatarEmoji)
                                    Text(friend.name).foregroundStyle(Ink.primary)
                                    Text("@\(friend.username)").font(Face.caption).foregroundStyle(Ink.muted)
                                    Spacer()
                                    Image(systemName: invited.contains(friend.userID) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(invited.contains(friend.userID) ? Palette.mint.ink : Ink.muted)
                                }
                            }
                            .accessibilityAddTraits(invited.contains(friend.userID) ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(Palette.blush.ink) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.background)
            .navigationTitle(isNew ? "New group alarm" : "Edit group alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save") { save() }.disabled(!canSave)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        if let existing {
            draft = GroupAlarmDraft(label: existing.label, hour: existing.hour, minute: existing.minute,
                                    weekdaysMask: existing.onceOn == nil ? existing.weekdaysMask : Weekdays.weekdayMask,
                                    onceOn: existing.onceDate, cutoffMinutes: existing.cutoffMinutes)
            isOneOff = existing.onceOn != nil
            onceDate = existing.onceDate ?? Date().adding(days: 1)
        } else {
            let profile = store.profile
            mine.challenge = [.nfc, .photo].contains(profile.defaultChallenge) ? .math : profile.defaultChallenge
            mine.tier = profile.defaultTier
            friends = ((try? await Backend.shared.connections()) ?? []).filter(\.isFriend)
        }
        time = Calendar.current.date(bySettingHour: draft.hour, minute: draft.minute, second: 0, of: .now) ?? .now
        cutoff = Date.today(atMinutes: draft.cutoffMinutes)
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        draft.hour = parts.hour ?? 7
        draft.minute = parts.minute ?? 0
        draft.onceOn = isOneOff ? onceDate.startOfDay : nil
        draft.cutoffMinutes = cutoff.minutesSinceMidnight
        draft.label = String(draft.label.trimmingCharacters(in: .whitespaces).prefix(40))

        Task {
            working = true
            defer { working = false }
            do {
                if let existing {
                    try await Backend.shared.updateGroup(existing.id, draft)
                } else {
                    _ = await store.scheduler.requestAuthorization()
                    _ = try await Backend.shared.createGroup(draft, mine: mine, invite: Array(invited))
                }
                await GroupAlarmSync.shared.refresh(store: store)
                dismiss()
            } catch {
                self.error = Backend.describe(error)
            }
        }
    }
}
