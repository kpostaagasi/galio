import SwiftUI

/// In-game overlay. Collapsed: next skill, top 3 items with one-line reasons and augment tiers
/// when the mode has augments. Expanded: enemy team, buildable components, augment search.
struct InGameOverlay: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore
    @AppStorage(OverlayController.expandedKey) private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 8 : 6) {
            if let advice = AdviceBuilder.inGame(session: session, store: store) {
                if expanded {
                    InGameHeader(advice: advice)
                }
                if let plan = advice.skill {
                    HStack(spacing: 8) {
                        SkillReminder(plan: plan, next: advice.nextSkill, champion: advice.champion)
                        if !expanded {
                            Text(Loc.tr("Sv %@ · %@ altın", String(advice.level), String(Int(advice.gold))))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                }
                if !advice.items.isEmpty {
                    Divider().opacity(0.4)
                    Text("Sıradaki eşya seçenekleri").font(.caption.weight(.semibold))
                    ForEach(advice.items.prefix(3)) { s in ItemSuggestionRow(suggestion: s, compact: true, showComponent: expanded) }
                }
                if advice.mode.hasAugments {
                    Divider().opacity(0.4)
                    AugmentPanel(ratings: advice.augments, champion: advice.champion, compact: true, showSearch: expanded)
                }
            } else {
                Text("Canlı oyun verisi bekleniyor…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct InGameHeader: View {
    let advice: InGameAdvice

    var body: some View {
        HStack {
            ChampionChip(champion: advice.champion, size: 34)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(Loc.tr("Seviye %@", String(advice.level))).font(.caption.monospacedDigit())
                Text(Loc.tr("%@ altın", String(Int(advice.gold)))).font(.caption2.monospacedDigit()).foregroundStyle(.yellow)
            }
        }
        TeamStrip(title: Loc.tr("Rakip"), champions: advice.enemies, size: 22)
    }
}

/// Reminder only — the player levels the ability (Galio never sends input to the game).
struct SkillReminder: View {
    let plan: SkillPlan
    let next: String?
    let champion: ChampionInfo?

    var body: some View {
        HStack(spacing: 8) {
            if let next {
                Text("Sıradaki yetenek:").font(.caption).foregroundStyle(.secondary)
                SkillKey(key: next, name: champion?.spellNames[next])
                    .scaleEffect(1.15)
                if let name = champion?.spellNames[next] {
                    Text(name).font(.caption).lineLimit(1)
                }
            } else {
                Text("Yükseltme sırası:").font(.caption).foregroundStyle(.secondary)
                Text(plan.maxOrder.joined(separator: " > ")).font(.caption.monospaced().bold())
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ItemSuggestionRow: View {
    let suggestion: ItemSuggestion
    var compact = false
    var showComponent = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ItemIcon(itemId: suggestion.item.id, size: compact ? 26 : 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(suggestion.item.displayName).font(compact ? .callout.weight(.semibold) : .headline).lineLimit(1)
                    Spacer(minLength: 0)
                    if suggestion.goldMissing == 0 {
                        Text("Alınabilir").font(.caption2.bold()).foregroundStyle(.green)
                    } else {
                        Text(Loc.tr("%@ eksik", String(suggestion.goldMissing))).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                ReasonList(reasons: suggestion.reasons, limit: compact ? 1 : 3)
                if showComponent, let comp = suggestion.componentNow {
                    Text(Loc.tr("Şimdi alınabilecek parça: %@", comp.displayName)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Augment helper: OCR scan of the three offered cards + manual search, with S–D tiers only.
struct AugmentPanel: View {
    @EnvironmentObject private var session: GameSession
    let ratings: [AugmentRating]
    let champion: ChampionInfo?
    var compact = false
    var showSearch = true

    @State private var query = ""
    @State private var scanned: [AugmentRating] = []
    @State private var scanning = false
    @State private var status: String?

    private var byId: [Int: AugmentRating] { Dictionary(ratings.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    private var searchResults: [AugmentRating] {
        let q = FuzzyMatcher.normalize(query)
        guard q.count >= 2 else { return [] }
        return ratings.filter {
            FuzzyMatcher.normalize($0.augment.name).contains(q) || FuzzyMatcher.normalize($0.augment.nameTR).contains(q)
        }
        .prefix(compact ? 4 : 10).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Güçlendirmeler").font(.caption.weight(.semibold))
                Spacer()
                Button {
                    scan()
                } label: {
                    Label("Kartları tara", systemImage: "text.viewfinder")
                }
                .controlSize(.small)
                .disabled(scanning)
                .help("Ekrandaki üç güçlendirme kartının adını cihaz üzerinde okur (Ekran Kaydı izni gerekir)")
            }
            if let status {
                Text(status).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(scanned) { r in AugmentRow(rating: r, compact: compact) }
            if showSearch {
                TextField("Güçlendirme ara", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                ForEach(searchResults) { r in AugmentRow(rating: r, compact: compact) }
            }
            if query.isEmpty && scanned.isEmpty {
                Text("En uyumlu güçlendirmeler").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(ratings.prefix(compact ? 3 : 8)) { r in AugmentRow(rating: r, compact: compact) }
            }

            Text("Yalnızca seviye gösterilir; kazanma oranı gösterilmez.").font(.caption2).foregroundStyle(.tertiary)
        }
        .onAppear(perform: applyMockOffer)
    }

    /// In mock scenarios, feed simulated OCR lines through the same fuzzy matcher as a real scan.
    private func applyMockOffer() {
        guard scanned.isEmpty, !session.mockAugmentOffer.isEmpty else { return }
        let matches = FuzzyMatcher.match(lines: session.mockAugmentOffer, augments: ratings.map(\.augment))
        scanned = matches.compactMap { byId[$0.augment.id] }
        if !scanned.isEmpty { status = Loc.tr("Deneme modu: kartlar simüle edildi") }
    }

    private func scan() {
        if !AugmentOCR.hasPermission {
            AugmentOCR.requestPermission()
            status = Loc.tr("Ekran Kaydı izni gerekli: Sistem Ayarları > Gizlilik ve Güvenlik > Ekran ve Sistem Sesi Kaydı'ndan Galio'yu aç, sonra tekrar dene. Bu arada aşağıdan elle arayabilirsin.")
            return
        }
        scanning = true
        status = Loc.tr("Taranıyor…")
        let augments = ratings.map(\.augment)
        Task {
            defer { scanning = false }
            do {
                let matches = try await AugmentOCR.scan(augments: augments)
                scanned = matches.compactMap { byId[$0.augment.id] }
                status = scanned.isEmpty ? Loc.tr("Kart bulunamadı. Kartlar ekrandayken tekrar dene ya da elle ara.") : nil
            } catch {
                status = Loc.tr("Tarama başarısız: %@", error.localizedDescription)
            }
        }
    }
}

struct AugmentRow: View {
    let rating: AugmentRating
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TierBadge(tier: rating.tier)
            CachedImage(url: DDragon.augmentIcon(rating.augment.icon), size: compact ? 22 : 28, cornerRadius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(rating.augment.displayName).font(compact ? .callout : .headline)
                ReasonList(reasons: rating.reasons, limit: compact ? 1 : 2)
                if !compact && !rating.augment.desc.isEmpty {
                    Text(rating.augment.desc).font(.caption2).foregroundStyle(.tertiary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Full in-game page in the main window.
struct InGamePage: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore

    var body: some View {
        if let advice = AdviceBuilder.inGame(session: session, store: store) {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    InGameHeader(advice: advice)
                    TeamStrip(title: Loc.tr("Takım"), champions: advice.allies, size: 22)
                    ThreatSummary(threat: advice.threat)
                }
                if let plan = advice.skill {
                    Card {
                        Text("Yetenek sırası").font(.title3.bold())
                        SkillReminder(plan: plan, next: advice.nextSkill, champion: advice.champion)
                        SkillGrid(plan: plan, currentLevel: advice.level)
                        Text("Hatırlatma: yeteneği sen yükseltirsin, Galio oyuna hiçbir tuş göndermez.").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                if !advice.items.isEmpty {
                    Card {
                        Text("Sıradaki eşya seçenekleri").font(.title3.bold())
                        ForEach(advice.items) { s in ItemSuggestionRow(suggestion: s) }
                    }
                }
                if advice.mode.hasAugments {
                    Card { AugmentPanel(ratings: advice.augments, champion: advice.champion) }
                }
            }
        } else {
            Card { Text("Canlı oyun verisi bekleniyor…").foregroundStyle(.secondary) }
        }
    }
}

struct ThreatSummary: View {
    let threat: EnemyThreat

    var body: some View {
        let ad = Int((threat.adShare * 100).rounded())
        HStack(spacing: 12) {
            Label(Loc.tr("Fiziksel %@%%", String(ad)), systemImage: "bolt.fill").foregroundStyle(.orange)
            Label(Loc.tr("Büyü %@%%", String(100 - ad)), systemImage: "sparkles").foregroundStyle(.purple)
            if threat.healing >= 1.2 { Label("İyileşme", systemImage: "cross.fill").foregroundStyle(.green) }
            if threat.cc >= 3 { Label("Kitle kontrolü", systemImage: "lock.fill").foregroundStyle(.blue) }
            if threat.crit >= 1 { Label("Kritik", systemImage: "scope").foregroundStyle(.red) }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}
