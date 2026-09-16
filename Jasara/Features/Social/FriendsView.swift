import SwiftUI

/// Add people by exact username, answer requests, and manage friends. Block and
/// report are one tap from every person, and neither is ever behind Pro.
struct FriendsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Backend.self) private var backend

    @State private var connections: [Connection] = []
    @State private var blocked: [BlockedUser] = []
    @State private var loaded = false
    @State private var error: String?

    @State private var query = ""
    @State private var searching = false
    @State private var found: RemoteProfile?
    @State private var searchMessage: String?

    @State private var reporting: ReportTarget?
    @State private var confirmBlock: ReportTarget?

    private var incoming: [Connection] { connections.filter { !$0.isFriend && $0.incoming } }
    private var outgoing: [Connection] { connections.filter { !$0.isFriend && !$0.incoming } }
    private var friends: [Connection] { connections.filter(\.isFriend) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if backend.isSignedIn, let me = backend.me {
                    signedIn(me)
                } else {
                    Card {
                        AccountView(mode: .create) { Task { await refresh() } }
                    }
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, 40)
        }
        .background(Ink.background)
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task(id: backend.me?.id) { await refresh() }
        .sheet(item: $reporting) { target in
            ReportSheet(target: target)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Block \(confirmBlock?.username ?? "")?",
                            isPresented: Binding(get: { confirmBlock != nil },
                                                 set: { if !$0 { confirmBlock = nil } }),
                            titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                if let target = confirmBlock { act { try await backend.block(target.userID) } }
            }
        } message: {
            Text("They won't be able to find you, add you, or see you in groups. They aren't told.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func signedIn(_ me: RemoteProfile) -> some View {
        Card {
            HStack(spacing: 12) {
                Text(me.avatarEmoji)
                    .font(.system(size: 26))
                    .frame(width: 50, height: 50)
                    .background(Palette.sky.fill, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(me.username)").font(Face.rowStrong)
                    Text("Friends add you by this exact username.")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }
                Spacer()
                ShareLink(item: "Add me on Jasara: @\(me.username)") {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: Metric.minTarget, height: Metric.minTarget)
                }
                .accessibilityLabel("Share your username")
            }
        }

        addFriend

        if let error {
            Text(error).font(Face.caption).foregroundStyle(Palette.blush.ink)
        }

        if !incoming.isEmpty {
            section("Requests", count: incoming.count, palette: .butter) {
                ForEach(incoming) { request in
                    personRow(request) {
                        Button("Accept") { act { try await backend.respond(to: request.friendshipID, accept: true) } }
                            .buttonStyle(.borderedProminent).tint(Palette.mint.ink)
                        Button("Decline") { act { try await backend.respond(to: request.friendshipID, accept: false) } }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }

        section("Friends", count: friends.count, palette: .mint) {
            if friends.isEmpty && loaded {
                EmptyHint(emoji: "👋", text: "No friends yet. Add someone by their username.")
            }
            ForEach(friends) { friend in
                personRow(friend) {
                    Menu {
                        Button("Remove friend", role: .destructive) {
                            act { try await backend.removeConnection(with: friend.userID) }
                        }
                        Button("Block") { confirmBlock = ReportTarget(friend) }
                        Button("Report") { reporting = ReportTarget(friend) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: Metric.minTarget, height: Metric.minTarget)
                    }
                    .accessibilityLabel("Options for \(friend.name)")
                }
            }
        }

        if !outgoing.isEmpty {
            section("Sent", count: outgoing.count, palette: .sky) {
                ForEach(outgoing) { request in
                    personRow(request) {
                        Button("Cancel") { act { try await backend.removeConnection(with: request.userID) } }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }

        if !blocked.isEmpty {
            section("Blocked", count: blocked.count, palette: .sand) {
                ForEach(blocked) { user in
                    HStack {
                        Text("@\(user.username)").font(Face.row)
                        Spacer()
                        Button("Unblock") { act { try await backend.unblock(user.userID) } }
                            .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
                }
            }
        }
    }

    private var addFriend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a friend").font(Face.sectionTitle)
            HStack(spacing: 8) {
                TextField("exact username", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .font(Face.row)
                    .padding(12)
                    .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
                Button {
                    Task { await search() }
                } label: {
                    Image(systemName: searching ? "hourglass" : "magnifyingglass")
                        .frame(width: Metric.minTarget, height: Metric.minTarget)
                        .background(Palette.lilac.fill, in: Circle())
                        .foregroundStyle(Palette.lilac.ink)
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).count < 3 || searching)
                .accessibilityLabel("Find")
            }
            if let found {
                let existing = connections.first { $0.userID == found.id }
                HStack(spacing: 12) {
                    Text(found.avatarEmoji)
                        .font(.system(size: 22))
                        .frame(width: 42, height: 42)
                        .background(Palette.sky.fill, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(found.name).font(Face.rowStrong)
                        Text("@\(found.username) • Lv \(found.level)").font(Face.caption).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    if let existing {
                        Text(existing.isFriend ? "Friends" : (existing.incoming ? "Asked you" : "Requested"))
                            .font(Face.caption).foregroundStyle(Ink.muted)
                    } else {
                        Button("Add") {
                            act {
                                try await backend.sendRequest(to: found.id)
                                searchMessage = "Request sent to @\(found.username)."
                            }
                        }
                        .buttonStyle(.borderedProminent).tint(Palette.lilac.ink)
                    }
                }
                .padding(12)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
                .contextMenu {
                    Button("Block") { confirmBlock = ReportTarget(found) }
                    Button("Report") { reporting = ReportTarget(found) }
                }
            }
            if let searchMessage {
                Text(searchMessage).font(Face.caption).foregroundStyle(Ink.muted)
            }
        }
    }

    private func section<Content: View>(_ title: String, count: Int, palette: Palette,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderRow(title: title, symbol: nil, palette: palette, count: count, onAdd: nil)
            content()
        }
    }

    private func personRow<Actions: View>(_ person: Connection,
                                          @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 12) {
            Text(person.avatarEmoji)
                .font(.system(size: 22))
                .frame(width: 42, height: 42)
                .background(Palette.sky.fill, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name).font(Face.rowStrong)
                Text("@\(person.username) • Lv \(person.level)").font(Face.caption).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 4)
            actions()
        }
        .padding(12)
        .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous)
            .strokeBorder(Ink.line, lineWidth: 1))
    }

    // MARK: - Actions

    private func refresh() async {
        guard backend.isSignedIn, backend.me != nil else { return }
        await backend.syncProfile(displayName: store.profile.displayName,
                                  avatarEmoji: store.profile.avatarEmoji,
                                  level: store.profile.level)
        do {
            async let people = backend.connections()
            async let blocks = backend.blockedUsers()
            connections = try await people
            blocked = try await blocks
            error = nil
        } catch {
            self.error = Backend.describe(error)
        }
        loaded = true
    }

    private func search() async {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3 else { return }
        searching = true
        defer { searching = false }
        searchMessage = nil
        found = nil
        do {
            found = try await backend.findProfile(username: name)
            if found == nil { searchMessage = "Nobody with that exact username." }
        } catch {
            searchMessage = Backend.describe(error)
        }
    }

    /// Run a change, then reload so every section reflects the server.
    private func act(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                error = nil
            } catch {
                self.error = Backend.describe(error)
            }
            await refresh()
        }
    }
}

