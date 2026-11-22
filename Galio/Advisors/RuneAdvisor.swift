import Foundation

struct RunePageSuggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let primaryStyleId: Int
    let subStyleId: Int
    let perkIds: [Int]
    let reasons: [Reason]
    let tag: String

    var keystoneId: Int { perkIds.first ?? 0 }

    /// Name used when importing into the client (LCU limits names to 25 characters).
    func importName(champion: ChampionInfo) -> String {
        String("Galio: \(champion.name)".prefix(25))
    }
}

/// Builds 2–3 rune pages from Riot's in-client recommendations (via CommunityDragon) plus a
/// Galio defensive variant, adjusts stat shards to the visible enemy team and explains each.
enum RuneAdvisor {
    static let shardTenacity = 5013
    static let shardHealth = 5011
    static let shardScalingHealth = 5001
    static let shardMoveSpeed = 5010

    static func suggest(build: BuildData, champion: ChampionInfo, enemies: [ChampionInfo], mode: ModeInfo) -> [RunePageSuggestion] {
        guard mode.usesRunes else { return [] }
        let enemy = TeamProfile(enemies)
        let heavyCC = enemies.count >= 3 && enemy.cc >= enemies.count * 2 + 2
        let burstThreat = enemy.assassins >= 2 || (enemies.count >= 3 && enemy.burst >= enemies.count * 2 + 1)
        let squishy = champion.attrs.durability <= 1

        var pages: [(Double, RunePageSuggestion)] = []
        for (i, page) in build.runes.enumerated() {
            var perks = page.perkIds
            var reasons: [Reason] = []
            var rank = Double(i)
            switch page.tag {
            case "standard":
                reasons.append(Reason("rune.riot", Loc.tr("Riot'un bu rol için istemcide önerdiği sayfa")))
            case "defensive":
                reasons.append(Reason("rune.defensive", Loc.tr("Kararlılık ikincil ağacı: koridor evresinde daha dayanıklı")))
                if burstThreat && squishy {
                    rank -= 1.5
                    reasons.append(Reason("rune.vsBurst", Loc.tr("Rakipte yüksek ani hasar var; hayatta kalma öncelikli")))
                }
            default:
                reasons.append(Reason("rune.alt", Loc.tr("Riot'un alternatif sayfası; farklı bir oyun planı")))
            }
            if perks.count == 9 {
                if heavyCC && perks[8] != shardTenacity {
                    perks[8] = shardTenacity
                    reasons.append(Reason("rune.tenacity", Loc.tr("Rakipte yoğun kitle kontrolü: savunma parçası Direnç olarak değiştirildi")))
                } else if enemies.count >= 3 && enemy.poke >= 4 && perks[8] == shardScalingHealth {
                    perks[8] = shardHealth
                    reasons.append(Reason("rune.vsPoke", Loc.tr("Uzaktan taciz eden rakiplere karşı sabit can parçası")))
                }
            }
            let title: String
            switch page.tag {
            case "standard": title = Loc.tr("Standart")
            case "defensive": title = Loc.tr("Dayanıklı")
            default: title = Loc.tr("Alternatif")
            }
            pages.append((rank, RunePageSuggestion(id: "\(champion.id)-\(i)-\(page.tag)", title: title,
                                                    primaryStyleId: page.primaryStyleId, subStyleId: page.subStyleId,
                                                    perkIds: perks, reasons: reasons, tag: page.tag)))
        }
        return pages.sorted { $0.0 < $1.0 }.prefix(3).map(\.1)
    }

    /// Validates a page against the rune tree structure (4 primary rows, 2 secondary rows, 3 shards).
    static func isValid(_ page: RunePageSuggestion, runes: RuneData) -> Bool {
        guard page.perkIds.count == 9, page.primaryStyleId != page.subStyleId,
              let primary = runes.styles.first(where: { $0.id == page.primaryStyleId }),
              let secondary = runes.styles.first(where: { $0.id == page.subStyleId })
        else { return false }
        for (row, perk) in page.perkIds.prefix(4).enumerated() {
            guard row < primary.slots.count, primary.slots[row].contains(where: { $0.id == perk }) else { return false }
        }
        let secRows = page.perkIds[4..<6].compactMap { perk in secondary.slots.firstIndex { $0.contains { $0.id == perk } } }
        guard secRows.count == 2, Set(secRows).count == 2, !secRows.contains(0) else { return false }
        for (i, shard) in page.perkIds[6..<9].enumerated() {
            guard i < runes.shardRows.count, runes.shardRows[i].contains(shard) else { return false }
        }
        return true
    }
}

struct SpellSuggestion: Identifiable, Equatable {
    let spells: [Int]
    let reasons: [Reason]
    var id: String { spells.map(String.init).joined(separator: "-") }
}

/// Summoner spell options: Riot's recommendation first, then role/enemy-informed alternatives.
enum SummonerSpellAdvisor {
    static let flash = 4, ignite = 14, teleport = 12, smite = 11, heal = 7, exhaust = 3
    static let barrier = 21, cleanse = 1, ghost = 6, mark = 32, clarity = 13

