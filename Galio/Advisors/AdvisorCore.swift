import Foundation

/// One human-readable justification behind a recommendation. `code` is stable for tests.
struct Reason: Hashable {
    let code: String
    let text: String
    var positive = true

    init(_ code: String, _ text: String, positive: Bool = true) {
        self.code = code
        self.text = text
        self.positive = positive
    }
}

/// S–D tiers. Galio never shows win rates for augments or Arena items (Riot policy).
enum Tier: String, CaseIterable, Comparable, Codable {
    case S, A, B, C, D

    private var rank: Int {
        switch self {
        case .S: return 0
        case .A: return 1
        case .B: return 2
        case .C: return 3
        case .D: return 4
        }
    }

    static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rank > rhs.rank }

    /// Maps a 0…1 score to a tier.
    static func from(score: Double) -> Tier {
        switch score {
        case 0.8...: return .S
        case 0.62..<0.8: return .A
        case 0.45..<0.62: return .B
        case 0.28..<0.45: return .C
        default: return .D
        }
    }
}

/// Aggregated view of a team composition (allies or visible enemies).
struct TeamProfile: Equatable {
    var count = 0
    var magic = 0.0
    var physical = 0.0
    var frontline = 0
    var engage = 0
    var peel = 0
    var waveclear = 0
    var poke = 0
    var cc = 0
    var mobility = 0
    var sustain = 0
    var burst = 0
    var ranged = 0
    var melee = 0
    var scaling = 0
    var tanks = 0
    var assassins = 0
    var marksmen = 0
    var healers = 0
    var shielders = 0

    init() {}

    init(_ champions: [ChampionInfo]) {
        for c in champions { add(c) }
    }

    mutating func add(_ c: ChampionInfo) {
        count += 1
        switch c.damageType {
        case "magic": magic += 1
        case "mixed": magic += 0.5; physical += 0.5
        default: physical += 1
        }
        let a = c.attrs
        frontline += a.frontline
        engage += a.engage
        peel += a.peel
        waveclear += a.waveclear
        poke += a.poke
        cc += a.cc
        mobility += a.mobility
        sustain += a.sustain
        burst += a.burst
        scaling += a.scaling
        if c.isRanged { ranged += 1 } else { melee += 1 }
        if c.has(role: "tank") { tanks += 1 }
        if c.has(role: "assassin") { assassins += 1 }
        if c.has(role: "marksman") { marksmen += 1 }
        if c.archetype == "enchanter" || a.sustain >= 3 { healers += 1 }
        if c.archetype == "enchanter" { shielders += 1 }
    }

    var magicShare: Double { count == 0 ? 0 : magic / Double(count) }
    var physicalShare: Double { count == 0 ? 0 : physical / Double(count) }
    var avgFrontline: Double { count == 0 ? 0 : Double(frontline) / Double(count) }
}
