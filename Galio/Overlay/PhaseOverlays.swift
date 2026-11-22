import SwiftUI

/// Champion select overlay: own pick, teams (visible picks only).
struct ChampSelectOverlay: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cs = session.champSelect {
                HStack {
                    ChampionChip(champion: store.champion(key: cs.myChampionId), size: 34)
                    Spacer()
                    if let pos = cs.myPosition {
                        Text(pos.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                TeamStrip(title: Loc.tr("Takım"), champions: cs.allyChampionIds.map { store.champion(key: $0) })
                TeamStrip(title: Loc.tr("Rakip"), champions: cs.visibleEnemyChampionIds.map { store.champion(key: $0) })
            } else {
                Text("Şampiyon seçimi okunuyor…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// In-game overlay: own champion, level and both teams' champions.
struct InGameOverlay: View {
    @EnvironmentObject private var session: GameSession
    @EnvironmentObject private var store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let live = session.live, let me = live.me {
                HStack {
                    ChampionChip(champion: store.champion(liveId: me.championDataId, name: me.championName), size: 34)
                    Spacer()
                    Text(Loc.tr("Seviye %@", String(me.level))).font(.caption.monospacedDigit())
                }
                TeamStrip(title: Loc.tr("Takım"), champions: live.allies.map { store.champion(liveId: $0.championDataId, name: $0.championName) })
                TeamStrip(title: Loc.tr("Rakip"), champions: live.enemies.map { store.champion(liveId: $0.championDataId, name: $0.championName) })
            } else {
                Text("Canlı oyun verisi bekleniyor…").font(.caption).foregroundStyle(.secondary)
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
            if let me = session.lastLive?.me {
                Text(Loc.tr("%@/%@/%@ · %@ CS", String(me.scores.kills), String(me.scores.deaths), String(me.scores.assists), String(me.scores.creepScore)))
                    .font(.callout.monospacedDigit())
            }
            Text("Ayrıntılı oyun sonu özeti ana pencerede.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
