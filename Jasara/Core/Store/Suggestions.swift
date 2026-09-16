import Foundation

/// Starter tasks shown under the list so a new, empty app still has something to
/// do. Tapping one adds it; the shuffle button swaps the set.
struct SuggestedTask: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var emoji: String
    var color: Palette
    var minutes: Int?
    var priority: Priority = .none
    /// The prayers suggestion opens setup instead of adding a plain task.
    var opensPrayerSetup: Bool = false

    static let prayers = SuggestedTask(title: "Daily prayers", emoji: "🕌", color: .mint,
                                       minutes: nil, opensPrayerSetup: true)

    static let pool: [SuggestedTask] = [
        SuggestedTask(title: "Make the bed", emoji: "🛏️", color: .sand, minutes: 5),
        SuggestedTask(title: "Drink a glass of water", emoji: "💧", color: .sky, minutes: nil),
        SuggestedTask(title: "Tidy your desk", emoji: "🧹", color: .mint, minutes: 10),
        SuggestedTask(title: "Read 10 pages", emoji: "📚", color: .sand, minutes: 15),
        SuggestedTask(title: "Stretch", emoji: "🧘", color: .lilac, minutes: 10),
        SuggestedTask(title: "Walk outside", emoji: "🚶", color: .mint, minutes: 20),
        SuggestedTask(title: "Plan tomorrow", emoji: "📅", color: .sky, minutes: 10, priority: .medium),
        SuggestedTask(title: "Inbox to zero", emoji: "📧", color: .sky, minutes: 25),
        SuggestedTask(title: "Gym session", emoji: "🏋️", color: .blush, minutes: 60, priority: .high),
        SuggestedTask(title: "Wash up", emoji: "🍽️", color: .butter, minutes: 15),
        SuggestedTask(title: "Call someone you miss", emoji: "📞", color: .blush, minutes: 15),
        SuggestedTask(title: "Deep work block", emoji: "💻", color: .lilac, minutes: 50, priority: .high),
        SuggestedTask(title: "Laundry", emoji: "🧺", color: .sand, minutes: 30),
        SuggestedTask(title: "Review your budget", emoji: "💳", color: .sand, minutes: 20)
    ]

    /// Always leads with prayers, then a rotating handful of the rest.
    static func sample(seed: Int, includePrayers: Bool) -> [SuggestedTask] {
        var picks: [SuggestedTask] = includePrayers ? [prayers] : []
        let count = includePrayers ? 3 : 4
        let start = abs(seed) % pool.count
        for offset in 0..<count {
            picks.append(pool[(start + offset * 3) % pool.count])
        }
        return picks
    }

    func makeTask() -> TaskItem {
        let task = TaskItem(title: title, emoji: emoji, color: color, priority: priority)
        task.durationMinutes = minutes
        return task
    }
}
