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
                    HStack {
                        ChampionChip(champion: advice.champion, size: 44)
                        Spacer()
                        VStack(alignment: .trailing) {
                            if let pos = advice.position { Text(pos.title).font(.headline) }
                            Text(advice.locked ? Loc.tr("Seçim kilitlendi") : Loc.tr("Seçim sürüyor")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    TeamStrip(title: Loc.tr("Takım"), champions: advice.allies, size: 30)
                    TeamStrip(title: Loc.tr("Rakip"), champions: advice.enemies, size: 30)
                    Text("Rakip oyuncuların adları ve istatistikleri gösterilmez; yalnızca görünen şampiyonlar kullanılır.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if !advice.suggestions.isEmpty && (!advice.locked || session.champSelect?.benchEnabled == true) {
                    Card {
                        Text(session.champSelect?.benchEnabled == true ? Loc.tr("Takas önerileri") : Loc.tr("Şampiyon önerileri"))
                            .font(.title3.bold())
                        ForEach(Array(advice.suggestions.enumerated()), id: \.element.id) { i, s in
                            SuggestionRow(suggestion: s, rank: i + 1)
                            if i < advice.suggestions.count - 1 { Divider() }
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
struct ChampionBuildSections: View {
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
            HStack(alignment: .top, spacing: 14) {
                if !advice.spells.isEmpty {
                    Card {
                        Text("Sihirdar büyüleri").font(.title3.bold())
                        ForEach(advice.spells) { option in
                            SpellOptionRow(option: option, current: advice.currentSpells, showSetButton: showActions)
                        }
                    }
                }
                if let plan = advice.skill {
                    Card {
                        Text("Yetenek sırası").font(.title3.bold())
                        SkillOrderView(plan: plan, champion: champion)
                    }
                }
            }
            if let build = advice.build {
                Card {
                    Text("Eşyalar").font(.title3.bold())
                    ItemBuildView(build: build, champion: champion, buildKey: advice.buildKey, map: advice.mode.itemMap,
                                  threat: advice.threat, showExport: showActions)
                }
            }
        }
    }
}