    static func suggest(build: BuildData?, champion: ChampionInfo, position: Position?, enemies: [ChampionInfo], mode: ModeInfo) -> [SpellSuggestion] {
        if mode.family == .arena || mode.family == .swarm { return [] }
        let enemy = TeamProfile(enemies)
        var out: [SpellSuggestion] = []
        func add(_ spells: [Int], _ reasons: [Reason]) {
            let key = Set(spells)
            guard spells.count == 2, !out.contains(where: { Set($0.spells) == key }) else { return }
            out.append(SpellSuggestion(spells: spells, reasons: reasons))
        }
        if let riot = build?.spells.first, riot.count == 2 {
            add(riot, [Reason("spell.riot", Loc.tr("Riot'un bu şampiyon için önerdiği büyüler"))])
        }
        let aram = mode.family == .aram || mode.family == .aramMayhem
        if aram {
            add([flash, mark], [Reason("spell.mark", Loc.tr("Kartopu ile savaşa hızlı giriş"))])
            if champion.attrs.mobility <= 1 { add([flash, ghost], [Reason("spell.ghost", Loc.tr("Hareketi kısıtlı şampiyona kaçış/kovalama"))]) }
            if enemy.assassins >= 2 { add([flash, exhaust], [Reason("spell.exhaust", Loc.tr("Rakip suikastçıların hasarını keser"))]) }
            add([flash, heal], [Reason("spell.heal", Loc.tr("Takım dövüşlerinde güvenli seçim"))])
            return Array(out.prefix(3))
        }
        switch position {
        case .jungle?:
            add([flash, smite], [Reason("spell.smite", Loc.tr("Orman için Çarp zorunlu"))])
            if champion.attrs.engage >= 2 && champion.attrs.mobility <= 2 {
                add([ghost, smite], [Reason("spell.ghost", Loc.tr("Hayalet ile uzun mesafeli girişler"))])
            }
        case .top?:
            add([flash, teleport], [Reason("spell.tp", Loc.tr("Işınlan ile harita baskısı ve güvenli koridor"))])
            add([flash, ignite], [Reason("spell.ignite", Loc.tr("Agresif koridor ve öldürme gücü"))])
            if champion.archetype == "juggernaut" { add([ghost, teleport], [Reason("spell.ghost", Loc.tr("Hayalet, menzilli rakiplere yetişmeyi sağlar"))]) }
        case .middle?:
            add([flash, ignite], [Reason("spell.ignite", Loc.tr("Koridorda öldürme baskısı"))])
            add([flash, teleport], [Reason("spell.tp", Loc.tr("Daha güvenli koridor ve yan koridorlara destek"))])
            if enemy.assassins >= 1 { add([flash, barrier], [Reason("spell.barrier", Loc.tr("Suikastçının ani hasarına karşı Bariyer"))]) }
        case .bottom?:
            add([flash, heal], [Reason("spell.heal", Loc.tr("Nişancı için standart"))])
            if enemy.assassins >= 1 || enemy.burst >= 8 { add([flash, barrier], [Reason("spell.barrier", Loc.tr("Ani hasara karşı Bariyer"))]) }
            if enemy.cc >= 11 { add([flash, cleanse], [Reason("spell.cleanse", Loc.tr("Rakipte yoğun kitle kontrolü: Arındır"))]) }
        case .utility?:
            add([flash, ignite], [Reason("spell.ignite", Loc.tr("Erken öldürme ve iyileşme azaltma"))])
            if enemy.assassins >= 1 || enemy.mobility >= 9 { add([flash, exhaust], [Reason("spell.exhaust", Loc.tr("Dalış yapan rakipleri yavaşlatır, hasarını keser"))]) }
            if champion.archetype == "enchanter" { add([flash, heal], [Reason("spell.heal", Loc.tr("Takım arkadaşını kurtaran iyileştirme"))]) }
        case nil:
            add([flash, ignite], [Reason("spell.ignite", Loc.tr("Genel amaçlı saldırgan seçim"))])
            add([flash, teleport], [Reason("spell.tp", Loc.tr("Harita hareketliliği"))])
        }
        if enemy.healers >= 1 && !out.prefix(2).contains(where: { $0.spells.contains(ignite) }) && position != .jungle {
            add([flash, ignite], [Reason("spell.antiheal", Loc.tr("Rakipte iyileştirme var; Tutuştur iyileşmeyi azaltır"))])
        }
        return Array(out.prefix(3))
    }

    /// Keeps Flash on the key the player already uses for it (D or F).
    static func orderForPlayer(_ spells: [Int], currentSpell1: Int, currentSpell2: Int) -> [Int] {
        guard spells.count == 2 else { return spells }
        if currentSpell2 == flash, spells[0] == flash { return [spells[1], spells[0]] }
        if currentSpell1 == flash, spells[1] == flash { return [spells[1], spells[0]] }
        return spells
    }
}
