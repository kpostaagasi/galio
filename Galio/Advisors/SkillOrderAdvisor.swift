import Foundation

/// Turns a max order (e.g. Q > E > W) into a level-by-level plan and tells the player which
/// ability the plan levels next. Purely informational: Galio never levels abilities itself.
struct SkillPlan: Equatable {
    /// Max priority of the basic abilities, e.g. ["Q", "E", "W"].
    let maxOrder: [String]
    /// Ability taken at each champion level 1…18.
    let sequence: [String]
    let ultLevels: [Int]

    var firstThree: [String] { Array(sequence.prefix(3)) }

    /// Ranks of each ability after reaching `level` when following the plan.
    func ranks(atLevel level: Int) -> [String: Int] {
        var r: [String: Int] = ["Q": 0, "W": 0, "E": 0, "R": 0]
        for key in sequence.prefix(max(0, min(level, sequence.count))) { r[key, default: 0] += 1 }
        return r
    }
}

enum SkillOrderAdvisor {
    static let maxBasicRank = 5
    static let maxUltRank = 3

    static func plan(for data: SkillOrderData) -> SkillPlan {
        plan(maxOrder: data.max, first: data.first, ultLevels: data.ultLevels)
    }

    static func plan(maxOrder: [String], first: [String], ultLevels: [Int] = [6, 11, 16]) -> SkillPlan {
        let order = normalized(maxOrder)
        let firstThree = normalized(first.isEmpty ? order : first)
        var ranks: [String: Int] = ["Q": 0, "W": 0, "E": 0, "R": 0]
        var seq: [String] = []
        let ultCap = ultLevels.count
        for level in 1...18 {
            var pick: String?
            if ultLevels.contains(level), ranks["R", default: 0] < ultCap {
                pick = "R"
            } else if level <= 3 {
                // Unlock each basic ability once in the given opening order.
                pick = firstThree.first { ranks[$0, default: 0] == 0 && canLevel($0, ranks: ranks, level: level) }
            }
            if pick == nil {
                pick = order.first { canLevel($0, ranks: ranks, level: level) }
            }
            let chosen = pick ?? order[0]
            ranks[chosen, default: 0] += 1
            seq.append(chosen)
        }
        return SkillPlan(maxOrder: order, sequence: seq, ultLevels: ultLevels)
    }

    /// A basic ability can reach rank n at champion level 2n-1 (rank 1 at 1, 2 at 3, 3 at 5…).
    static func canLevel(_ key: String, ranks: [String: Int], level: Int) -> Bool {
        let next = ranks[key, default: 0] + 1
        if key == "R" { return next <= maxUltRank }
        return next <= maxBasicRank && level >= 2 * next - 1
    }

    /// Which ability the plan wants next, given the live ranks at the current level.
    /// Returns nil when no skill point is unspent according to the plan.
    static func nextSkill(plan: SkillPlan, level: Int, current: [String: Int]) -> String? {
        let spent = current.values.reduce(0, +)
        guard spent < level else { return nil }
        let target = plan.ranks(atLevel: level)
        // Prefer the plan's own order for the missing points (ult first when available).
        for key in ["R"] + plan.maxOrder where current[key, default: 0] < target[key, default: 0] {
            return key
        }
        // The player deviated from the plan: suggest the highest-priority ability that can still be levelled.
        if plan.ultLevels.contains(where: { $0 <= level }), current["R", default: 0] < plan.ultLevels.filter({ $0 <= level }).count {
            return "R"
        }
        return plan.maxOrder.first { canLevel($0, ranks: current, level: level) }
    }

    private static func normalized(_ keys: [String]) -> [String] {
        var out: [String] = []
        for k in keys.map({ $0.uppercased() }) where ["Q", "W", "E"].contains(k) && !out.contains(k) { out.append(k) }
        for k in ["Q", "W", "E"] where !out.contains(k) { out.append(k) }
        return out
    }
}
