import Foundation

/// Riot Live Client Data API (`https://127.0.0.1:2999/liveclientdata/allgamedata`).
/// Everything here is information the player can already see on the scoreboard. Galio never
/// reads, stores or shows other players' names from it — only champions, levels and items.
struct LiveGameData: Decodable, Equatable {
    let activePlayer: LiveActivePlayer?
    let allPlayers: [LivePlayer]
    let gameData: LiveGameInfo

    /// The local player's scoreboard entry.
    var me: LivePlayer? {
        guard let active = activePlayer else { return nil }
        if let id = active.riotId, !id.isEmpty, let p = allPlayers.first(where: { $0.riotId == id }) { return p }
        if let name = active.summonerName, !name.isEmpty,
           let p = allPlayers.first(where: { $0.summonerName == name || $0.riotIdGameName == name }) { return p }
        return nil
    }

    var myTeam: String? { me?.team }

    var allies: [LivePlayer] {
        guard let me else { return [] }
        return allPlayers.filter { $0.team == me.team && $0 != me }
    }

    var enemies: [LivePlayer] {
        guard let me else { return [] }
        return allPlayers.filter { $0.team != me.team }
    }

    var mode: ModeInfo {
        ModeInfo.classify(gameMode: gameData.gameMode, queueId: nil, mapId: gameData.mapNumber,
                          isCustom: false, isRanked: false)
    }
}

struct LiveActivePlayer: Decodable, Equatable {
    struct Abilities: Decodable, Equatable {
        let Q: LiveAbility?
        let W: LiveAbility?
        let E: LiveAbility?
        let R: LiveAbility?
    }
    let riotId: String?
    let summonerName: String?
    let level: Int
    let currentGold: Double
    let abilities: Abilities?

    enum CodingKeys: String, CodingKey { case riotId, summonerName, level, currentGold, abilities }

    init(riotId: String?, summonerName: String?, level: Int, currentGold: Double, abilities: Abilities?) {
        self.riotId = riotId
        self.summonerName = summonerName
        self.level = level
        self.currentGold = currentGold
        self.abilities = abilities
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        riotId = try? c.decodeIfPresent(String.self, forKey: .riotId)
        summonerName = try? c.decodeIfPresent(String.self, forKey: .summonerName)
        level = c.lenientInt(.level)
        currentGold = (try? c.decodeIfPresent(Double.self, forKey: .currentGold)) ?? 0
        abilities = try? c.decodeIfPresent(Abilities.self, forKey: .abilities)
    }

    /// Current rank of Q/W/E/R (0 when unknown).
    func abilityLevel(_ key: String) -> Int {
        switch key {
        case "Q": return abilities?.Q?.abilityLevel ?? 0
        case "W": return abilities?.W?.abilityLevel ?? 0
        case "E": return abilities?.E?.abilityLevel ?? 0
        case "R": return abilities?.R?.abilityLevel ?? 0
        default: return 0
        }
    }
}

struct LiveAbility: Decodable, Equatable {
    let abilityLevel: Int?
    let displayName: String?
}

struct LivePlayer: Decodable, Equatable {
    let championName: String
    let rawChampionName: String?
    let riotId: String?
    let riotIdGameName: String?
    let summonerName: String?
    let team: String
    let level: Int
    let isBot: Bool
    let isDead: Bool
    let position: String?
    let items: [LiveItem]
    let scores: LiveScores

    enum CodingKeys: String, CodingKey {
        case championName, rawChampionName, riotId, riotIdGameName, summonerName, team, level, isBot, isDead, position, items, scores
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        championName = (try? c.decodeIfPresent(String.self, forKey: .championName)) ?? ""
        rawChampionName = try? c.decodeIfPresent(String.self, forKey: .rawChampionName)
        riotId = try? c.decodeIfPresent(String.self, forKey: .riotId)
        riotIdGameName = try? c.decodeIfPresent(String.self, forKey: .riotIdGameName)
        summonerName = try? c.decodeIfPresent(String.self, forKey: .summonerName)
        team = (try? c.decodeIfPresent(String.self, forKey: .team)) ?? ""
        level = c.lenientInt(.level)
        isBot = (try? c.decodeIfPresent(Bool.self, forKey: .isBot)) ?? false
        isDead = (try? c.decodeIfPresent(Bool.self, forKey: .isDead)) ?? false
        position = try? c.decodeIfPresent(String.self, forKey: .position)
        items = (try? c.decodeIfPresent([LiveItem].self, forKey: .items)) ?? []
        scores = (try? c.decodeIfPresent(LiveScores.self, forKey: .scores)) ?? LiveScores()
    }

    /// Data Dragon champion id derived from `rawChampionName`
    /// (`game_character_displayname_MonkeyKing` → `MonkeyKing`).
    var championDataId: String? {
        guard let raw = rawChampionName, let range = raw.range(of: "game_character_displayname_") else { return nil }
        let id = String(raw[range.upperBound...])
        return id.isEmpty ? nil : id
    }

    var itemIds: [Int] { items.map(\.itemID) }
}

struct LiveItem: Decodable, Equatable {
    let itemID: Int
    let displayName: String?
    let count: Int?
    let slot: Int?
    let price: Int?
}

struct LiveScores: Decodable, Equatable {
    var kills = 0
    var deaths = 0
    var assists = 0
    var creepScore = 0
    var wardScore = 0.0

    enum CodingKeys: String, CodingKey { case kills, deaths, assists, creepScore, wardScore }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kills = c.lenientInt(.kills)
        deaths = c.lenientInt(.deaths)
        assists = c.lenientInt(.assists)
        creepScore = c.lenientInt(.creepScore)
        wardScore = (try? c.decodeIfPresent(Double.self, forKey: .wardScore)) ?? 0
    }
}

struct LiveGameInfo: Decodable, Equatable {
    let gameMode: String
    let gameTime: Double
    let mapNumber: Int?
    let mapName: String?
}

/// Polls the Live Client Data API. Only called while the gameflow phase is InProgress.
struct LiveClient {
    var baseURL = URL(string: "https://127.0.0.1:2999")!
    var session: URLSession = RiotSession.shared

    func allGameData() async throws -> LiveGameData {
        let url = baseURL.appendingPathComponent("liveclientdata/allgamedata")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LCUError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: "")
        }
        return try JSONDecoder().decode(LiveGameData.self, from: data)
    }
}
