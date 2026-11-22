import Foundation

/// Galio's per-patch data set (`data/<patch>/all.json`, produced by `tools/build_data.py`).
struct GalioDataSet: Decodable {
    let schema: Int
    let patch: String
    let generatedAt: String?
    let champions: [ChampionInfo]
    let details: [String: ChampionDetail]
    let items: [ItemInfo]
    let runes: RuneData
    let summoners: [SummonerSpellInfo]
    let augments: [String: [AugmentInfo]]
}

struct ChampionAttrs: Decodable, Hashable {
    let frontline: Int
    let engage: Int
    let peel: Int
    let waveclear: Int
    let poke: Int
    let scaling: Int
    let sustain: Int
    let burst: Int
    let cc: Int
    let mobility: Int
    let damage: Int
    let durability: Int
    let utility: Int
}

struct ChampionInfo: Decodable, Identifiable, Hashable {
    let id: String
    let key: Int
    let name: String
    let nameTR: String
    let title: String
    let titleTR: String
    let tags: [String]
    let roles: [String]
    let positions: [String]
    let damageType: String
    let attackType: String
    let range: Int
    let difficulty: Int
    let archetype: String
    let attrs: ChampionAttrs
    let spellNames: [String: String]

    var displayName: String { Loc.pick(tr: nameTR, en: name) }
    var displayTitle: String { Loc.pick(tr: titleTR, en: title) }
    var isRanged: Bool { attackType == "ranged" || range > 300 }
    var isMagic: Bool { damageType == "magic" }
    var isPhysical: Bool { damageType == "physical" }
    var positionList: [Position] { positions.compactMap { Position(rawValue: $0) } }
    func has(role: String) -> Bool { roles.contains(role) }
}

struct ChampionDetail: Decodable {
    let id: String
    let key: Int
    let patch: String
    let source: String
    let skillOrder: SkillOrderData
    let builds: [String: BuildData]

    /// Build for a position (falls back to the champion's first listed build).
    func build(for key: String?) -> BuildData? {
        if let key, let b = builds[key] { return b }
        return builds.first { $0.key != "ARAM" }?.value ?? builds.values.first
    }
}

struct SkillOrderData: Decodable, Equatable {
    let max: [String]
    let first: [String]
    let ultLevels: [Int]
}

struct BuildData: Decodable {
    let archetype: String
    let itemClass: String
    let runes: [RunePageData]
    let spells: [[Int]]
    let items: ItemBuildData
}

struct RunePageData: Decodable, Hashable {
    let primaryStyleId: Int
    let subStyleId: Int
    let perkIds: [Int]
    let source: String
    let tag: String
}

struct ItemBuildData: Decodable {
    let starter: [Int]
    let boots: [Int]
    let core: [Int]
    let situational: [SituationalItem]
}

struct SituationalItem: Decodable, Hashable {
    let id: Int
    let when: [String]
}

struct ItemInfo: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let nameTR: String
    let gold: Int
    let tags: [String]
    let stats: [String: Double]
    let flags: [String]
    let maps: [Int]
    let from: [Int]
    let legendary: Bool
    let boots: Bool
    let starter: Bool

    var displayName: String { Loc.pick(tr: nameTR, en: name) }
    func stat(_ key: String) -> Double { stats[key] ?? 0 }
    func has(_ flag: String) -> Bool { flags.contains(flag) }
}

struct RuneData: Decodable {
    let styles: [RuneStyle]
    let shards: [RuneShard]
    let shardRows: [[Int]]
}

struct RuneStyle: Decodable, Identifiable {
    let id: Int
    let key: String
    let name: String
    let nameTR: String
    let icon: String
    let slots: [[RuneInfo]]

    var displayName: String { Loc.pick(tr: nameTR, en: name) }
}

struct RuneInfo: Decodable, Identifiable, Hashable {
    let id: Int
    let key: String
    let name: String
    let nameTR: String
    let icon: String

    var displayName: String { Loc.pick(tr: nameTR, en: name) }
}

struct RuneShard: Decodable, Identifiable {
    let id: Int
    let name: String
    let nameTR: String
    let icon: String?

    var displayName: String { Loc.pick(tr: nameTR, en: name) }
}

struct SummonerSpellInfo: Decodable, Identifiable, Hashable {
    let id: Int
    let ddId: String
    let name: String
    let nameTR: String
    let modes: [String]
    let image: String

    var displayName: String { Loc.pick(tr: nameTR, en: name) }
}

struct AugmentInfo: Decodable, Identifiable, Hashable {
    let id: Int
    let apiName: String
    let name: String
    let nameTR: String
    let rarity: String
    let tags: [String]
    let affinity: [String]
    let desc: String
    let icon: String

    var displayName: String { Loc.pick(tr: nameTR, en: name) }
}
