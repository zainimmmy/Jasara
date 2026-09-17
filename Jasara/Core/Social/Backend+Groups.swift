import Foundation
import Supabase

/// Postgres `date` values arrive as "yyyy-MM-dd". They're calendar days, not
/// instants, so they're read in the phone's own calendar.
enum DayString {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ string: String?) -> Date? { string.flatMap(formatter.date(from:)) }
    static func string(_ date: Date) -> String { formatter.string(from: date) }
}

/// One row of `my_alarm_groups()`: a group you're in or invited to.
struct GroupAlarm: Codable, Identifiable, Hashable {
    var id: UUID
    var label: String
    var hour: Int
    var minute: Int
    var weekdaysMask: Int
    var onceOn: String?
    var cutoffMinutes: Int
    var creatorID: UUID
    var creatorUsername: String
    var myStatus: String
    var invitedByUsername: String?
    var isOn: Bool
    var challenge: String
    var tier: Int
    var rounds: Int
    var memberCount: Int
    var nextOccurrence: String?
    var nextLocked: Bool
    var countsNext: Bool

    enum CodingKeys: String, CodingKey {
        case label, hour, minute, challenge, tier, rounds
        case id = "group_id"
        case weekdaysMask = "weekdays_mask"
        case onceOn = "once_on"
        case cutoffMinutes = "cutoff_minutes"
        case creatorID = "creator_id"
        case creatorUsername = "creator_username"
        case myStatus = "my_status"
        case invitedByUsername = "invited_by_username"
        case isOn = "is_on"
        case memberCount = "member_count"
        case nextOccurrence = "next_occurrence"
        case nextLocked = "next_locked"
        case countsNext = "counts_next"
    }

    var isJoined: Bool { myStatus == "joined" }
    var onceDate: Date? { DayString.date(onceOn) }
    var nextDate: Date? { DayString.date(nextOccurrence) }
    var challengeKind: Challenge { Challenge(rawValue: challenge) ?? .math }
    var tierKind: Tier { Tier(rawValue: tier) ?? .normal }

    var timeText: String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        return date.shortTime
    }

    var scheduleText: String {
        if let once = onceDate { return once.formatted(.dateTime.weekday(.abbreviated).day().month()) }
        return Weekdays.describe(weekdaysMask)
    }

    var cutoffText: String {
        Date.today(atMinutes: cutoffMinutes).shortTime
    }

    /// The moment the next occurrence rings, in this phone's time zone.
    var nextRingDate: Date? {
        nextDate.flatMap { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: $0) }
    }
}

/// One person on a group's board for a day.
struct GroupMemberDay: Codable, Identifiable, Hashable {
    var userID: UUID
    var username: String
    var displayName: String
    var avatarEmoji: String
    var memberStatus: String
    var participating: Bool
    var checkedIn: Bool
    var wokeAt: Date?
    var onTime: Bool
    var snoozes: Int?
    var emergencyStopped: Bool
    var photoPath: String?

    enum CodingKeys: String, CodingKey {
        case username, participating
        case userID = "user_id"
        case displayName = "display_name"
        case avatarEmoji = "avatar_emoji"
        case memberStatus = "member_status"
        case checkedIn = "checked_in"
        case wokeAt = "woke_at"
        case onTime = "on_time"
        case snoozes
        case emergencyStopped = "emergency_stopped"
        case photoPath = "photo_path"
    }

    var id: UUID { userID }
    var name: String { displayName.isEmpty ? username : displayName }
}

/// What the group's creator edits. The same shape creates a group.
struct GroupAlarmDraft: Equatable {
    var label = "Wake up"
    var hour = 7
    var minute = 0
    var weekdaysMask = Weekdays.weekdayMask
    var onceOn: Date?
    var cutoffMinutes = 21 * 60
}

/// Each member's own challenge for a group.
struct MemberChallenge: Equatable {
    var challenge: Challenge = .math
    var tier: Tier = .normal
    var rounds = 3
}

extension Backend {
    private var zone: String { TimeZone.current.identifier }

    func myAlarmGroups() async throws -> [GroupAlarm] {
        let client = try signedInClient()
        return try await client.rpc("my_alarm_groups").execute().value
    }

    func createGroup(_ draft: GroupAlarmDraft, mine: MemberChallenge, invite friends: [UUID]) async throws -> UUID {
        struct Params: Encodable {
            var label: String; var hour: Int; var minute: Int
            var weekdays_mask: Int; var once_on: String?; var cutoff_minutes: Int
            var time_zone: String; var challenge: String; var tier: Int; var rounds: Int
        }
        let client = try signedInClient()
        let params = Params(label: draft.label, hour: draft.hour, minute: draft.minute,
                            weekdays_mask: draft.onceOn == nil ? draft.weekdaysMask : 0,
                            once_on: draft.onceOn.map(DayString.string),
                            cutoff_minutes: draft.cutoffMinutes, time_zone: zone,
                            challenge: mine.challenge.rawValue, tier: mine.tier.rawValue, rounds: mine.rounds)
        let id: UUID = try await client.rpc("create_alarm_group", params: params).execute().value
        for friend in friends {
            try await invite(friend, to: id)
        }
        return id
    }

