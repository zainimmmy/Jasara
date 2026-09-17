import SwiftUI

/// Group alarms at the top of the Alarm tab: invites waiting for an answer, the
/// groups you're in, and a way to start one.
struct GroupAlarmsSection: View {
    @Environment(AppStore.self) private var store
    @Environment(Backend.self) private var backend
    @Environment(GroupAlarmSync.self) private var sync

    @State private var creating = false
    @State private var answering: GroupAlarm?
    @State private var showFriends = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderRow(title: "Group alarms", symbol: "person.3", palette: .lilac,
                             count: sync.joined.count,
                             onAdd: backend.isSignedIn ? { creating = true } : nil)

            if !backend.isConfigured {
                hint("Group alarms need an account, which isn't switched on in this build.")
            } else if !backend.isSignedIn {
                Button { showFriends = true } label: {
                    hint("Create an account to set alarms with friends and keep a streak together. →")
                }
                .buttonStyle(.plain)
            } else {
                ForEach(sync.invites) { invite in
                    Button { answering = invite } label: { inviteRow(invite) }
                        .buttonStyle(.plain)
                }
                ForEach(sync.joined) { group in
                    NavigationLink {
                        GroupAlarmDetailView(groupID: group.id)
                    } label: {
                        groupRow(group)
                    }
                    .buttonStyle(.plain)
                }
                if sync.joined.isEmpty && sync.invites.isEmpty {
                    DashedAddRow(title: "Start a group alarm") { creating = true }
                }
                if let error = sync.lastError, sync.groups.isEmpty {
                    Text(error).font(Face.caption).foregroundStyle(Ink.muted)
                }
            }
        }
        .sheet(isPresented: $creating) { GroupAlarmEditorView(existing: nil) }
        .sheet(item: $answering) { JoinGroupSheet(group: $0) }
        .sheet(isPresented: $showFriends) {
            NavigationStack { FriendsView() }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(Face.caption)
            .foregroundStyle(Ink.muted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
    }

    private func inviteRow(_ invite: GroupAlarm) -> some View {
        HStack(spacing: 12) {
            EmojiBubble(emoji: "📨", palette: .butter)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(invite.label) • \(invite.timeText)").font(Face.rowStrong)
                Text("@\(invite.invitedByUsername ?? invite.creatorUsername) invited you • \(invite.scheduleText)")
                    .font(Face.caption).foregroundStyle(Ink.muted)
            }
            Spacer()
            Text("Answer").font(Face.caption.weight(.bold)).foregroundStyle(Palette.butter.ink)
        }
        .padding(12)
        .background(Palette.butter.fill.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
    }

    private func groupRow(_ group: GroupAlarm) -> some View {
        Card {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(group.timeText).font(Face.display(30)).monospacedDigit()
                            .foregroundStyle(group.isOn || group.countsNext ? Ink.primary : Ink.muted)
                        if group.nextLocked {
                            Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(Ink.muted)
                                .accessibilityLabel("Locked for the next alarm")
                        }
                    }
                    Text("\(group.label) • \(group.scheduleText)").font(Face.rowStrong)
                    HStack(spacing: 6) {
                        Text("👥 \(group.memberCount)")
                        Text("\(group.challengeKind.emoji) \(group.challengeKind.title)")
                        if !group.isOn { Text(group.countsNext ? "• off after next" : "• off") }
                    }
                    .font(Face.caption).foregroundStyle(Ink.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Ink.muted)
            }
        }
    }
}
