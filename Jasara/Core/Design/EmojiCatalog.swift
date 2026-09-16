import Foundation

/// iOS has no system emoji picker to present, so the list is bundled and shown in
/// a custom grid. That also means the picker works with no connection.
enum EmojiCatalog {
    struct Group: Identifiable {
        let id = UUID()
        let name: String
        let emoji: [String]
    }

    static let groups: [Group] = [
        Group(name: "Everyday", emoji: ["✅","⭐️","🔥","⏰","⏳","📌","🗂️","📝","📅","🔔","💡","🎯","🧩","🔑","🧹","🧺","🛒","🍽️","🧾","💳","📦","🧴","🪥","🛏️","🚿","💊","🧘","🫧"]),
        Group(name: "Work & study", emoji: ["💻","📊","📈","🧮","📚","✏️","🖊️","📖","🎓","🔬","🧪","🗣️","📣","💼","🗓️","📎","🖇️","🧠","🗃️","📐","⌨️","🖥️","🧑‍💻","📓"]),
        Group(name: "Health & move", emoji: ["🏋️","🏃","🚴","🧗","🏊","⚽️","🏀","🎾","🥊","🤸","🚶","🧎","💪","🥗","🍎","🥤","💧","😴","🩺","🦷","🫀","🧊"]),
        Group(name: "Home & life", emoji: ["🏠","🪴","🐕","🐈","🧑‍🍳","🍳","🍜","🥘","☕️","🫖","🧺","🔧","🔨","🪛","🚗","⛽️","✈️","🧳","🎁","💐","🕯️","🪟"]),
        Group(name: "Faith & calm", emoji: ["🕌","📿","🤲","🌙","☪️","🧿","🕊️","🌅","🌄","🌿","🍃","🪷","🫶","☁️","✨","🌊"]),
        Group(name: "Fun", emoji: ["🎮","🎧","🎬","🎸","🎨","📷","🍿","🎲","🃏","🛹","🏕️","🎤","🪩","🥳","🧋","🍩","🌮","🏖️"]),
        Group(name: "Faces", emoji: ["😀","🙂","😌","😎","🤓","🥱","😤","😭","🤪","🫠","🫡","🤝","👀","🙌","👍","🤞","🫰","🧑","👥"])
    ]

    static var all: [String] { groups.flatMap(\.emoji) }

    /// Keyword → emoji, so "gym" suggests 🏋️ while the user is still typing.
    private static let keywords: [(words: [String], emoji: String, color: Palette)] = [
        (["gym", "workout", "lift", "weights", "train"], "🏋️", .blush),
        (["run", "jog", "cardio", "5k"], "🏃", .blush),
        (["walk", "steps", "stroll"], "🚶", .mint),
        (["pray", "prayer", "salah", "namaz", "masjid", "fajr", "dhuhr", "asr", "maghrib", "isha"], "🕌", .mint),
        (["quran", "read", "book", "reading", "chapter"], "📚", .sand),
        (["study", "revise", "exam", "homework", "assignment", "essay"], "✏️", .sky),
        (["code", "build", "ship", "bug", "deploy", "app"], "💻", .lilac),
        (["email", "inbox", "reply", "message"], "📧", .sky),
        (["meeting", "call", "standup", "sync", "1:1"], "🗓️", .lilac),
        (["clean", "tidy", "dishes", "laundry", "vacuum"], "🧹", .mint),
        (["shop", "groceries", "buy", "store"], "🛒", .butter),
        (["cook", "dinner", "lunch", "meal", "breakfast"], "🍳", .butter),
        (["water", "drink", "hydrate"], "💧", .sky),
        (["sleep", "bed", "nap", "rest"], "😴", .lilac),
        (["money", "budget", "bill", "pay", "rent", "invoice"], "💳", .sand),
        (["doctor", "dentist", "appointment", "medicine", "pills"], "💊", .blush),
        (["drive", "car", "commute", "petrol", "gas"], "🚗", .sand),
        (["flight", "airport", "travel", "trip", "pack"], "✈️", .sky),
        (["call mum", "family", "friend", "birthday"], "🎁", .blush),
        (["focus", "deep work", "pomodoro", "timer"], "⏳", .lilac)
    ]

    /// Best-effort suggestion. Falls back to a neutral tick so it never blocks saving.
    static func suggestion(for title: String) -> (emoji: String, color: Palette)? {
        let text = title.lowercased()
        guard !text.isEmpty else { return nil }
        for entry in keywords where entry.words.contains(where: { text.contains($0) }) {
            return (entry.emoji, entry.color)
        }
        return nil
    }

    static func search(_ query: String) -> [String] {
        let text = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return all }
        var matches = keywords
            .filter { $0.words.contains { $0.contains(text) } }
            .map(\.emoji)
        // Let people paste an emoji straight into the field.
        if query.unicodeScalars.contains(where: { $0.properties.isEmoji && $0.value > 0x238C }) {
            matches.insert(query, at: 0)
        }
        return matches.isEmpty ? all : matches
    }
}
