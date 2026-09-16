import Foundation

/// Every number the economy runs on, in one place. The anti-farming rules matter
/// as much as the rewards: XP has to be worth something or the streak is theatre.
enum XPRules {
    static let wakeOnTime = 20
    static let snoozePenalty = 5
    static let wakeFloor = 5
    /// Priority does not change task XP, so nobody marks everything High to farm.
    static let task = 5
    static let taskDailyCap = 50
    static let timerPerFiveMinutes = 1
    static let timerDailyCap = 30
    static let timerMinimumMinutes = 5
    static let prayer = 5
    static let groupBonus = 10
    /// A task created and ticked off inside this window earns nothing.
    static let minimumTaskAge: TimeInterval = 120

    static let milestones: [Int: Int] = [7: 50, 30: 200, 100: 500, 365: 1000]
    static let milestoneDays = [3, 7, 30, 100, 365]
    static let milestoneLabel = "3, 7, 30, 100, 365"

    /// Wake XP after snoozes, never below the floor. Rounds never add XP.
    static func wakeXP(snoozes: Int) -> Int {
        max(wakeFloor, wakeOnTime - snoozes * snoozePenalty)
    }

    static func timerXP(seconds: Int) -> Int {
        let minutes = seconds / 60
        guard minutes >= timerMinimumMinutes else { return 0 }
        return (minutes / 5) * timerPerFiveMinutes
    }
}
