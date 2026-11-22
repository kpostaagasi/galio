import SwiftUI

/// Full champion select page in the main window.
struct ChampSelectPage: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var actions: ActionCenter

    var body: some View {
        if let advice = AdviceBuilder.champSelect(session: session, store: store) {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    HStack(spacing: 12) {
                        ChampionChip(champion: advice.champion, size: 44)
                        VStack(alignment: .leading, spacing: 0) {
                            if let pos = advice.position { Text(pos.title).font(.headline) }
                            Text(advice.locked ? Loc.tr("Seçim kilitlendi") : Loc.tr("Seçim sürüyor")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 18) {
                            TeamStrip(title: Loc.tr("Takım"), champions: advice.allies, size: 28)
                            TeamStrip(title: Loc.tr("Rakip"), champions: advice.enemies, size: 28)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            TeamStrip(title: Loc.tr("Takım"), champions: advice.allies, size: 28)
                            TeamStrip(title: Loc.tr("Rakip"), champions: advice.enemies, size: 28)
                        }
                    }
                    Text("Rakip oyuncuların adları ve istatistikleri gösterilmez; yalnızca görünen şampiyonlar kullanılır.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if !advice.suggestions.isEmpty && (!advice.locked || session.champSelect?.benchEnabled == true) {
                    Card {
                        Text(session.champSelect?.benchEnabled == true ? Loc.tr("Takas önerileri") : Loc.tr("Şampiyon önerileri"))
                            .font(.title3.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .topLeading)],
                                  alignment: .leading, spacing: 10) {
                            ForEach(Array(advice.suggestions.enumerated()), id: \.element.id) { i, s in
                                SuggestionRow(suggestion: s, rank: i + 1)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                }
                if let champion = advice.champion {
                    ChampionBuildSections(advice: advice, champion: champion, showActions: true)
                }
                ActionToast()
            }
            .replacePageDialog(actions)
        } else {
            Card { Text("Şampiyon seçimi okunuyor…").foregroundStyle(.secondary) }
        }
    }
}

/// Runes, spells, skill order and items for one champion/build (shared by champ select and the champion browser).
/// Sections stack vertically so nothing is clipped in narrow windows.
struct ChampionBuildSections: View {
    @EnvironmentObject private var store: DataStore
    let advice: ChampSelectAdvice
    let champion: ChampionInfo
    var showActions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !advice.runes.isEmpty {
                Card {
                    Text("Rün sayfaları").font(.title3.bold())
                    ForEach(Array(advice.runes.enumerated()), id: \.element.id) { i, page in
                        RunePageCard(page: page, champion: champion)
                        if i < advice.runes.count - 1 { Divider() }
                    }
                }
            }
            if let plan = advice.skill {
                Card {
                    Text("Yetenek sırası").font(.title3.bold())
                    SkillOrderView(plan: plan, champion: champion)
                    if let games = store.detail(for: champion)?.skillOrder.games {
                        Text(Loc.tr("Örneklenen %@ dereceli oyunda en popüler sıra", String(games)))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            if !advice.spells.isEmpty {
                Card {
                    Text("Sihirdar büyüleri").font(.title3.bold())
                    ForEach(advice.spells) { option in
                        SpellOptionRow(option: option, current: advice.currentSpells, showSetButton: showActions)
                    }
                }
            }
            if let build = advice.build {
                Card {
                    Text("Eşyalar").font(.title3.bold())
                    ItemBuildView(build: build, champion: champion, buildKey: advice.buildKey, map: advice.mode.itemMap,
                                  threat: advice.threat, showExport: showActions)
                    if let n = build.sample?.coreGames {
                        Text(Loc.tr("Temel üçlü örneklenen %@ oyunda en popüler; diğerleri kurala dayalı", String(n)))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
