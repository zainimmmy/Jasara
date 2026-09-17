import SwiftUI
import SwiftData

struct GroupAlarmDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(Backend.self) private var backend
    @Environment(GroupAlarmSync.self) private var sync
    @Environment(\.dismiss) private var dismiss

    var groupID: UUID

    @State private var board: [GroupMemberDay] = []
    @State private var boardDay = Date()
    @State private var streak = 0
    @State private var mine = MemberChallenge()
    @State private var savedMine = MemberChallenge()
    @State private var loading = true
    @State private var working = false
    @State private var error: String?
    @State private var notice: String?
    @State private var editing = false
    @State private var inviting = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var reportingPhoto: GroupMemberDay?

    private var group: GroupAlarm? { sync.groups.first { $0.id == groupID } }
    private var isCreator: Bool { group?.creatorID == backend.userID }

    var body: some View {
        ScrollView {
            if let group {
                VStack(alignment: .leading, spacing: 16) {
                    header(group)
                    toggleCard(group)
                    boardCard(group)
                    challengeCard
                    actions(group)
                    if let error {
                        Text(error).font(Face.caption).foregroundStyle(Palette.blush.ink)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 40)
            } else {
                EmptyHint(emoji: "👋", text: "You're no longer in this group.")
            }
        }
        .background(Ink.background)
        .navigationTitle(group?.label ?? "Group alarm")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
        .sheet(isPresented: $editing) { GroupAlarmEditorView(existing: group) }
        .sheet(isPresented: $inviting) { InviteFriendsSheet(groupID: groupID, existing: board.map(\.userID)) }
        .sheet(item: $reportingPhoto) { member in
            ReportPhotoSheet(groupID: groupID, day: boardDay, member: member)
                .presentationDetents([.medium])
        }
        .confirmationDialog("Leave this group alarm?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { run { try await backend.leaveGroup(groupID) } then: { dismiss() } }
        } message: {
            Text(isCreator ? "Someone else in the group takes over. If you're the only one, it's deleted." :
                 "Your alarm for this group stops ringing on this phone.")
        }
        .confirmationDialog("Delete this group alarm for everyone?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { run { try await backend.deleteGroup(groupID) } then: { dismiss() } }
        }
    }

    // MARK: - Sections

    private func header(_ group: GroupAlarm) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.timeText).font(Face.display(40)).monospacedDigit()
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("🔥 \(streak)").font(Face.title(20)).monospacedDigit()
                        Text("group streak").font(Face.caption).foregroundStyle(Ink.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(group.scheduleText).font(Face.rowStrong)
                Text("\(group.memberCount) in • made by @\(group.creatorUsername) • locks at \(group.cutoffText) the night before")
                    .font(Face.caption).foregroundStyle(Ink.muted)
            }
        }
    }

    /// The on/off switch, with the cutoff spelled out: what you change and what
    /// you can't.
    private func toggleCard(_ group: GroupAlarm) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(get: { group.isOn }, set: { setOn($0) })) {
                    Text("My alarm").font(Face.rowStrong)
                }
                .tint(Palette.mint.ink)
                .disabled(working)
                Text(lockExplanation(group))
                    .font(Face.caption)
                    .foregroundStyle(group.nextLocked ? Palette.butter.ink : Ink.muted)
                if let notice {
                    Text(notice).font(Face.caption).foregroundStyle(Palette.mint.ink)
                }
            }
        }
    }

    private func lockExplanation(_ group: GroupAlarm) -> String {
        guard let next = group.nextDate else {
            return group.onceOn != nil ? "This one-off alarm has already rung." : "No alarm coming up."
        }
        let day = relativeDay(next)
        if !group.nextLocked {
            return group.isOn
                ? "You're in for \(day). You can switch off until \(group.cutoffText) the night before."
                : "You're out for \(day). Switch on before \(group.cutoffText) the night before to count."
        }
        switch (group.isOn, group.countsNext) {
        case (true, true):   return "Locked in for \(day). 🔒"
        case (false, false): return "Locked out for \(day). Changes apply after that."
        case (false, true):  return "\(day.capitalizedFirst) is locked in, so it still rings and counts. You're off after that."
        case (true, false):  return "\(day.capitalizedFirst) was locked before you switched on: it rings but doesn't count."
        }
    }

    private func boardCard(_ group: GroupAlarm) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(boardDay.isSameDay(as: .now) ? "This morning" : relativeDay(boardDay).capitalizedFirst)
                        .font(Face.sectionTitle)
                    Spacer()
                    Button { shiftDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                        .accessibilityLabel("Previous day")
                    Button { shiftDay(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                        .disabled(boardDay.isSameDay(as: .now))
                        .accessibilityLabel("Next day")
                }
                if loading && board.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else if board.isEmpty {
                    Text("Nobody here yet.").font(Face.caption).foregroundStyle(Ink.muted)
                }
                ForEach(board) { member in
                    MemberBoardRow(member: member, isMe: member.userID == backend.userID,
                                   onReportPhoto: { reportingPhoto = member },
                                   onBlock: { run { try await backend.block(member.userID) } })
                }
            }
        }
    }

    private var challengeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My challenge").font(Face.sectionTitle).padding(.horizontal, 4)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Challenge", selection: $mine.challenge) {
                        ForEach([Challenge.math, .shake, .typing, .tiles, .overstimulated]) {
                            Text("\($0.emoji)  \($0.title)").tag($0)
                        }
                    }
                    if mine.challenge.supportsTiers {
                        Picker("Difficulty", selection: $mine.tier) {
                            ForEach(Tier.allCases) { Text($0.title).tag($0) }
                        }
                        Stepper("Rounds: \(mine.rounds)", value: $mine.rounds, in: 1...100)
                    }
                    if mine != savedMine {
                        PrimaryButton(title: "Save my challenge", palette: .lilac, isEnabled: !working) {
                            run { try await backend.updateMyChallenge(groupID, mine) } then: { savedMine = mine }
                        }
                    }
                }
            }
        }
    }

    private func actions(_ group: GroupAlarm) -> some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Invite friends", palette: .sky) { inviting = true }
            if isCreator {
                PrimaryButton(title: "Edit time and days", palette: .sand) { editing = true }
            }
            Button("Leave group", role: .destructive) { confirmLeave = true }
                .frame(minHeight: Metric.minTarget)
            if isCreator {
                Button("Delete for everyone", role: .destructive) { confirmDelete = true }
                    .frame(minHeight: Metric.minTarget)
            }
        }
    }

    // MARK: - Actions

    private func reload() async {
        loading = true
        defer { loading = false }
        await sync.refresh(store: store)
        if let group {
            mine = MemberChallenge(challenge: group.challengeKind, tier: group.tierKind, rounds: group.rounds)
            savedMine = mine
        }
        await loadBoard()
    }

    private func loadBoard() async {
        do {
            async let day = backend.groupDay(groupID, day: boardDay)
            async let count = backend.groupStreak(groupID)
            board = try await day
            streak = try await count
            error = nil
        } catch {
            self.error = Backend.describe(error)
        }
    }

    private func shiftDay(_ offset: Int) {
        boardDay = boardDay.adding(days: offset)
        Task { await loadBoard() }
    }

    private func setOn(_ on: Bool) {
        run {
            let from = try await backend.setGroupAlarm(groupID, on: on)
            if let from, let group, group.nextLocked, let next = group.nextDate, !from.isSameDay(as: next) {
                notice = "Saved. It applies from \(relativeDay(from))."
            } else {
                notice = nil
            }
        } then: {
            // After the refresh, the local alarm knows exactly when it rings next.
            guard on else { return }
            let local = (try? store.context.fetch(FetchDescriptor<AlarmItem>()))?.first { $0.groupID == groupID }
            store.announceAlarmSet(ringsAt: local?.nextFireDate())
        }
    }

    private func run(_ work: @escaping () async throws -> Void, then done: (() -> Void)? = nil) {
        Task {
            working = true
            defer { working = false }
            do {
                try await work()
                error = nil
                await sync.refresh(store: store)
                done?()
                await loadBoard()
            } catch {
                self.error = Backend.describe(error)
            }
        }
    }

    private func relativeDay(_ date: Date) -> String {
        if date.isSameDay(as: .now) { return "today" }
        if date.isSameDay(as: Date().adding(days: 1)) { return "tomorrow" }
        if date.isSameDay(as: Date().adding(days: -1)) { return "yesterday" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

struct MemberBoardRow: View {
    @Environment(Backend.self) private var backend
    var member: GroupMemberDay
    var isMe: Bool
    var onReportPhoto: () -> Void
    var onBlock: () -> Void

    @State private var photoURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(member.avatarEmoji)
                    .font(.system(size: 20))
                    .frame(width: 38, height: 38)
                    .background(Palette.sky.fill, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(isMe ? "You" : member.name).font(Face.rowStrong)
                    Text(status).font(Face.caption).foregroundStyle(statusColor)
                }
                Spacer()
                Text(badge).font(.system(size: 20)).accessibilityHidden(true)
                if !isMe {
                    Menu {
                        if member.photoPath != nil {
                            Button("Report photo", action: onReportPhoto)
                        }
                        Button("Block @\(member.username)", role: .destructive, action: onBlock)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 36, height: Metric.minTarget)
                    }
                    .accessibilityLabel("Options for \(member.name)")
                }
            }
            if let photoURL {
                AsyncImage(url: photoURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Ink.line)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
                .accessibilityLabel("\(member.name)'s wake photo")
            }
        }
        .task(id: member.photoPath) {
            guard let path = member.photoPath else { photoURL = nil; return }
            photoURL = try? await backend.wakePhotoURL(path)
        }
    }

    private var status: String {
        if !member.participating { return member.memberStatus == "invited" ? "Invited" : "Not in for this one" }
        if member.emergencyStopped { return "Emergency stop" }
        if member.checkedIn, let woke = member.wokeAt {
            let snoozed = (member.snoozes ?? 0) > 0 ? " • snoozed \(member.snoozes ?? 0)×" : ""
            return (member.onTime ? "Up at " : "Late, up at ") + woke.shortTime + snoozed
        }
        return "Not up yet"
    }

    private var statusColor: Color {
        if member.checkedIn && member.onTime { return Palette.mint.ink }
        if member.checkedIn { return Palette.blush.ink }
        return Ink.muted
    }

    private var badge: String {
        if !member.participating { return "💤" }
        if member.emergencyStopped { return "🆘" }
        if member.checkedIn { return member.onTime ? "✅" : "🐢" }
        return "⏳"
    }
}

