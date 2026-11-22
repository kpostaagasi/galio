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

/// Post-game evaluation: own numbers vs. the plan and vs. the champion's sampled averages
/// (Match-v5 aggregates for the same champion/position). Specific, number-backed notes only.
enum PostGameReview {
    static func notes(for r: GameRecord, benchmark: BuildBenchmarks? = nil,
                      itemName: (Int) -> String = { "#\($0)" }) -> [Reason] {
        var out: [Reason] = []
        let minutes = r.durationSeconds / 60
        guard minutes >= 5 else { return out }
        let sr = r.family == .summonersRift
        let support = r.position == Position.utility.rawValue
        let jungle = r.position == Position.jungle.rawValue
        let sample = benchmark.map { String($0.games) } ?? ""
        func f1(_ x: Double) -> String { String(format: "%.1f", x) }

        // Farming (laners and junglers on the Rift).
        if sr && !support && minutes >= 10 {
            let cs = r.csPerMinute
            if let b = benchmark {
                let diff = cs - b.csPerMin
                if diff <= -1.0 {
                    out.append(Reason("cs.low", Loc.tr("Dakikada %@ minyon; örneklenen %@ oyunun ortalaması %@ (−%@). Son vuruşlara ve dalga yönetimine odaklan", f1(cs), sample, f1(b.csPerMin), f1(-diff)), positive: false))
                } else if diff >= 0.8 {
                    out.append(Reason("cs.good", Loc.tr("Dakikada %@ minyon; örneklenen %@ oyunun ortalaması %@ (+%@)", f1(cs), sample, f1(b.csPerMin), f1(diff))))
                }
            } else if !jungle {
                if cs < 6 {
                    out.append(Reason("cs.low", Loc.tr("Dakikada %@ minyon, koridor hedefi olan 7'nin altında: son vuruşlara ve dalga yönetimine odaklan", f1(cs)), positive: false))
                } else if cs >= 8 {
                    out.append(Reason("cs.good", Loc.tr("Dakikada %@ minyon, koridor hedefi olan 7'nin üstünde", f1(cs))))
                }
            }
        }

        // Damage to champions vs. the sample.
        if let b = benchmark, let dmg = r.damageToChampions, b.damagePerMin > 0 {
            let dpm = Double(dmg) / minutes
            let ratio = dpm / b.damagePerMin
            if ratio < 0.75 {
                out.append(Reason("damage.low", Loc.tr("Şampiyonlara dakikada %@ hasar; ortalama %@. Savaşlara daha erken katıl ya da hasar eşyalarını öne al", String(Int(dpm)), String(Int(b.damagePerMin))), positive: false))
            } else if ratio > 1.25 {
                out.append(Reason("damage.good", Loc.tr("Şampiyonlara dakikada %@ hasar; ortalama %@", String(Int(dpm)), String(Int(b.damagePerMin)))))
            }
        }

        // Deaths.
        if let b = benchmark {
            if Double(r.deaths) >= b.deaths + 3 {
                out.append(Reason("deaths.high", Loc.tr("%@ ölüm; bu şampiyon ve rolde ortalama %@. Ölümlerin hangi bölgede olduğunu ve o anki görüşü gözden geçir", String(r.deaths), f1(b.deaths)), positive: false))
            } else if Double(r.deaths) <= max(0, b.deaths - 2) && minutes >= 15 {
                out.append(Reason("deaths.low", Loc.tr("%@ ölüm; ortalama %@", String(r.deaths), f1(b.deaths))))
            }
        } else if r.deaths >= 8 {
            out.append(Reason("deaths.high", Loc.tr("%@ ölüm (dakikada %@): riskli pozisyonları ve harita görüşünü gözden geçir", String(r.deaths), String(format: "%.2f", Double(r.deaths) / minutes)), positive: false))
        } else if r.deaths <= 2 && minutes >= 15 {
            out.append(Reason("deaths.low", Loc.tr("%@ dakikada yalnızca %@ ölüm", String(Int(minutes)), String(r.deaths))))
        }

        // Vision on the Rift.
        if sr, let vision = r.visionScore, minutes >= 10 {
            let perMin = vision / minutes
            if let b = benchmark, b.visionPerMin > 0 {
                if perMin < b.visionPerMin * 0.7 {
                    out.append(Reason("vision.low", Loc.tr("Görüş skoru dakikada %@; ortalama %@. Totemini her yenilendiğinde kullan ve Kontrol Totemi al", String(format: "%.2f", perMin), String(format: "%.2f", b.visionPerMin)), positive: false))
                }
            } else {
                let target = support ? 1.5 : 0.7
                if perMin < target {
                    out.append(Reason("vision.low", Loc.tr("Görüş skoru dakikada %@, hedef %@: daha sık totem ve Kontrol Totemi kullan", String(format: "%.2f", perMin), f1(target)), positive: false))
                }
            }
        }

        // Build vs. plan (the plan is the popular core when sampled, otherwise the curated core).
        let planned = Array(r.plannedCore.prefix(3))
        if !planned.isEmpty && minutes >= 20 {
            let missing = planned.filter { !r.items.contains($0) }.map(itemName)
            let done = planned.count - missing.count
            if done >= 2 {
                if missing.isEmpty {
                    out.append(Reason("plan.followed", Loc.tr("Planlanan temel eşyaların %@/%@'ünü tamamladın", String(done), String(planned.count))))
                } else {
                    out.append(Reason("plan.followed", Loc.tr("Planlanan temel eşyaların %@/%@'ünü tamamladın; eksik: %@", String(done), String(planned.count), missing.joined(separator: ", "))))
                }
            } else {
                out.append(Reason("plan.diverged", Loc.tr("Planlanan temel eşyalardan %@/%@ tamamlandı; eksik: %@. Rakibe göre uyarladıysan sorun değil", String(done), String(planned.count), missing.joined(separator: ", ")), positive: false))
            }
        }

        // Gold income vs. the sample.
        if let b = benchmark, let gold = r.goldEarned, b.goldPerMin > 0 {
            let gpm = Double(gold) / minutes
            if gpm < b.goldPerMin * 0.8 {
                out.append(Reason("gold.low", Loc.tr("Dakikada %@ altın; ortalama %@. Boş anlarda yakındaki dalgaları ve kampları topla", String(Int(gpm)), String(Int(b.goldPerMin))), positive: false))
            }
        }
        return out
    }

    /// Sampled averages for the record's champion/position (ARAM uses the ARAM build).
    @MainActor
    static func benchmark(for r: GameRecord, store: DataStore) -> BuildBenchmarks? {
        guard let champion = store.championsById[r.championId] ?? store.champion(key: r.championKey),
              let detail = store.detail(for: champion) else { return nil }
        let key: String?
        switch r.family {
        case .summonersRift: key = r.position
        case .aram: key = "ARAM"
        default: key = nil
        }
        guard let key else { return nil }
        return detail.builds[key]?.benchmarks
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
