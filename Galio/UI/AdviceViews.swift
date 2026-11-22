import SwiftUI

// MARK: - Champion suggestions

struct SuggestionRow: View {
    let suggestion: ChampionSuggestion
    let rank: Int
    var compact = false
    var reasonLimit: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(rank)).font(.caption.bold()).foregroundStyle(.secondary).frame(width: 14)
            ChampionChip(champion: suggestion.champion, size: compact ? 26 : 32, showName: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.champion.displayName).font(compact ? .callout.weight(.semibold) : .headline)
                ReasonList(reasons: suggestion.reasons, limit: reasonLimit ?? (compact ? 2 : 3))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Runes

struct RunePageCard: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var actions: ActionCenter
    let page: RunePageSuggestion
    let champion: ChampionInfo
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                RuneIcon(runeId: page.keystoneId, size: compact ? 26 : 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(page.title).font(compact ? .callout.weight(.semibold) : .headline).lineLimit(1)
                    Text(runeName(page.keystoneId)).font(.caption).foregroundStyle(.secondary).lineLimit(compact ? 1 : 2)
                }
                Spacer(minLength: 4)
                Button {
                    actions.importRunes(page, champion: champion)
                } label: {
                    Label("Aktar", systemImage: "square.and.arrow.down")
                }
                .controlSize(compact ? .small : .regular)
                .fixedSize()
                .disabled(!session.connection.isConnected || !session.phase.allowsClientActions || actions.busy)
                .help("Bu sayfayı tek tıkla League istemcisine aktar")
            }
            if !compact {
                HStack(spacing: 4) {
                    ForEach(Array(page.perkIds.dropFirst().prefix(5).enumerated()), id: \.offset) { _, id in
                        RuneIcon(runeId: id, size: 22)
                    }
                    Divider().frame(height: 18)
                    ForEach(Array(page.perkIds.suffix(3).enumerated()), id: \.offset) { _, id in
                        RuneIcon(runeId: id, size: 18)
                    }
                }
            }
            ReasonList(reasons: page.reasons, limit: compact ? 1 : 3)
        }
    }

    private func runeName(_ id: Int) -> String {
        let primary = store.stylesById[page.primaryStyleId]?.displayName ?? ""
        let sub = store.stylesById[page.subStyleId]?.displayName ?? ""
        return "\(store.runesById[id]?.displayName ?? "?") · \(primary) + \(sub)"
    }
}

// MARK: - Summoner spells

struct SpellOptionRow: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var actions: ActionCenter
    @EnvironmentObject private var store: DataStore
    let option: SpellSuggestion
    let current: [Int]
    var showSetButton = true
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(option.spells, id: \.self) { SummonerIcon(spellId: $0, size: compact ? 24 : 36) }
            }
            VStack(alignment: .leading, spacing: 2) {
                if !compact {
                    Text(option.spells.compactMap { store.summonersById[$0]?.displayName }.joined(separator: " + "))
                        .font(.callout.weight(.semibold))
                }
                ReasonList(reasons: option.reasons, limit: 1)
            }
            Spacer(minLength: 0)
            if showSetButton && session.phase == .champSelect {
                if Set(current) == Set(option.spells) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityLabel("Seçili")
                } else {
                    Button("Ayarla") { actions.setSpells(option.spells, current: current) }
                        .controlSize(.small)
                        .disabled(actions.busy)
                        .help("Bu büyüleri şampiyon seçiminde ayarla")
                }
            }
        }
    }
}

// MARK: - Skill order

struct SkillOrderView: View {
    let plan: SkillPlan
    let champion: ChampionInfo?
    var compact = false
    var currentLevel: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Önce yükselt:").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(plan.maxOrder.enumerated()), id: \.offset) { i, key in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    SkillKey(key: key, name: champion?.spellNames[key])
                }
            }
            HStack(spacing: 4) {
                Text("İlk seviyeler:").font(.caption).foregroundStyle(.secondary)
                Text(plan.firstThree.joined(separator: " → ")).font(.caption.monospaced().bold())
            }
            if !compact {
                SkillGrid(plan: plan, currentLevel: currentLevel)
            }
        }
    }
}

struct SkillKey: View {
    let key: String
    var name: String?

    var body: some View {
        Text(key)
            .font(.system(.callout, design: .rounded).bold())
            .frame(width: 24, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.25)))
            .help(name ?? key)
            .accessibilityLabel(name.map { "\(key): \($0)" } ?? key)
    }
}

