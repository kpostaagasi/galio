import Foundation

/// One finished game, the local player's own numbers only.
struct GameRecord: Codable, Identifiable, Equatable {
    var id: String
    var date: Date
    var modeTitle: String
    var family: ModeFamily
    var championKey: Int
    var championId: String
    var position: String?
    var win: Bool?
    var kills: Int
    var deaths: Int
    var assists: Int
    var creepScore: Int
    var durationSeconds: Double
    var damageToChampions: Int?
    var goldEarned: Int?
    var visionScore: Double?
    var items: [Int]
    var plannedCore: [Int]

    var csPerMinute: Double { durationSeconds > 60 ? Double(creepScore) / (durationSeconds / 60) : 0 }
    var kda: Double { Double(kills + assists) / Double(max(1, deaths)) }
    /// How many of the planned first three core items ended up in the final inventory.
    var coreFollowed: Int { plannedCore.prefix(3).filter { items.contains($0) }.count }
}

/// Post-game evaluation: own performance vs. the plan, plus short learning notes.
enum PostGameReview {
    static func notes(for r: GameRecord) -> [Reason] {
        var out: [Reason] = []
        let laner = r.family == .summonersRift && r.position != Position.utility.rawValue && r.position != Position.jungle.rawValue
        if laner && r.durationSeconds > 600 {
            if r.csPerMinute < 6 {
                out.append(Reason("cs.low", Loc.tr("Dakika başı minyon %@: dalga yönetimine ve son vuruşlara odaklan", String(format: "%.1f", r.csPerMinute)), positive: false))
            } else if r.csPerMinute >= 8 {
                out.append(Reason("cs.good", Loc.tr("Dakika başı %@ minyon: çok iyi farm", String(format: "%.1f", r.csPerMinute))))
            }
        }
        if r.deaths >= 8 {
            out.append(Reason("deaths.high", Loc.tr("%@ ölüm: riskli pozisyonları ve harita görüşünü gözden geçir", String(r.deaths)), positive: false))
        } else if r.deaths <= 2 && r.durationSeconds > 900 {
            out.append(Reason("deaths.low", Loc.tr("Az ölümle oynadın, güvenli oyun")))
        }
        if r.family == .summonersRift, let vision = r.visionScore, r.durationSeconds > 600 {
            let perMin = vision / (r.durationSeconds / 60)
            let target = r.position == Position.utility.rawValue ? 1.5 : 0.7
            if perMin < target {
                out.append(Reason("vision.low", Loc.tr("Görüş skoru düşük: daha sık totem ve Kontrol Totemi kullan"), positive: false))
            }
        }
        if !r.plannedCore.isEmpty && r.durationSeconds > 1200 {
            if r.coreFollowed >= 2 {
                out.append(Reason("plan.followed", Loc.tr("Planlanan temel eşyaların %@/3'ünü tamamladın", String(r.coreFollowed))))
            } else {
                out.append(Reason("plan.diverged", Loc.tr("Plandan farklı eşyalar aldın (%@/3); rakibe göre uyarlama yaptıysan sorun değil", String(r.coreFollowed)), positive: false))
            }
        }
        if r.kda >= 4 {
            out.append(Reason("kda.good", Loc.tr("KDA %@: etkili bir oyun", String(format: "%.1f", r.kda))))
        }
        return out
    }
}

/// Local history of finished games (Application Support/Galio/history.json, newest first).
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    static let limit = 200

    @Published private(set) var records: [GameRecord] = []
    private let url: URL

    init(url: URL = AppPaths.support.appendingPathComponent("history.json")) {
        self.url = url
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([GameRecord].self, from: data)) ?? []
    }

    func upsert(_ record: GameRecord) {
        if let i = records.firstIndex(where: { $0.id == record.id }) {
            records[i] = record
        } else {
            records.insert(record, at: 0)
        }
        records = Array(records.sorted { $0.date > $1.date }.prefix(Self.limit))
        save()
    }

    func delete(_ ids: Set<String>) {
        records.removeAll { ids.contains($0.id) }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) { try? data.write(to: url, options: .atomic) }
    }

    /// Builds a record from the end-of-game block (preferred) and/or the last live snapshot.
    static func makeRecord(eog: EndOfGameStats?, live: LiveGameData?, mode: ModeInfo?, position: Position?,
                           store: DataStore, now: Date = Date()) -> GameRecord? {
        let liveMe = live?.me
        var champion: ChampionInfo?
        if let key = eog?.localPlayer?.championId, key != 0 { champion = store.champion(key: key) }
        if champion == nil, let me = liveMe { champion = store.champion(liveId: me.championDataId, name: me.championName) }
        guard let champion else { return nil }
        let m = mode ?? live?.mode ?? ModeInfo.classify(gameMode: eog?.gameMode, queueId: nil, mapId: nil, isCustom: false, isRanked: false)
        let duration = eog.map { $0.gameLength } ?? live?.gameData.gameTime ?? 0
        let key = AdviceBuilder.buildKey(mode: m, position: position, champion: champion)
        let planned = store.detail(for: champion)?.build(for: key)?.items.core ?? []
        var r = GameRecord(
            id: eog.map { $0.gameId != 0 ? String($0.gameId) : "" } ?? "",
            date: now, modeTitle: m.title, family: m.family, championKey: champion.key, championId: champion.id,
            position: position?.rawValue, win: nil,
            kills: liveMe?.scores.kills ?? 0, deaths: liveMe?.scores.deaths ?? 0, assists: liveMe?.scores.assists ?? 0,
            creepScore: liveMe?.scores.creepScore ?? 0, durationSeconds: duration,
            damageToChampions: nil, goldEarned: nil, visionScore: liveMe.map { $0.scores.wardScore },
            items: liveMe?.itemIds ?? [], plannedCore: planned)
        if let eog, eog.localPlayer != nil {
            r.kills = Int(eog.stat("CHAMPIONS_KILLED"))
            r.deaths = Int(eog.stat("NUM_DEATHS"))
            r.assists = Int(eog.stat("ASSISTS"))
            r.creepScore = Int(eog.stat("MINIONS_KILLED") + eog.stat("NEUTRAL_MINIONS_KILLED"))
            r.damageToChampions = Int(eog.stat("TOTAL_DAMAGE_DEALT_TO_CHAMPIONS"))
            r.goldEarned = Int(eog.stat("GOLD_EARNED"))
            if eog.localPlayer?.stats["VISION_SCORE"] != nil { r.visionScore = eog.stat("VISION_SCORE") }
            if eog.localPlayer?.stats["WIN"] != nil { r.win = eog.stat("WIN") > 0 }
            if let items = eog.localPlayer?.items, !items.isEmpty { r.items = items }
        }
        if r.id.isEmpty {
            r.id = "\(champion.id)-\(Int(now.timeIntervalSince1970))"
        }
        return r
    }
}
