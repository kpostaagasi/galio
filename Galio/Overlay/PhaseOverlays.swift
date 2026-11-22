import SwiftUI

/// Champion select overlay: suggestions before lock-in, then runes / spells / skill order.
/// Collapsed: only the essentials; expanded: team strips and reasons.
struct ChampSelectOverlay: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore
    @AppStorage(OverlayController.expandedKey) private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 8 : 6) {
            if let cs = session.champSelect, let advice = AdviceBuilder.champSelect(session: session, store: store) {
                HStack {
                    ChampionChip(champion: advice.champion, size: expanded ? 34 : 26)
                    Spacer()
                    if let pos = cs.myPosition {
                        Text(pos.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if expanded {
                    TeamStrip(title: Loc.tr("Takım"), champions: advice.allies)
                    TeamStrip(title: Loc.tr("Rakip"), champions: advice.enemies)
                    Divider().opacity(0.4)
                }
                if !advice.locked || cs.benchEnabled {
                    Text(cs.benchEnabled ? Loc.tr("Takas önerileri") : Loc.tr("Öneriler")).font(.caption.weight(.semibold))
                    ForEach(Array(advice.suggestions.prefix(3).enumerated()), id: \.element.id) { i, s in
                        SuggestionRow(suggestion: s, rank: i + 1, compact: true, reasonLimit: expanded ? 2 : 1)
                    }
                }
                if advice.locked, let champion = advice.champion {
                    if let page = advice.runes.first {
                        RunePageCard(page: page, champion: champion, compact: true)
                    }
                    if let spell = advice.spells.first {
                        SpellOptionRow(option: spell, current: advice.currentSpells, compact: true)
                    }
                    if let plan = advice.skill {
                        SkillOrderView(plan: plan, champion: champion, compact: true)
                    }
                    PendingReplaceInline()
                    ActionToast()
                }
            } else {
                Text("Şampiyon seçimi okunuyor…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Post-game overlay: one-line summary, details in the main window.
struct PostGameOverlay: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChampionChip(champion: session.myChampion(in: store), size: 32)
            if let r = session.lastRecord {
                Text(Loc.tr("%@/%@/%@ · %@ CS", String(r.kills), String(r.deaths), String(r.assists), String(r.creepScore)))
                    .font(.callout.monospacedDigit())
                if let note = PostGameReview.notes(for: r, benchmark: PostGameReview.benchmark(for: r, store: store)).first {
                    ReasonList(reasons: [note], limit: 1)
                }
            }
            Text("Ayrıntılı oyun sonu özeti ana pencerede.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Inline version of the "rune page limit full" confirmation for the overlay panel.
struct PendingReplaceInline: View {
    @EnvironmentObject private var actions: ActionCenter

    var body: some View {
        if let pending = actions.pendingReplace {
            VStack(alignment: .leading, spacing: 6) {
                Text(Loc.tr("Galio yeni sayfa için \"%@\" sayfanı silecek. Devam edilsin mi?", pending.pageName))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(Loc.tr("\"%@\" sayfasının yerine yaz", pending.pageName), role: .destructive) { actions.confirmReplace() }
                    Button("Vazgeç") { actions.pendingReplace = nil }
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