struct SkillGrid: View {
    let plan: SkillPlan
    var currentLevel: Int?

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                Text("").frame(width: 16)
                ForEach(1...18, id: \.self) { lvl in
                    Text(String(lvl)).font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(lvl == currentLevel ? Color.accentColor : .secondary)
                        .frame(width: 16)
                }
            }
            ForEach(["Q", "W", "E", "R"], id: \.self) { key in
                GridRow {
                    Text(key).font(.caption.bold()).frame(width: 16)
                    ForEach(0..<18, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(plan.sequence[i] == key ? Color.accentColor : Color.secondary.opacity(0.12))
                            .frame(width: 16, height: 14)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Loc.tr("Yetenek sırası: %@", plan.sequence.joined(separator: " ")))
    }
}

// MARK: - Items

struct ItemBuildView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var actions: ActionCenter
    let build: BuildData
    let champion: ChampionInfo
    let buildKey: String
    let map: Int
    let threat: EnemyThreat
    var showExport = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !build.items.starter.isEmpty {
                ItemRow(title: Loc.tr("Başlangıç"), ids: build.items.starter)
            }
            ItemRow(title: Loc.tr("Temel"), ids: Array(build.items.boots.prefix(1)) + Array(build.items.core.prefix(3)))
            ItemRow(title: Loc.tr("Sonra"), ids: Array(build.items.core.dropFirst(3)))
            let situational = rankedSituational
            if !situational.isEmpty {
                Text("Duruma göre").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(situational, id: \.0.id) { item, reasons in
                    HStack(alignment: .top, spacing: 8) {
                        ItemIcon(itemId: item.id, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayName).font(.callout)
                            if !reasons.isEmpty { ReasonList(reasons: reasons, limit: 1) }
                        }
                    }
                }
            }
            if showExport {
                Button {
                    actions.exportItemSet(ItemSetPayload.from(build: build, champion: champion, position: buildKey, map: map, threat: threat))
                } label: {
                    Label("Eşya setini istemciye yaz", systemImage: "tray.and.arrow.down")
                }
                .disabled(!session.connection.isConnected || !session.phase.allowsClientActions || actions.busy)
                .help("Mağazada görünen bir eşya seti oluşturur (yalnızca tıklayınca, oyun dışında)")
            }
        }
    }

    /// Situational items, ordered by relevance against the visible enemy team.
    private var rankedSituational: [(ItemInfo, [Reason])] {
        build.items.situational.compactMap { s -> (ItemInfo, [Reason], Double)? in
            guard let item = store.itemsById[s.id] else { return nil }
            let value = ItemAdvisor.situationalValue(item, threat: threat)
            return (item, value.map(\.1), value.reduce(0) { $0 + $1.0 })
        }
        .sorted { $0.2 > $1.2 }
        .prefix(5)
        .map { ($0.0, $0.1) }
    }
}

struct ItemRow: View {
    let title: String
    let ids: [Int]

    var body: some View {
        if !ids.isEmpty {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                ForEach(Array(ids.enumerated()), id: \.offset) { _, id in ItemIcon(itemId: id, size: 30) }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Transient status message for client actions.
struct ActionToast: View {
    @EnvironmentObject private var actions: ActionCenter

    var body: some View {
        if let msg = actions.message {
            Label(msg, systemImage: actions.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(actions.isError ? Color.orange : Color.green)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
        }
    }
}

/// Confirmation before overwriting one of the player's own rune pages when the limit is full.
struct ReplacePageDialog: ViewModifier {
    @ObservedObject var actions: ActionCenter

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Rün sayfası sınırı dolu",
            isPresented: Binding(get: { actions.pendingReplace != nil }, set: { if !$0 { actions.pendingReplace = nil } }),
            presenting: actions.pendingReplace
        ) { pending in
            Button(Loc.tr("\"%@\" sayfasının yerine yaz", pending.pageName), role: .destructive) { actions.confirmReplace() }
            Button("Vazgeç", role: .cancel) { actions.pendingReplace = nil }
        } message: { pending in
            Text(Loc.tr("Galio yeni sayfa için \"%@\" sayfanı silecek. Devam edilsin mi?", pending.pageName))
        }
    }
}

extension View {
    func replacePageDialog(_ actions: ActionCenter) -> some View { modifier(ReplacePageDialog(actions: actions)) }
}
