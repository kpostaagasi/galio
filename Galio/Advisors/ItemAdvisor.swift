import Foundation

/// What the visible enemy team threatens, derived from their champions and the items shown on
/// the scoreboard (no hidden information).
struct EnemyThreat: Equatable {
    var adShare = 0.5
    var apShare = 0.5
    var healing = 0.0
    var crit = 0.0
    var attackSpeed = 0.0
    var shields = 0.0
    var cc = 0.0
    var tankiness = 0.0
    var burst = 0.0
    var armorStack = 0.0
    var mrStack = 0.0
    var count = 0

    init() {}

    init(champions: [ChampionInfo], items: [[ItemInfo]] = []) {
        count = champions.count
        guard count > 0 else { return }
        var ad = 0.0, ap = 0.0
        for (i, c) in champions.enumerated() {
            let inv = i < items.count ? items[i] : []
            var cAD = c.isMagic ? 0.15 : (c.damageType == "mixed" ? 0.5 : 1.0)
            var cAP = 1.0 - cAD
            let invAD = inv.reduce(0.0) { $0 + $1.stat("ad") + $1.stat("lethality") * 2 }
            let invAP = inv.reduce(0.0) { $0 + $1.stat("ap") }
            if invAD + invAP > 40 {
                cAD = 0.5 * cAD + 0.5 * invAD / (invAD + invAP)
                cAP = 1.0 - cAD
            }
            ad += cAD
            ap += cAP
            let a = c.attrs
            if c.archetype == "enchanter" { healing += 0.8; shields += 0.8 }
            if a.sustain >= 3 { healing += 0.7 }
            healing += inv.reduce(0.0) { $0 + ($1.has("lifesteal") || $1.has("omnivamp") || $1.has("allyheal") ? 0.5 : 0) }
            shields += inv.reduce(0.0) { $0 + ($1.has("allyshield") || $1.has("shield") ? 0.3 : 0) }
            crit += inv.reduce(0.0) { $0 + ($1.stat("crit") > 0 ? 0.6 : 0) }
            attackSpeed += inv.reduce(0.0) { $0 + ($1.stat("as") >= 20 ? 0.45 : 0) }
            if ["marksman", "onhit"].contains(c.archetype) { attackSpeed += 0.4; crit += c.archetype == "marksman" ? 0.4 : 0 }
            cc += Double(a.cc) / 3.0
            tankiness += Double(a.frontline) / 3.0
            armorStack += inv.reduce(0.0) { $0 + $1.stat("armor") } / 100.0
            mrStack += inv.reduce(0.0) { $0 + $1.stat("mr") } / 100.0
            if c.has(role: "assassin") || a.burst >= 3 { burst += 1 }
        }
        adShare = ad / Double(count)
        apShare = ap / Double(count)
        tankiness += (armorStack + mrStack) * 0.5
    }
}

struct ItemSuggestion: Identifiable, Equatable {
    let item: ItemInfo
    let score: Double
    let reasons: [Reason]
    /// Gold still needed after owned components; 0 = affordable now.
    let goldMissing: Int
    /// A component the player can buy right now on the way to this item.
    let componentNow: ItemInfo?
    var id: Int { item.id }
}

/// Re-ranks the next item options against the visible enemy team, with reasons and gold awareness.
enum ItemAdvisor {
    static func suggest(build: BuildData, owned: [Int], gold: Double, threat: EnemyThreat,
                        items: [Int: ItemInfo], map: Int, limit: Int = 4) -> [ItemSuggestion] {
        let ownedSet = Set(owned)
        let ownedLegendaries = owned.compactMap { items[$0] }.filter { $0.legendary }
        let hasBoots = owned.compactMap { items[$0] }.contains { $0.boots }

        var candidates: [(ItemInfo, Double, [Reason])] = []
        var seen = Set<Int>()
        func consider(_ id: Int, base: Double, reason: Reason?) {
            guard !ownedSet.contains(id), !seen.contains(id), let item = items[id], item.maps.contains(map) else { return }
            seen.insert(id)
            var score = base
            var reasons: [Reason] = reason.map { [$0] } ?? []
            for (w, r) in situationalValue(item, threat: threat) {
                score += w
                reasons.append(r)
            }
            candidates.append((item, score, reasons))
        }

        for (i, id) in build.items.core.enumerated() {
            let base = max(0.25, 0.62 - Double(i) * 0.06 - Double(ownedLegendaries.count) * 0.0)
            consider(id, base: base, reason: i < 3 ? Reason("item.core", Loc.tr("Temel eşya dizisinin parçası")) : Reason("item.later", Loc.tr("Geç oyun için plandaki eşya")))
        }
        for s in build.items.situational {
            consider(s.id, base: 0.22, reason: nil)
        }
        if !hasBoots && !owned.isEmpty {
            var bootIds = build.items.boots
            if threat.adShare >= 0.6 || threat.attackSpeed >= 1.2 { bootIds.insert(3047, at: 0) }
            if threat.apShare >= 0.6 || threat.cc >= 3.2 { bootIds.insert(3111, at: 0) }
            for (i, id) in bootIds.enumerated() {
                consider(id, base: 0.5 - Double(i) * 0.05, reason: Reason("item.boots", Loc.tr("Henüz botun yok")))
            }
        }

        let ranked = candidates
            .map { entry -> ItemSuggestion in
                let (item, score, reasons) = entry
                let (missing, component) = goldStatus(for: item, owned: owned, gold: gold, items: items)
                return ItemSuggestion(item: item, score: score, reasons: reasons.isEmpty ? [Reason("item.plan", Loc.tr("Plana uygun"))] : reasons,
                                      goldMissing: missing, componentNow: component)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.item.gold < $1.item.gold }
        return Array(ranked.prefix(limit))
    }