struct InviteFriendsSheet: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    var groupID: UUID
    var existing: [UUID]

    @State private var friends: [Connection] = []
    @State private var sent: Set<UUID> = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if friends.isEmpty {
                    Text("Everyone you're friends with is already here, or you haven't added anyone yet.")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }
                ForEach(friends) { friend in
                    HStack {
                        Text(friend.avatarEmoji)
                        VStack(alignment: .leading) {
                            Text(friend.name)
                            Text("@\(friend.username)").font(Face.caption).foregroundStyle(Ink.muted)
                        }
                        Spacer()
                        if sent.contains(friend.userID) {
                            Text("Invited").font(Face.caption).foregroundStyle(Ink.muted)
                        } else {
                            Button("Invite") {
                                Task {
                                    do {
                                        try await backend.invite(friend.userID, to: groupID)
                                        sent.insert(friend.userID)
                                    } catch {
                                        self.error = Backend.describe(error)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(Palette.blush.ink)
                }
            }
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                let all = (try? await backend.connections()) ?? []
                friends = all.filter { $0.isFriend && !existing.contains($0.userID) }
            }
        }
    }
}

struct ReportPhotoSheet: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    var groupID: UUID
    var day: Date
    var member: GroupMemberDay

    @State private var details = ""
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Label("Thanks. A person reviews every report within 24 hours.", systemImage: "checkmark.shield")
                } else {
                    Section("What's wrong with this photo? (optional)") {
                        TextField("Details", text: $details, axis: .vertical).lineLimit(2...5)
                    }
                    if let error { Text(error).foregroundStyle(Palette.blush.ink) }
                }
            }
            .navigationTitle("Report photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(sent ? "Done" : "Cancel") { dismiss() } }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            Task {
                                do {
                                    try await backend.reportWakePhoto(group: groupID, day: day,
                                                                      member: member.userID,
                                                                      details: String(details.prefix(1000)))
                                    sent = true
                                } catch {
                                    self.error = Backend.describe(error)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
