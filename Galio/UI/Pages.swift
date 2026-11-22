import SwiftUI

/// Champion browser: search, then a static page (runes, spells, skill order, items) per role.
struct ChampionsView: View {
    @EnvironmentObject private var store: DataStore
    @State private var query = ""
    @State private var selected: ChampionInfo.ID?

    private var champions: [ChampionInfo] {
        let all = store.data?.champions ?? []
        let q = FuzzyMatcher.normalize(query)
        let list = q.isEmpty ? all : all.filter { FuzzyMatcher.normalize($0.name).contains(q) || FuzzyMatcher.normalize($0.nameTR).contains(q) }
        return list.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        HSplitView {
            List(champions, selection: $selected) { champ in
                HStack {
                    ChampionChip(champion: champ, size: 26)
                    Spacer()
                    Text(champ.positionList.first?.title ?? "").font(.caption2).foregroundStyle(.secondary)
                }
                .tag(champ.id)
            }
            .searchable(text: $query, placement: .sidebar, prompt: Text("Şampiyon ara"))
            .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
            Group {
                if let id = selected, let champ = store.championsById[id] {
                    ChampionDetailView(champion: champ)
                        .id(champ.id)
                } else {
                    ContentUnavailableView("Bir şampiyon seç", systemImage: "person.crop.square",
                                           description: Text("Rünler, yetenek sırası ve eşyalar burada görünür."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Şampiyonlar")
    }
}

struct ChampionDetailView: View {
    @EnvironmentObject private var store: DataStore
    let champion: ChampionInfo
    @State private var buildKey: String = ""

    private var keys: [String] {
        (store.detail(for: champion)?.builds.keys.map { $0 } ?? [])
            .sorted { order($0) < order($1) }
    }

    private func order(_ key: String) -> Int {
        if key == "ARAM" { return 99 }
        return champion.positions.firstIndex(of: key) ?? 50
    }

    private func title(_ key: String) -> String {
        key == "ARAM" ? "ARAM" : (Position(rawValue: key)?.title ?? key)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ChampionChip(champion: champion, size: 56, showName: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(champion.displayName).font(.largeTitle.bold())
                        Text(champion.displayTitle).foregroundStyle(.secondary)
                        Text(attributeSummary).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Picker("Rol", selection: $buildKey) {
                    ForEach(keys, id: \.self) { Text(title($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .onAppear { if buildKey.isEmpty { buildKey = keys.first ?? "" } }
                let key = buildKey.isEmpty ? (keys.first ?? "ARAM") : buildKey
                ChampionBuildSections(advice: AdviceBuilder.championPage(champion, key: key, store: store), champion: champion, showActions: false)
                AbilitiesCard(champion: champion)
                if let detail = store.detail(for: champion) {
                    Text(Loc.tr("Kaynak: %@ · yama %@", detail.source, detail.patch)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(20)
        }
    }

    private var attributeSummary: String {
        let a = champion.attrs
        let dmg: String
        switch champion.damageType {
        case "magic": dmg = Loc.tr("Büyü hasarı")
        case "mixed": dmg = Loc.tr("Karma hasar")
        default: dmg = Loc.tr("Fiziksel hasar")
        }
        return Loc.tr("%@ · ön saf %@/3 · giriş %@/3 · koruma %@/3", dmg, String(a.frontline), String(a.engage), String(a.peel))
    }
}


/// Ability names and descriptions from the champion's Data Dragon file (localized, cached per patch).
struct AbilitiesCard: View {
    @EnvironmentObject private var store: DataStore
    let champion: ChampionInfo
    @State private var dd: DDChampion?
    @State private var failed = false

    var body: some View {
        Card {
            Text("Yetenekler").font(.title3.bold())
            if let dd {
                AbilityRow(key: Loc.tr("Pasif"), name: dd.passive.name, text: dd.passive.description,
                           icon: DDragon.passiveIcon(dd.passive.image.full, patch: store.imagePatch))
                ForEach(Array(zip(["Q", "W", "E", "R"], dd.spells)), id: \.0) { key, spell in
                    AbilityRow(key: key, name: spell.name, text: spell.description,
                               icon: DDragon.spellIcon(spell.image.full, patch: store.imagePatch))
                }
            } else if failed {
                Text("Yetenek bilgisi yüklenemedi (çevrimdışı olabilirsin).").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: champion.id) {
            do {
                dd = try await DDragon.champion(id: champion.id, patch: store.imagePatch)
                failed = dd == nil
            } catch {
                failed = true
            }
        }
    }
}

struct AbilityRow: View {
    let key: String
    let name: String
    let text: String
    let icon: URL

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CachedImage(url: icon, size: 32, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(key) · \(name)").font(.headline)
                Text(Self.plain(text)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<br>", with: " ")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
