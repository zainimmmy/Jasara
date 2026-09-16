import Foundation

/// The tier table from the spec, in code. Tier sets how hard one round is; the
/// number of rounds is chosen separately and never changes the XP, so nobody can
/// grind 100 easy rounds for a reward.
enum ChallengeCatalog {

    // MARK: - Math

    struct MathProblem: Equatable {
        var question: String
        var answer: Int
    }

    static func mathProblem(_ tier: Tier) -> MathProblem {
        func r(_ range: ClosedRange<Int>) -> Int { Int.random(in: range) }
        switch tier {
        case .veryEasy:
            let a = r(1...9), b = r(1...9)
            return MathProblem(question: "\(a) + \(b)", answer: a + b)
        case .easy:
            let a = r(10...49), b = r(10...49)
            return MathProblem(question: "\(a) + \(b)", answer: a + b)
        case .normal:
            let a = r(20...99), b = r(20...99)
            return MathProblem(question: "\(a) + \(b)", answer: a + b)
        case .hard:
            let a = r(11...19), b = r(3...9)
            return MathProblem(question: "\(a) × \(b)", answer: a * b)
        case .veteran:
            let a = r(11...19), b = r(4...9), c = r(20...60)
            return MathProblem(question: "\(a) × \(b) + \(c)", answer: a * b + c)
        case .general:
            let a = r(15...35), b = r(12...25), c = r(40...99)
            return MathProblem(question: "\(a) × \(b) + \(c)", answer: a * b + c)
        case .hell:
            let a = r(17...49), b = r(23...79), c = r(100...400)
            return MathProblem(question: "\(a) × \(b) + \(c)", answer: a * b + c)
        }
    }

    /// Sample shown in the alarm editor so nobody agrees to something blind.
    static func mathPreview(_ tier: Tier) -> String {
        switch tier {
        case .veryEasy: return "3 + 4"
        case .easy: return "18 + 25"
        case .normal: return "47 + 86"
        case .hard: return "13 × 8"
        case .veteran: return "14 × 9 + 37"
        case .general: return "26 × 18 + 94"
        case .hell: return "23 × 47 + 156"
        }
    }

    // MARK: - Shake

    /// Peak acceleration in g needed for a shake to count. Starting values, to be
    /// tuned on real devices before release.
    static func shakeThreshold(_ tier: Tier) -> Double {
        [1.3, 1.7, 2.1, 2.5, 2.8, 3.2, 3.6][tier.rawValue]
    }

    /// Shakes any closer together than this are one wobble, not two.
    static let shakeCooldown: TimeInterval = 0.25

    // MARK: - Colour tiles

    struct TileSpec {
        var gridSize: Int
        var litTiles: Int
        var showSeconds: Double
    }

    static func tileSpec(_ tier: Tier) -> TileSpec {
        switch tier {
        case .veryEasy: return TileSpec(gridSize: 3, litTiles: 3, showSeconds: 3.0)
        case .easy:     return TileSpec(gridSize: 4, litTiles: 4, showSeconds: 2.75)
        case .normal:   return TileSpec(gridSize: 5, litTiles: 6, showSeconds: 2.5)
        case .hard:     return TileSpec(gridSize: 6, litTiles: 8, showSeconds: 2.25)
        case .veteran:  return TileSpec(gridSize: 7, litTiles: 10, showSeconds: 2.0)
        case .general:  return TileSpec(gridSize: 8, litTiles: 12, showSeconds: 1.75)
        case .hell:     return TileSpec(gridSize: 10, litTiles: 15, showSeconds: 1.5)
        }
    }

    // MARK: - Typing

    static func typingPreview(_ tier: Tier) -> String {
        PhraseFactory.phrase(tier: tier, wordCount: min(tier.rawValue + 3, 8))
    }
}

/// Phrases are built when the alarm is saved and refreshed nightly, so a groggy
/// 6am never waits on generation. On iPhones with the on-device Foundation Models
/// framework this is where that call goes; everywhere else the bundled word bank
/// below does the job, which also keeps the whole thing working offline.
enum PhraseFactory {
    private static let common = ["morning", "coffee", "window", "light", "quiet", "kettle", "street", "garden", "pillow", "blanket", "shower", "kitchen", "clock", "shoes", "bicycle", "river", "bread", "orange", "candle", "letter"]
    private static let uncommon = ["lantern", "harbour", "meridian", "thicket", "cobblestone", "alcove", "marmalade", "sextant", "filament", "quarry", "tundra", "verandah", "zephyr", "aperture", "bramble", "cirrus"]
    private static let connectors = ["and", "the", "with", "under", "beside", "after", "before", "over"]
    private static let hellCharacters = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// One phrase at the right difficulty for the tier.
    static func phrase(tier: Tier, wordCount: Int) -> String {
        let count = max(2, min(wordCount, 50))
        switch tier {
        case .veryEasy:
            return (0..<max(2, min(count, 3))).map { _ in common.randomElement()! }.joined(separator: " ")
        case .easy:
            return sentence(from: common, count: count, capitalised: true, punctuation: false)
        case .normal:
            return sentence(from: common, count: count, capitalised: true, punctuation: true)
        case .hard:
            let base = sentence(from: common, count: count, capitalised: true, punctuation: true)
            return base + " \(Int.random(in: 10...99))"
        case .veteran:
            return sentence(from: uncommon, count: count, capitalised: true, punctuation: true)
        case .general:
            let words = (0..<count).map { index -> String in
                let word = (index.isMultiple(of: 2) ? uncommon : common).randomElement()!
                return index.isMultiple(of: 3) ? word.uppercased() : word.capitalized
            }
            return words.joined(separator: " ") + " #\(Int.random(in: 100...999))!"
        case .hell:
            // Generated in code on purpose: no model should be asked for noise.
            return (0..<max(3, count / 2)).map { _ in
                String((0..<6).map { _ in hellCharacters.randomElement()! })
            }.joined(separator: " ")
        }
    }

    private static func sentence(from bank: [String], count: Int, capitalised: Bool, punctuation: Bool) -> String {
        var words: [String] = []
        for index in 0..<count {
            words.append(index.isMultiple(of: 3) && index > 0
                         ? connectors.randomElement()!
                         : bank.randomElement()!)
        }
        var text = words.joined(separator: " ")
        if capitalised { text = text.prefix(1).uppercased() + text.dropFirst() }
        if punctuation { text += Bool.random() ? ", then out the door." : "." }
        return text
    }

    /// Filtered and length-checked before it is ever stored on an alarm.
    static func prepare(for alarm: AlarmItem, count: Int = 8) -> [String] {
        guard alarm.challenge == .typing else { return [] }
        var phrases: [String] = []
        var attempts = 0
        while phrases.count < count && attempts < count * 4 {
            attempts += 1
            let candidate = phrase(tier: alarm.tier, wordCount: alarm.typingWordCount)
            guard !ProfanityFilter.isBlocked(candidate) else { continue }
            phrases.append(candidate)
        }
        return phrases
    }
}
