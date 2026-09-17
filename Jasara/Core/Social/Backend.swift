import Foundation
import Observation
import Supabase

// MARK: - Rows

struct RemoteProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var username: String
    var displayName: String
    var avatarEmoji: String
    var level: Int

    enum CodingKeys: String, CodingKey {
        case id, username, level
        case displayName = "display_name"
        case avatarEmoji = "avatar_emoji"
    }

    var name: String { displayName.isEmpty ? username : displayName }
}

/// A friend, or a request in either direction. One row from `my_connections()`.
struct Connection: Codable, Identifiable, Hashable {
    var friendshipID: UUID
    var userID: UUID
    var username: String
    var displayName: String
    var avatarEmoji: String
    var level: Int
    var status: String
    /// True when the other person sent the request.
    var incoming: Bool

    enum CodingKeys: String, CodingKey {
        case username, level, status, incoming
        case friendshipID = "friendship_id"
        case userID = "user_id"
        case displayName = "display_name"
        case avatarEmoji = "avatar_emoji"
    }

    var id: UUID { friendshipID }
    var isFriend: Bool { status == "accepted" }
    var name: String { displayName.isEmpty ? username : displayName }
}

struct BlockedUser: Codable, Identifiable, Hashable {
    var userID: UUID
    var username: String

    enum CodingKeys: String, CodingKey {
        case username
        case userID = "user_id"
    }

    var id: UUID { userID }
}

/// Mirrors the check constraint on `reports.reason`.
enum ReportReason: String, CaseIterable, Identifiable {
    case spam, harassment, impersonation, other
    case inappropriateUsername = "inappropriate_username"
    case inappropriatePhoto = "inappropriate_photo"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .spam: return "Spam"
        case .harassment: return "Harassment or bullying"
        case .inappropriateUsername: return "Inappropriate username"
        case .inappropriatePhoto: return "Inappropriate photo"
        case .impersonation: return "Pretending to be someone"
        case .other: return "Something else"
        }
    }
}

enum SignUpOutcome {
    case signedIn
    /// Supabase has "Confirm email" on: the account exists but has no session yet.
    case confirmEmail
}

struct BackendError: LocalizedError {
    var message: String
    var errorDescription: String? { message }

    static let notConfigured = BackendError(message: "Accounts aren't set up in this build yet.")
    static let notSignedIn = BackendError(message: "Sign in first.")
}

// MARK: - Client

/// Accounts and friends, backed by Supabase. Everything solo keeps working
/// without it: when `Config/Secrets.xcconfig` is missing, `isConfigured` is false
/// and the social screens say so instead of failing.
@Observable
@MainActor
final class Backend {
    static let shared = Backend()

    private let client: SupabaseClient?
    private(set) var userID: UUID?
    private(set) var email: String?
    /// Nil while signed in means the account still needs a username.
    private(set) var me: RemoteProfile?
    private(set) var isLoadingProfile = false

    var isConfigured: Bool { client != nil }
    var isSignedIn: Bool { userID != nil }

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let host = (info["SupabaseHost"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (info["SupabaseAnonKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !key.isEmpty,
              !host.contains("your-project"), !key.contains("your-anon-key"),
              let url = URL(string: "https://\(host)") else {
            client = nil
            return
        }
        let client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true)))
        self.client = client
        // Read the stored session right away, so the first screen already knows
        // who's signed in instead of waiting for the listener's first event.
        userID = client.auth.currentUser?.id
        email = client.auth.currentUser?.email
        Task { await listenForSessionChanges() }
    }

    /// The SDK keeps the session in the keychain, so people stay signed in offline
    /// and across launches. This just mirrors it into observable state.
    private func listenForSessionChanges() async {
        guard let client else { return }
        for await (_, session) in client.auth.authStateChanges {
            // An expired access token still means signed in: the SDK refreshes it
            // once there's a connection. Offline users must not look signed out.
            let user = session?.user
            let changed = user?.id != userID
            userID = user?.id
            email = user?.email
            if user == nil {
                me = nil
            } else if changed || me == nil {
                try? await loadMe()
            }
        }
    }

    private func require() throws -> SupabaseClient {
        guard let client else { throw BackendError.notConfigured }
        return client
    }

    /// For extensions in other files, which can't see the private helpers.
    func signedInClient() throws -> SupabaseClient {
        try requireUser().0
    }

    private func requireUser() throws -> (SupabaseClient, UUID) {
        let client = try require()
        guard let userID else { throw BackendError.notSignedIn }
        return (client, userID)
    }

    /// Server errors carry readable messages (the SQL raises them in plain
    /// English), so pass those through and keep the rest generic.
    static func describe(_ error: Error) -> String {
        if let error = error as? BackendError { return error.message }
        if let error = error as? PostgrestError { return error.message }
        if let error = error as? AuthError { return error.message }
        if (error as? URLError) != nil { return "Couldn't reach the server. Check your connection." }
        return error.localizedDescription
    }

    // MARK: Accounts

