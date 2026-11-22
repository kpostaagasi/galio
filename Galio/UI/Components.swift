import SwiftUI

/// Champion icon + name. Never shows player names — only champions.
struct ChampionChip: View {
    @EnvironmentObject private var store: DataStore
    let champion: ChampionInfo?
    var size: CGFloat = 28
    var showName = true
    var dimmed = false

    var body: some View {
        HStack(spacing: 6) {
            CachedImage(url: champion.map { DDragon.championIcon($0.id, patch: store.imagePatch) }, size: size, cornerRadius: size / 4)
                .opacity(dimmed ? 0.5 : 1)
            if showName {
                Text(champion?.displayName ?? "—")
                    .lineLimit(1)
                    .foregroundStyle(dimmed ? .secondary : .primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(champion?.displayName ?? Loc.tr("Seçilmedi"))
    }
}

struct ItemIcon: View {
    @EnvironmentObject private var store: DataStore
    let itemId: Int
    var size: CGFloat = 28

    var body: some View {
        let item = store.itemsById[itemId]
        CachedImage(url: DDragon.itemIcon(itemId, patch: store.imagePatch), size: size, cornerRadius: 4)
            .help(item?.displayName ?? String(itemId))
            .accessibilityElement()
            .accessibilityLabel(item?.displayName ?? String(itemId))
    }
}

struct RuneIcon: View {
    @EnvironmentObject private var store: DataStore
    let runeId: Int
    var size: CGFloat = 24

    var body: some View {
        if let rune = store.runesById[runeId] {
            CachedImage(url: DDragon.runeIcon(rune.icon), size: size, cornerRadius: size / 2)
                .help(rune.displayName)
                .accessibilityElement()
                .accessibilityLabel(rune.displayName)
        } else if let style = store.stylesById[runeId] {
            CachedImage(url: DDragon.runeIcon(style.icon), size: size, cornerRadius: size / 2)
                .help(style.displayName)
                .accessibilityElement()
                .accessibilityLabel(style.displayName)
        } else if let shard = store.shardsById[runeId] {
            CachedImage(url: shard.icon.flatMap { DDragon.shardIcon($0) }, size: size, cornerRadius: size / 2)
                .padding(2)
                .background(Circle().fill(Color.secondary.opacity(0.2)))
                .help(shard.displayName)
                .accessibilityElement()
                .accessibilityLabel(shard.displayName)
        }
    }
}

struct SummonerIcon: View {
    @EnvironmentObject private var store: DataStore
    let spellId: Int
    var size: CGFloat = 24

    var body: some View {
        let spell = store.summonersById[spellId]
        CachedImage(url: spell.map { DDragon.spellIcon($0.image, patch: store.imagePatch) }, size: size, cornerRadius: 4)
            .help(spell?.displayName ?? "")
            .accessibilityElement()
            .accessibilityLabel(spell?.displayName ?? "")
    }
}

/// Small rounded "card" container used across the app and the overlay.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A list of reasons shown under a recommendation.
struct ReasonList: View {
    let reasons: [Reason]
    var limit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(reasons.prefix(limit).enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: r.positive ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(r.positive ? Color.green : Color.orange)
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text(r.text).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Tier badge (S–D). Tiers only — never win rates (Riot policy).
struct TierBadge: View {
    let tier: Tier

    var body: some View {
        Text(tier.rawValue)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .frame(width: 22, height: 22)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 5).fill(tier.color))
            .accessibilityLabel(Loc.tr("Seviye %@", tier.rawValue))
    }
}

extension Tier {
    var color: Color {
        switch self {
        case .S: return Color(red: 0.93, green: 0.35, blue: 0.20)
        case .A: return Color(red: 0.93, green: 0.62, blue: 0.13)
        case .B: return Color(red: 0.25, green: 0.62, blue: 0.35)
        case .C: return Color(red: 0.28, green: 0.50, blue: 0.80)
        case .D: return Color.gray
        }
    }
}
