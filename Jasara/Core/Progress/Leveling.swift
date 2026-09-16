import Foundation

/// Max level is 365, one for each day of the year, and each level costs a little
/// more than the one before. The curve and the cumulative table below match the
/// PRD exactly, so a level shown in the app is the level the spec promises.
enum Leveling {
    static let maxLevel = 365

    static func xpToNextLevel(_ level: Int) -> Int {
        guard level < maxLevel else { return 0 }
        let l = Double(level)
        return Int((75 + 1.5 * l + 0.06 * pow(l, 1.5)).rounded())
    }

    /// Total XP needed to *reach* a level, i.e. the sum of every cost below it.
    private static let cumulative: [Int] = {
        var totals = [0, 0]           // index 0 unused, level 1 starts at 0 XP
        var running = 0
        for level in 1..<maxLevel {
            running += xpToNextLevel(level)
            totals.append(running)
        }
        return totals
    }()

    static func totalXP(toReach level: Int) -> Int {
        cumulative[min(max(level, 1), maxLevel)]
    }

    static func level(forTotalXP xp: Int) -> Int {
        // Binary search the cumulative table.
        var low = 1, high = maxLevel
        while low < high {
            let mid = (low + high + 1) / 2
            if cumulative[mid] <= xp { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Progress through the current level, 0…1, and the raw numbers behind it.
    static func progress(forTotalXP xp: Int) -> (level: Int, into: Int, needed: Int, fraction: Double) {
        let level = self.level(forTotalXP: xp)
        guard level < maxLevel else { return (maxLevel, 0, 0, 1) }
        let floorXP = totalXP(toReach: level)
        let needed = xpToNextLevel(level)
        let into = xp - floorXP
        return (level, into, needed, needed == 0 ? 1 : Double(into) / Double(needed))
    }

    /// A cosmetic every 5 levels, a title every 50.
    static func title(for level: Int) -> String {
        switch level {
        case ..<50: return "Early riser"
        case ..<100: return "Day builder"
        case ..<150: return "Steady hand"
        case ..<200: return "Momentum"
        case ..<250: return "Unshakeable"
        case ..<300: return "Lighthouse"
        case ..<365: return "First light"
        default: return "Sunkeeper"
        }
    }
}