    /// Nil when the username is free; otherwise the reason it isn't. Works signed out.
    func usernameProblem(_ name: String) async -> String? {
        if let local = UsernameRules.problem(with: name) { return local }
        guard let client else { return nil }
        do {
            return try await client.rpc("username_available", params: ["name": name])
                .execute().value as String?
        } catch {
            return nil     // offline: don't block typing; sign-up re-checks on the server
        }
    }

    func signUp(email: String, password: String, username: String) async throws -> SignUpOutcome {
        let client = try require()
        let response = try await client.auth.signUp(email: email,
                                                    password: password,
                                                    data: ["username": .string(username)])
        guard let session = response.session else { return .confirmEmail }
        userID = session.user.id
        self.email = session.user.email
        try await loadMe()
        return .signedIn
    }

    func signIn(email: String, password: String) async throws {
        let client = try require()
        let session = try await client.auth.signIn(email: email, password: password)
        userID = session.user.id
        self.email = session.user.email
        try await loadMe()
    }

    func signOut() async {
        try? await client?.auth.signOut()
        userID = nil
        email = nil
        me = nil
    }

    /// Server data first; the caller wipes this phone afterwards.
    func deleteAccount() async throws {
        let (client, _) = try requireUser()
        try await client.rpc("delete_account").execute()
        try? await client.auth.signOut(scope: .local)
        userID = nil
        email = nil
        me = nil
    }

    func loadMe() async throws {
        let (client, userID) = try requireUser()
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        let rows: [RemoteProfile] = try await client.from("profiles")
            .select("id, username, display_name, avatar_emoji, level")
            .eq("id", value: userID)
            .execute().value
        me = rows.first
    }

    /// For accounts that exist but never got a username.
    func claimUsername(_ name: String) async throws {
        let client = try require()
        me = try await client.rpc("create_profile", params: ["name": name]).execute().value
    }

    /// Keeps what friends see in step with this phone. Level only ever moves up here.
    func syncProfile(displayName: String, avatarEmoji: String, level: Int) async {
        guard let client, let userID, let current = me else { return }
        let patch = ProfilePatch(displayName: String(displayName.prefix(40)),
                                 avatarEmoji: avatarEmoji,
                                 level: max(current.level, min(max(level, 1), Leveling.maxLevel)))
        guard patch.displayName != current.displayName
                || patch.avatarEmoji != current.avatarEmoji
                || patch.level != current.level else { return }
        do {
            try await client.from("profiles").update(patch).eq("id", value: userID).execute()
            me?.displayName = patch.displayName
            me?.avatarEmoji = patch.avatarEmoji
            me?.level = patch.level
        } catch {
            // Offline or rejected: the next visit to Friends tries again.
        }
    }

    private struct ProfilePatch: Encodable {
        var displayName: String
        var avatarEmoji: String
        var level: Int
        enum CodingKeys: String, CodingKey {
            case level
            case displayName = "display_name"
            case avatarEmoji = "avatar_emoji"
        }
    }

    // MARK: Friends

    /// Exact username only, never a partial search, so nobody can trawl for people.
    func findProfile(username: String) async throws -> RemoteProfile? {
        let (client, _) = try requireUser()
        let rows: [RemoteProfile] = try await client
            .rpc("find_profile", params: ["name": username.trimmingCharacters(in: .whitespaces)])
            .execute().value
        return rows.first
    }

    func connections() async throws -> [Connection] {
        let (client, _) = try requireUser()
        return try await client.rpc("my_connections").execute().value
    }

    func blockedUsers() async throws -> [BlockedUser] {
        let (client, _) = try requireUser()
        return try await client.rpc("my_blocks").execute().value
    }

    func sendRequest(to user: UUID) async throws {
        let (client, _) = try requireUser()
        try await client.rpc("send_friend_request", params: ["target": user]).execute()
    }

    func respond(to request: UUID, accept: Bool) async throws {
        struct Params: Encodable { var request: UUID; var accept: Bool }
        let (client, _) = try requireUser()
        try await client.rpc("respond_to_friend_request",
                             params: Params(request: request, accept: accept)).execute()
    }

    /// Unfriend, or cancel a request you sent.
    func removeConnection(with user: UUID) async throws {
        let (client, _) = try requireUser()
        try await client.rpc("remove_friendship", params: ["other": user]).execute()
    }

    func block(_ user: UUID) async throws {
        let (client, _) = try requireUser()
        try await client.rpc("block_user", params: ["target": user]).execute()
    }

    func unblock(_ user: UUID) async throws {
        let (client, _) = try requireUser()
        try await client.rpc("unblock_user", params: ["target": user]).execute()
    }

    func report(_ user: UUID, reason: ReportReason, details: String) async throws {
        struct Params: Encodable { var target: UUID; var reason: String; var details: String }
        let (client, _) = try requireUser()
        try await client.rpc("report_user",
                             params: Params(target: user, reason: reason.rawValue, details: details))
            .execute()
    }
}