    /// Bonus for an item given the enemy threat, based on its stats and derived flags.
    static func situationalValue(_ item: ItemInfo, threat: EnemyThreat) -> [(Double, Reason)] {
        guard threat.count > 0 else { return [] }
        var out: [(Double, Reason)] = []
        if item.has("antiheal") && threat.healing >= 1.2 {
            out.append((0.35, Reason("vs.heal", Loc.tr("Rakipte güçlü iyileşme var: Ağır Yara uygular"))))
        }
        if item.stat("armor") >= 30 && threat.adShare >= 0.6 {
            out.append((0.22 + (threat.adShare - 0.6), Reason("vs.ad", Loc.tr("Rakip hasarı çoğunlukla fiziksel: zırh"))))
        }
        if item.stat("mr") >= 30 && threat.apShare >= 0.55 {
            out.append((0.22 + (threat.apShare - 0.55), Reason("vs.ap", Loc.tr("Rakip hasarı çoğunlukla büyü: büyü direnci"))))
        }
        if item.has("anticrit") && threat.crit >= 1.0 {
            out.append((0.30, Reason("vs.crit", Loc.tr("Rakipte kritik vuruş eşyaları var"))))
        }
        if item.has("antias") && threat.attackSpeed >= 1.0 {
            out.append((0.25, Reason("vs.as", Loc.tr("Rakipte saldırı hızına dayalı hasar var"))))
        }
        if (item.has("qss") || item.has("tenacity")) && threat.cc >= 3.0 {
            out.append((0.20, Reason("vs.cc", Loc.tr("Rakipte yoğun kitle kontrolü var"))))
        }
        if (item.has("stasis") || item.has("spellshield") || item.has("magicshield")) && threat.burst >= 2 {
            out.append((0.20, Reason("vs.burst", Loc.tr("Ani hasar veren rakiplere karşı hayatta kalma"))))
        }
        if item.has("antishield") && threat.shields >= 1.2 {
            out.append((0.25, Reason("vs.shield", Loc.tr("Rakip kalkanlarını zayıflatır"))))
        }
        if item.has("armorpen") && (threat.armorStack >= 1.0 || threat.tankiness >= 2.2) {
            out.append((0.22, Reason("vs.armor", Loc.tr("Rakip zırh topluyor: zırh delme"))))
        }
        if item.has("mpen") && (threat.mrStack >= 0.8 || threat.tankiness >= 2.2) {
            out.append((0.22, Reason("vs.mr", Loc.tr("Rakip büyü direnci topluyor: büyü delme"))))
        }
        return out
    }

    /// Remaining cost after owned components (one level deep) and a component affordable now.
    static func goldStatus(for item: ItemInfo, owned: [Int], gold: Double, items: [Int: ItemInfo]) -> (Int, ItemInfo?) {
        var pool = owned
        var credit = 0
        for comp in item.from {
            if let idx = pool.firstIndex(of: comp), let ci = items[comp] {
                credit += ci.gold
                pool.remove(at: idx)
            }
        }
        let remaining = max(0, item.gold - credit)
        let missing = max(0, remaining - Int(gold))
        var component: ItemInfo?
        if missing > 0 {
            component = item.from
                .filter { !owned.contains($0) }
                .compactMap { items[$0] }
                .filter { Double($0.gold) <= gold }
                .max { $0.gold < $1.gold }
        }
        return (missing, component)
    }
}
