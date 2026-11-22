import SwiftUI

/// Summary of one finished game (own numbers only) with plan comparison and learning notes.
struct GameSummaryView: View {
    @EnvironmentObject private var store: DataStore
    let record: GameRecord

    private var champion: ChampionInfo? { store.championsById[record.championId] ?? store.champion(key: record.championKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ChampionChip(champion: champion, size: 48, showName: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(champion?.displayName ?? record.championId).font(.title2.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                Spacer()
                if let win = record.win {
                    (win ? Text("Zafer") : Text("Bozgun"))
                        .font(.headline)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background((win ? Color.green : Color.red).opacity(0.2), in: Capsule())
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    StatCell(title: Loc.tr("KDA"), value: "\(record.kills)/\(record.deaths)/\(record.assists)", detail: String(format: "%.1f", record.kda))
                    StatCell(title: Loc.tr("Minyon"), value: String(record.creepScore), detail: Loc.tr("%@/dk", String(format: "%.1f", record.csPerMinute)))
                    StatCell(title: Loc.tr("Şampiyon hasarı"), value: record.damageToChampions.map { String($0) } ?? "—", detail: nil)
                }
                GridRow {
                    StatCell(title: Loc.tr("Altın"), value: record.goldEarned.map { String($0) } ?? "—", detail: nil)
                    StatCell(title: Loc.tr("Görüş"), value: record.visionScore.map { String(Int($0)) } ?? "—", detail: nil)
                    StatCell(title: Loc.tr("Süre"), value: duration, detail: nil)
                }
            }
            if !record.items.isEmpty || !record.plannedCore.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Eşyalar ve plan").font(.headline)
                    ItemRow(title: Loc.tr("Son durum"), ids: record.items)
                    HStack(spacing: 6) {
                        Text("Plan").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                        ForEach(Array(record.plannedCore.prefix(3).enumerated()), id: \.offset) { _, id in
                            ZStack(alignment: .bottomTrailing) {
                                ItemIcon(itemId: id, size: 30).opacity(record.items.contains(id) ? 1 : 0.45)
                                Image(systemName: record.items.contains(id) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(record.items.contains(id) ? Color.green : Color.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        Spacer()
                    }
                }
            }
            let notes = PostGameReview.notes(for: record)
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notlar").font(.headline)
                    ReasonList(reasons: notes, limit: 6)
                }
            }
        }
    }

    private var subtitle: String {
        var parts = [record.modeTitle]
        if let p = record.position.flatMap({ Position(rawValue: $0) }) { parts.append(p.title) }
        parts.append(record.date.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: " · ")
    }

    private var duration: String {
        let s = Int(record.durationSeconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct StatCell: View {
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().bold())
            if let detail { Text(detail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Post-game page in the main window.
struct PostGamePage: View {
    @EnvironmentObject private var session: GameSession

    var body: some View {
        if let record = session.lastRecord {
            Card { GameSummaryView(record: record) }
        } else {
            Card {
                Text("Oyun sonu verisi bekleniyor…").foregroundStyle(.secondary)
                Button("Tekrar dene") { Task { await session.refreshEndOfGame() } }
            }
        }
    }
}

/// Local history list with details.
struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var store: DataStore
    @State private var selection: String?

    var body: some View {
        if history.records.isEmpty {
            ContentUnavailableView("Henüz oyun yok", systemImage: "clock",
                                   description: Text("Bitirdiğin oyunların özetleri burada listelenecek."))
        } else {
            HSplitView {
                List(history.records, selection: $selection) { r in
                    HStack {
                        ChampionChip(champion: store.championsById[r.championId], size: 26, showName: false)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: "\(r.kills)/\(r.deaths)/\(r.assists) · \(r.modeTitle)").font(.callout)
                            Text(r.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let win = r.win {
                            Circle().fill(win ? Color.green : Color.red).frame(width: 8, height: 8)
                                .accessibilityLabel(win ? Loc.tr("Zafer") : Loc.tr("Bozgun"))
                        }
                    }
                    .tag(r.id)
                    .contextMenu {
                        Button("Sil", role: .destructive) { history.delete([r.id]) }
                    }
                }
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
                ScrollView {
                    if let id = selection ?? history.records.first?.id, let r = history.records.first(where: { $0.id == id }) {
                        GameSummaryView(record: r).padding(20)
                    }
                }
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Geçmiş")
        }
    }
}