    func updateGroup(_ id: UUID, _ draft: GroupAlarmDraft) async throws {
        struct Params: Encodable {
            var target: UUID; var label: String; var hour: Int; var minute: Int
            var weekdays_mask: Int; var once_on: String?; var cutoff_minutes: Int
        }
        let client = try signedInClient()
        try await client.rpc("update_alarm_group", params: Params(
            target: id, label: draft.label, hour: draft.hour, minute: draft.minute,
            weekdays_mask: draft.onceOn == nil ? draft.weekdaysMask : 0,
            once_on: draft.onceOn.map(DayString.string),
            cutoff_minutes: draft.cutoffMinutes)).execute()
    }

    func deleteGroup(_ id: UUID) async throws {
        let client = try signedInClient()
        try await client.rpc("delete_alarm_group", params: ["target": id]).execute()
    }

    func invite(_ friend: UUID, to group: UUID) async throws {
        struct Params: Encodable { var target: UUID; var friend: UUID }
        let client = try signedInClient()
        try await client.rpc("invite_to_alarm_group", params: Params(target: group, friend: friend)).execute()
    }

    func respondToInvite(_ group: UUID, accept: Bool, mine: MemberChallenge) async throws {
        struct Params: Encodable {
            var target: UUID; var accept: Bool; var time_zone: String
            var challenge: String; var tier: Int; var rounds: Int
        }
        let client = try signedInClient()
        try await client.rpc("respond_to_group_invite", params: Params(
            target: group, accept: accept, time_zone: zone,
            challenge: mine.challenge.rawValue, tier: mine.tier.rawValue, rounds: mine.rounds)).execute()
    }

    func leaveGroup(_ id: UUID) async throws {
        let client = try signedInClient()
        try await client.rpc("leave_alarm_group", params: ["target": id]).execute()
    }

    /// Returns the first day the change applies to.
    @discardableResult
    func setGroupAlarm(_ id: UUID, on: Bool) async throws -> Date? {
        struct Params: Encodable { var target: UUID; var turn_on: Bool; var time_zone: String }
        let client = try signedInClient()
        let day: String? = try await client.rpc("set_group_alarm_on",
                                                params: Params(target: id, turn_on: on, time_zone: zone))
            .execute().value
        return DayString.date(day)
    }

    func updateMyChallenge(_ id: UUID, _ mine: MemberChallenge) async throws {
        struct Params: Encodable {
            var target: UUID; var challenge: String; var tier: Int; var rounds: Int; var time_zone: String
        }
        let client = try signedInClient()
        try await client.rpc("update_my_group_settings", params: Params(
            target: id, challenge: mine.challenge.rawValue, tier: mine.tier.rawValue,
            rounds: mine.rounds, time_zone: zone)).execute()
    }

    func checkIn(_ checkIn: PendingGroupCheckIn) async throws -> Bool {
        struct Params: Encodable {
            var target: UUID; var occurrence_on: String; var woke_at: Date
            var snoozes: Int; var emergency_stopped: Bool
        }
        let client = try signedInClient()
        return try await client.rpc("check_in_group_alarm", params: Params(
            target: checkIn.groupID, occurrence_on: checkIn.occurrenceOn, woke_at: checkIn.wokeAt,
            snoozes: checkIn.snoozes, emergency_stopped: checkIn.emergencyStopped)).execute().value
    }

    func groupDay(_ id: UUID, day: Date) async throws -> [GroupMemberDay] {
        struct Params: Encodable { var target: UUID; var day: String }
        let client = try signedInClient()
        return try await client.rpc("alarm_group_day",
                                    params: Params(target: id, day: DayString.string(day))).execute().value
    }

    func groupStreak(_ id: UUID) async throws -> Int {
        let client = try signedInClient()
        return try await client.rpc("alarm_group_streak", params: ["target": id]).execute().value
    }

    // MARK: Wake photos

    static let wakePhotoBucket = "wake-photos"

    func uploadWakePhoto(_ jpeg: Data, group: UUID, occurrenceOn: String) async throws {
        struct Params: Encodable { var target: UUID; var occurrence_on: String }
        let client = try signedInClient()
        guard let me = userID else { throw BackendError.notSignedIn }
        let path = "\(group.uuidString.lowercased())/\(occurrenceOn)/\(me.uuidString.lowercased()).jpg"
        try await client.storage.from(Self.wakePhotoBucket)
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
        _ = try await client.rpc("attach_wake_photo",
                                 params: Params(target: group, occurrence_on: occurrenceOn)).execute()
    }

    /// Short-lived link: photos are only visible to the group, for 24 hours.
    func wakePhotoURL(_ path: String) async throws -> URL {
        let client = try signedInClient()
        return try await client.storage.from(Self.wakePhotoBucket).createSignedURL(path: path, expiresIn: 600)
    }

    func reportWakePhoto(group: UUID, day: Date, member: UUID, details: String) async throws {
        struct Params: Encodable { var target: UUID; var occurrence_on: String; var member: UUID; var details: String }
        let client = try signedInClient()
        try await client.rpc("report_wake_photo", params: Params(
            target: group, occurrence_on: DayString.string(day), member: member, details: details)).execute()
    }
}
