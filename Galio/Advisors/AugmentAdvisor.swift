import Foundation

struct AugmentRating: Identifiable, Equatable {
    let augment: AugmentInfo
    let tier: Tier
    let reasons: [Reason]
    var id: Int { augment.id }
}

/// Champion-relative S–D tiers for ARAM Mayhem / Arena augments. Tiers come from how well an
/// augment's effects (derived from its tooltip) fit the champion's damage type and kit — never
/// from win rates (Riot policy forbids showing augment win rates).
enum AugmentAdvisor {
    struct Profile: Equatable {
        var wants: Set<String>
        var avoids: Set<String>
    }

    static func profile(for c: ChampionInfo, archetype: String? = nil) -> Profile {
        var wants: Set<String> = []
        var avoids: Set<String> = []
        let arch = archetype ?? c.archetype
        switch c.damageType {
        case "magic":
            wants.formUnion(["ap", "ah"])
            if !["onhit", "apbruiser"].contains(arch) { avoids.formUnion(["ad", "crit"]) }
        case "physical":
            wants.insert("ad")
            avoids.insert("ap")
        default:
            wants.formUnion(["ad", "ap"])
        }
        switch arch {
        case "marksman": wants.formUnion(["as", "crit"]); avoids.insert("tank")
        case "onhit": wants.formUnion(["as", "onhit"]); avoids.remove("ap")
        case "lethality", "assassin", "apassassin": wants.formUnion(["ms", "ah"]); avoids.insert("ally")
        case "bruiser", "juggernaut": wants.formUnion(["heal", "tank", "ah"])
        case "tank", "tankmage", "catcher": wants.formUnion(["tank", "shield", "ah"]); avoids.formUnion(["crit", "as"])
        case "enchanter": wants.formUnion(["ally", "heal", "shield", "ah"]); avoids.formUnion(["crit", "as", "ad"])
        case "burstmage", "battlemage", "artillery", "apbruiser": wants.insert("ah")
        default: break
        }
        if c.isRanged { avoids.insert("melee") } else { avoids.insert("ranged") }
        avoids.subtract(wants)
        return Profile(wants: wants, avoids: avoids)
    }

    static func rate(_ augment: AugmentInfo, champion: ChampionInfo, archetype: String? = nil) -> AugmentRating {
        let p = profile(for: champion, archetype: archetype)
        let aff = Set(augment.affinity)
        let tags = Set(augment.tags)
        var score = 0.45
        var reasons: [Reason] = []
        let hits = aff.intersection(p.wants)
        let misses = aff.intersection(p.avoids)
        if !hits.isEmpty {
            score += min(0.42, Double(hits.count) * 0.16)
            reasons.append(Reason("aug.fit", Loc.tr("%@ ile uyumlu: %@", champion.displayName, label(hits))))
        }
        if !misses.isEmpty {
            score -= min(0.4, Double(misses.count) * 0.17)
            reasons.append(Reason("aug.misfit", Loc.tr("Pek uymuyor: %@", label(misses)), positive: false))
        }
        if tags.contains("general") && misses.isEmpty {
            score += 0.06
            reasons.append(Reason("aug.general", Loc.tr("Her şampiyona genel değer katar")))
        }
        if tags.contains("quest") || tags.contains("questline") {
            reasons.append(Reason("aug.quest", Loc.tr("Görev güçlendirmesi: koşulu tamamlayınca güçlenir")))
        }
        if aff.isEmpty && tags.isEmpty {
            reasons.append(Reason("aug.unknown", Loc.tr("Etkisi sınıflandırılamadı; açıklamayı oku"), positive: false))
        }
        return AugmentRating(augment: augment, tier: Tier.from(score: score), reasons: reasons)
    }

    static func rank(_ augments: [AugmentInfo], champion: ChampionInfo, archetype: String? = nil) -> [AugmentRating] {
        augments.map { rate($0, champion: champion, archetype: archetype) }
            .sorted { $0.tier != $1.tier ? $0.tier > $1.tier : $0.augment.displayName < $1.augment.displayName }
    }

    static func label(_ keys: Set<String>) -> String {
        let names: [String: String] = [
            "ap": Loc.tr("yetenek gücü"), "ad": Loc.tr("saldırı gücü"), "as": Loc.tr("saldırı hızı"),
            "crit": Loc.tr("kritik"), "onhit": Loc.tr("isabet etkisi"), "ah": Loc.tr("yetenek hızı"),
            "tank": Loc.tr("dayanıklılık"), "shield": Loc.tr("kalkan"), "heal": Loc.tr("iyileşme"),
            "ms": Loc.tr("hareket hızı"), "ally": Loc.tr("takım desteği"), "melee": Loc.tr("yakın dövüş"),
            "ranged": Loc.tr("menzilli"), "summoner": Loc.tr("sihirdar büyüsü"), "ult": Loc.tr("ultimate"),
        ]
        return keys.sorted().map { names[$0] ?? $0 }.joined(separator: ", ")
    }
}

/// Fuzzy matching of OCR text lines against augment names (English + Turkish).
enum FuzzyMatcher {
    static func normalize(_ s: String) -> String {
        let folded = s.lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Normalised similarity 0…1 (1 = identical) based on Levenshtein distance.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(normalize(a)), y = Array(normalize(b))
        if x.isEmpty || y.isEmpty { return 0 }
        if x == y { return 1 }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    struct Match: Equatable {
        let augment: AugmentInfo
        let text: String
        let similarity: Double
    }

    /// Best distinct augment matches for the recognised lines (at most `limit`).
    static func match(lines: [String], augments: [AugmentInfo], threshold: Double = 0.74, limit: Int = 3) -> [Match] {
        var best: [Int: Match] = [:]
        for line in lines {
            let n = normalize(line)
            guard n.count >= 3 else { continue }
            for a in augments {
                let s = max(similarity(line, a.name), similarity(line, a.nameTR))
                guard s >= threshold else { continue }
                if (best[a.id]?.similarity ?? 0) < s { best[a.id] = Match(augment: a, text: line, similarity: s) }
            }
        }
        // One augment per recognised line: keep the strongest.
        var byLine: [String: Match] = [:]
        for m in best.values where (byLine[m.text]?.similarity ?? 0) < m.similarity { byLine[m.text] = m }
        return byLine.values.sorted { $0.similarity > $1.similarity }.prefix(limit).map { $0 }
    }
}
