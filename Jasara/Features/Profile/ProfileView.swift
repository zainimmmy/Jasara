import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    @Query private var wakeEvents: [WakeEvent]
    @State private var showSettings = false

    private var progress: (level: Int, into: Int, needed: Int, fraction: Double) {
        Leveling.progress(forTotalXP: store.profile.totalXP)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    identityCard
                    levelCard
                    streakCard
                    wakeCard
                    friendsCard
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 40)
            }
            .background(Ink.background)
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var identityCard: some View {
        Card {
            HStack(spacing: 14) {
                Text(store.profile.avatarEmoji)
                    .font(.system(size: 30))
                    .frame(width: 60, height: 60)
                    .background(Palette.sky.fill, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.profile.displayName.isEmpty ? "You" : store.profile.displayName)
                        .font(Face.title(20))
                    Text(backend.me.map { "@\($0.username)" }
                         ?? (store.profile.isGuest ? "Using the app without an account" : "@\(store.profile.username)"))
                        .font(Face.caption).foregroundStyle(Ink.muted)
                    Text(Leveling.title(for: progress.level))
                        .font(Face.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.butter.fill, in: Capsule())
                        .foregroundStyle(Palette.butter.ink)
                }
                Spacer()
            }
        }
    }

    private var levelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Level \(progress.level)").font(Face.title(20))
                    Spacer()
                    Text("\(store.profile.totalXP) XP total")
                        .font(Face.caption).foregroundStyle(Ink.muted).monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Ink.line)
                        Capsule().fill(Palette.lilac.ink)
                            .frame(width: geo.size.width * progress.fraction)
                    }
                }
                .frame(height: 10)
                Text(progress.level >= Leveling.maxLevel
                     ? "Max level. There were 365 of them, one for each day."
                     : "\(progress.needed - progress.into) XP to level \(progress.level + 1)")
                    .font(Face.caption).foregroundStyle(Ink.muted).monospacedDigit()
            }
        }
    }

    private var streakCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Streaks").font(Face.sectionTitle)
                streakRow("🔥", "Daily", store.streak(.daily))
                Divider().overlay(Ink.line)
                streakRow("⏰", "Wake", store.streak(.wake))
                Text("Milestones at \(XPRules.milestoneLabel) days. Streak freezes are earned with XP, never sold.")
                    .font(Face.caption).foregroundStyle(Ink.muted)
            }
        }
    }

    private func streakRow(_ emoji: String, _ title: String, _ record: StreakRecord) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Face.rowStrong)
                Text("Best \(record.best) day\(record.best == 1 ? "" : "s")")
                    .font(Face.caption).foregroundStyle(Ink.muted)
            }
            Spacer()
            Text("\(record.count)")
                .font(Face.display(26)).monospacedDigit()
            if record.freezes > 0 {
                Text("🧊\(record.freezes)").font(Face.caption)
            }
        }
    }

    private var wakeCard: some View {
        let recent = wakeEvents.sorted { $0.scheduledAt > $1.scheduledAt }.prefix(5)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent wake-ups").font(Face.sectionTitle)
                if recent.isEmpty {
                    Text("Nothing logged yet. Set an alarm and it'll show up here.")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                } else {
                    ForEach(Array(recent)) { event in
                        HStack(spacing: 10) {
                            Text(event.wasOnTime ? "✅" : "🆘")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(Face.caption)
                                Text(event.emergencyStopped
                                     ? "Emergency stop"
                                     : "\(event.tier.title) • \(event.snoozes) snooze\(event.snoozes == 1 ? "" : "s")")
                                    .font(Face.caption).foregroundStyle(Ink.muted)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var friendsCard: some View {
        NavigationLink {
            FriendsView()
        } label: {
            Card {
                HStack(spacing: 12) {
                    Text("👥").font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Friends").font(Face.sectionTitle)
                        Text(backend.isSignedIn
                             ? "Add people by username, answer requests, block or report."
                             : "Create an account to add friends. Group alarms come next.")
                            .font(Face.caption).foregroundStyle(Ink.muted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Ink.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
