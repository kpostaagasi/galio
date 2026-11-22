import Foundation

struct ChampionSuggestion: Identifiable, Equatable {
    let champion: ChampionInfo
    let score: Double
    let reasons: [Reason]
    var id: String { champion.id }
}

/// Inputs for champion suggestions (everything here is visible to the player in champ select).
struct ChampSelectContext {
    var mode: ModeInfo
    var position: Position?
    var allies: [ChampionInfo]
    var enemies: [ChampionInfo]
    var unavailable: Set<Int> = []
    /// Champions the player can pick (owned/free). Empty = unknown, allow all.
    var pickable: Set<Int> = []
    /// ARAM bench + the player's current champion: suggestions are limited to these.
    var swapPool: [ChampionInfo] = []
    /// The player's own mastery points per champion key (own data only).
    var mastery: [Int: Int] = [:]
}

/// Rule engine that ranks champions by what the team composition needs. Always returns several
/// options with reasons (never a single "pick this").
enum ChampionAdvisor {
    static func suggest(_ ctx: ChampSelectContext, from all: [ChampionInfo], limit: Int = 5) -> [ChampionSuggestion] {
        let candidates = candidatePool(ctx, all: all)
        let allyProfile = TeamProfile(ctx.allies)
        let enemyProfile = TeamProfile(ctx.enemies)
        let scored = candidates.map { c -> ChampionSuggestion in
            let (score, reasons) = evaluate(c, ctx: ctx, allies: allyProfile, enemies: enemyProfile)
            return ChampionSuggestion(champion: c, score: score, reasons: reasons)
        }
        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.champion.name < $1.champion.name }
            .prefix(limit)
            .map { $0 }
    }

    static func candidatePool(_ ctx: ChampSelectContext, all: [ChampionInfo]) -> [ChampionInfo] {
        if !ctx.swapPool.isEmpty { return ctx.swapPool }
        var pool = all.filter { !ctx.unavailable.contains($0.key) }
        if !ctx.pickable.isEmpty { pool = pool.filter { ctx.pickable.contains($0.key) } }
        if let pos = ctx.position, ctx.mode.usesPositions {
            let inRole = pool.filter { $0.positions.contains(pos.rawValue) }
            if inRole.count >= 3 { pool = inRole }
        }
        return pool
    }

    static func evaluate(_ c: ChampionInfo, ctx: ChampSelectContext, allies: TeamProfile, enemies: TeamProfile) -> (Double, [Reason]) {
        var score = 0.30
        var reasons: [(Double, Reason)] = []
        let a = c.attrs
        func add(_ weight: Double, _ reason: Reason) {
            score += weight
            reasons.append((weight, reason))
        }

        // Role fit.
        if let pos = ctx.position, ctx.mode.usesPositions {
            if c.positions.first == pos.rawValue {
                add(0.15, Reason("role.main", Loc.tr("%@ için ana rol seçeneklerinden", pos.title)))
            } else if c.positions.contains(pos.rawValue) {
                add(0.06, Reason("role.flex", Loc.tr("%@ rolünde de oynanıyor", pos.title)))
            }
        }

        // Damage balance (allies only: the player's own pick completes it).
        if allies.count >= 2 {
            if allies.physicalShare >= 0.7 && c.isMagic {
                add(0.25, Reason("dmg.needAP", Loc.tr("Takım çoğunlukla fiziksel hasar veriyor; büyü hasarı dengeyi sağlar")))
            } else if allies.magicShare >= 0.7 && c.isPhysical {
                add(0.25, Reason("dmg.needAD", Loc.tr("Takım çoğunlukla büyü hasarı veriyor; fiziksel hasar dengeyi sağlar")))
            } else if allies.physicalShare >= 0.7 && c.isPhysical {
                add(-0.12, Reason("dmg.tooMuchAD", Loc.tr("Takımda zaten çok fiziksel hasar var"), positive: false))
            } else if allies.magicShare >= 0.7 && c.isMagic {
                add(-0.12, Reason("dmg.tooMuchAP", Loc.tr("Takımda zaten çok büyü hasarı var"), positive: false))
            }
        }

        // Frontline.
        if allies.count >= 2 && allies.tanks == 0 && allies.avgFrontline < 1.6 {
            if a.frontline >= 2 {
                add(0.20, Reason("comp.frontline", Loc.tr("Takımda ön saf eksik; bu şampiyon hasar emebilir")))
            }
        }
        // Engage.
        if allies.count >= 2 && allies.engage < 3 && a.engage >= 2 {
            add(0.15, Reason("comp.engage", Loc.tr("Takımın savaş başlatma gücü düşük; güvenilir giriş sağlar")))
        }
        // Peel for carries.
        if allies.marksmen >= 1 && allies.peel < 3 && a.peel >= 2 {
            add(0.10, Reason("comp.peel", Loc.tr("Takımdaki nişancıyı koruyabilir")))
        }
        // Waveclear.
        if allies.count >= 3 && allies.waveclear < allies.count * 2 - 1 && a.waveclear >= 3 {
            add(0.07, Reason("comp.waveclear", Loc.tr("Dalga temizleme gücü takıma katkı sağlar")))
        }
        // Range balance.
        if allies.count >= 3 && allies.ranged == 0 && c.isRanged {
            add(0.06, Reason("comp.range", Loc.tr("Takım çoğunlukla yakın dövüşçü; menzil ekler")))
        }

        // Counter hints against visible enemies (champions only, never players).
        if enemies.count > 0 {
            if enemies.assassins + (enemies.mobility >= enemies.count * 2 + 1 ? 1 : 0) >= 2 && (a.cc >= 3 || a.durability >= 3) {
                add(0.12, Reason("vs.divers", Loc.tr("Rakipteki hareketli suikastçılara karşı kitle kontrolü ve dayanıklılık")))
            }
            if enemies.tanks >= 2 && (["marksman", "onhit", "battlemage", "juggernaut", "apbruiser"].contains(c.archetype)) {
                add(0.10, Reason("vs.tanks", Loc.tr("Rakipte birden çok tank var; sürekli hasar etkili")))
            }
            if enemies.count >= 3 && enemies.avgFrontline < 1.3 && a.burst >= 2 {
                add(0.08, Reason("vs.squishy", Loc.tr("Rakip kırılgan; ani hasar cezalandırır")))
            }
            if enemies.poke >= 3 && (a.engage >= 2 || a.sustain >= 3) {
                add(0.08, Reason("vs.poke", Loc.tr("Rakip uzaktan taciz ediyor; hızlı giriş veya yenilenme işe yarar")))
            }
            if enemies.physicalShare >= 0.75 && a.frontline >= 2 && enemies.count >= 3 {
                add(0.06, Reason("vs.ad", Loc.tr("Rakip çoğunlukla fiziksel hasar; zırh odaklı ön saf iyi karşılar")))
            }
            if enemies.healers >= 1 && a.burst >= 3 {
                add(0.04, Reason("vs.heal", Loc.tr("İyileştiren rakiplere karşı hızlı öldürme")))
            }
        }

        // Arena: duo synergy with the visible ally.
        if ctx.mode.family == .arena, let ally = ctx.allies.first {
            if ally.attrs.frontline >= 2 && c.attrs.damage >= 3 {
                add(0.12, Reason("arena.duo", Loc.tr("%@ ön safta durur, sen hasar verirsin", ally.displayName)))
            } else if ally.attrs.damage >= 3 && (c.attrs.frontline >= 2 || c.attrs.peel >= 2) {
                add(0.12, Reason("arena.duo", Loc.tr("%@ hasarı taşır, sen korur ya da önde durursun", ally.displayName)))
            }
        }

        // Own mastery (the player's own data).
        if let points = ctx.mastery[c.key], points >= 50_000 {
            add(min(0.15, Double(points) / 1_000_000.0 + 0.05), Reason("mastery", Loc.tr("Bu şampiyonda deneyimlisin")))
        }

        let ordered = reasons.sorted { abs($0.0) > abs($1.0) }.map(\.1)
        let fallback = ordered.isEmpty ? [Reason("base", Loc.tr("Takım dengesini bozmayan güvenli seçim"))] : ordered
        return (score, fallback)
    }
}
