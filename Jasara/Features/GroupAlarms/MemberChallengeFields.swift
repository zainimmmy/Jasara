import SwiftUI

/// The per-member part of a group alarm: your challenge, difficulty and rounds.
/// Everyone in a group picks their own.
struct MemberChallengeFields: View {
    @Binding var value: MemberChallenge
    @State private var previewing = false

    /// NFC and Photo need hardware set up per phone, so groups skip them for now.
    private let options: [Challenge] = [.math, .shake, .typing, .tiles, .overstimulated]

    var body: some View {
        Picker("Challenge", selection: $value.challenge) {
            ForEach(options) { option in
                Text("\(option.emoji)  \(option.title)").tag(option)
            }
        }
        if value.challenge.supportsTiers {
            Picker("Difficulty", selection: $value.tier) {
                ForEach(Tier.allCases) { Text($0.title).tag($0) }
            }
            Stepper("Rounds: \(value.rounds)", value: $value.rounds, in: 1...100)
        } else {
            Text(value.challenge.blurb).font(Face.caption).foregroundStyle(Ink.muted)
        }
        Button {
            previewing = true
        } label: {
            Label("Try it (silent)", systemImage: "play.circle")
        }
        .fullScreenCover(isPresented: $previewing) {
            ChallengePreview(challenge: value.challenge, tier: value.tier,
                             rounds: min(value.rounds, 2), wordCount: 6)
        }
    }
}

/// Accepting an invite: see what you're signing up for, pick your challenge, join.
struct JoinGroupSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var group: GroupAlarm

    @State private var mine = MemberChallenge()
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.label).font(Face.title(22))
                        Text("\(group.timeText) • \(group.scheduleText)")
                            .font(Face.rowStrong)
                        Text("@\(group.invitedByUsername ?? group.creatorUsername) invited you. \(group.memberCount) in so far.")
                            .font(Face.caption).foregroundStyle(Ink.muted)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    MemberChallengeFields(value: $mine)
                } header: {
                    Text("Your challenge")
                } footer: {
                    Text("Only you see this. Everyone in the group picks their own.")
                }
                Section {
                    Label("You can switch your alarm off any time before \(group.cutoffText) the night before. After that, the next morning is locked in.",
                          systemImage: "lock.clock")
                        .font(Face.caption)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Palette.blush.ink) }
                }
            }
            .navigationTitle("Group alarm invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Decline", role: .destructive) { respond(accept: false) }
                        .disabled(working)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { respond(accept: true) }.disabled(working)
                }
            }
            .onAppear {
                mine.challenge = store.profile.defaultChallenge == .nfc || store.profile.defaultChallenge == .photo
                    ? .math : store.profile.defaultChallenge
                mine.tier = store.profile.defaultTier
            }
        }
    }

    private func respond(accept: Bool) {
        Task {
            working = true
            defer { working = false }
            do {
                try await Backend.shared.respondToInvite(group.id, accept: accept, mine: mine)
                if accept { _ = await store.scheduler.requestAuthorization() }
                await GroupAlarmSync.shared.refresh(store: store)
                dismiss()
            } catch {
                self.error = Backend.describe(error)
            }
        }
    }
}
