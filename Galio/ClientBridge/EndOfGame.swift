import Foundation

/// `/lol-end-of-game/v1/eog-stats-block`, reduced to the local player's own numbers.
/// Teammates' and opponents' entries are intentionally not decoded.
struct EndOfGameStats: Decodable, Equatable {
    struct LocalPlayer: Decodable, Equatable {
        let championId: Int
        let stats: [String: Double]
        let items: [Int]

        enum CodingKeys: String, CodingKey { case championId, stats, items }

        init(championId: Int, stats: [String: Double], items: [Int]) {
            self.championId = championId
            self.stats = stats
            self.items = items
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            championId = c.lenientInt(.championId)
            if let s = try? c.decodeIfPresent([String: Double].self, forKey: .stats) {
                stats = s
            } else if let raw = try? c.decodeIfPresent([String: LenientNumber].self, forKey: .stats) {
                stats = raw.compactMapValues(\.value)
            } else {
                stats = [:]
            }
            items = ((try? c.decodeIfPresent([Int].self, forKey: .items)) ?? []).filter { $0 > 0 }
        }
    }

    let gameId: Int64
    let gameLength: Double
    let gameMode: String
    let localPlayer: LocalPlayer?

    enum CodingKeys: String, CodingKey { case gameId, gameLength, gameMode, localPlayer }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gameId = (try? c.decodeIfPresent(Int64.self, forKey: .gameId)) ?? 0
        gameLength = (try? c.decodeIfPresent(Double.self, forKey: .gameLength)) ?? 0
        gameMode = (try? c.decodeIfPresent(String.self, forKey: .gameMode)) ?? ""
        localPlayer = try? c.decodeIfPresent(LocalPlayer.self, forKey: .localPlayer)
    }

    func stat(_ key: String) -> Double { localPlayer?.stats[key] ?? 0 }
}

/// Decodes numbers or numeric strings, ignores anything else.
struct LenientNumber: Decodable, Equatable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let b = try? c.decode(Bool.self) { value = b ? 1 : 0 }
        else if let s = try? c.decode(String.self) { value = Double(s) }
        else { value = nil }
    }
}