struct ReportTarget: Identifiable, Hashable {
    var userID: UUID
    var username: String
    var id: UUID { userID }

    init(_ connection: Connection) {
        userID = connection.userID
        username = connection.username
    }

    init(_ profile: RemoteProfile) {
        userID = profile.id
        username = profile.username
    }
}

struct ReportSheet: View {
    @Environment(Backend.self) private var backend
    @Environment(\.dismiss) private var dismiss
    var target: ReportTarget

    @State private var reason = ReportReason.harassment
    @State private var details = ""
    @State private var working = false
    @State private var error: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("Thanks. A person reviews every report within 24 hours.",
                              systemImage: "checkmark.shield")
                    }
                } else {
                    Section("What's wrong?") {
                        Picker("Reason", selection: $reason) {
                            ForEach(ReportReason.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    Section("Anything else (optional)") {
                        TextField("Details", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(Palette.blush.ink) }
                    }
                }
            }
            .navigationTitle("Report @\(target.username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            Task {
                                working = true
                                defer { working = false }
                                do {
                                    try await backend.report(target.userID, reason: reason,
                                                             details: String(details.prefix(1000)))
                                    sent = true
                                } catch {
                                    self.error = Backend.describe(error)
                                }
                            }
                        }
                        .disabled(working)
                    }
                }
            }
        }
    }
}
