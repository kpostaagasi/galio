import Foundation

extension KeyedDecodingContainer {
    /// LCU sometimes encodes "unset" ids as huge unsigned numbers or omits them; map those to 0.
    func lenientInt(_ key: Key) -> Int {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Double.self, forKey: key), v.isFinite, abs(v) < 1e15 { return Int(v) }
        return 0
    }
}

/// `/lol-champ-select/v1/session`. Deliberately does **not** decode any player identity
/// (summonerId, puuid, gameName, tagLine): Galio never needs or shows who other players are,
/// which also guarantees ranked champ-select anonymity is never resolved.
struct ChampSelectSession: Decodable, Equatable {
    struct Bans: Decodable, Equatable {
        let myTeamBans: [Int]?
        let theirTeamBans: [Int]?
    }
    struct Bench: Decodable, Equatable {
        let championId: Int
    }
    struct PhaseTimer: Decodable, Equatable {
        let phase: String?
        let adjustedTimeLeftInPhase: Double?
    }

    let localPlayerCellId: Int
    let myTeam: [ChampSelectPlayer]
    let theirTeam: [ChampSelectPlayer]
    let bans: Bans?
    let actions: [[ChampSelectAction]]
    let timer: PhaseTimer?
    let benchEnabled: Bool
    let benchChampions: [Bench]
    let isCustomGame: Bool

    enum CodingKeys: String, CodingKey {
        case localPlayerCellId, myTeam, theirTeam, bans, actions, timer, benchEnabled, benchChampions, isCustomGame
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        localPlayerCellId = c.lenientInt(.localPlayerCellId)
        myTeam = (try? c.decodeIfPresent([ChampSelectPlayer].self, forKey: .myTeam)) ?? []
        theirTeam = (try? c.decodeIfPresent([ChampSelectPlayer].self, forKey: .theirTeam)) ?? []
        bans = try? c.decodeIfPresent(Bans.self, forKey: .bans)
        actions = (try? c.decodeIfPresent([[ChampSelectAction]].self, forKey: .actions)) ?? []
        timer = try? c.decodeIfPresent(PhaseTimer.self, forKey: .timer)
        benchEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .benchEnabled)) ?? false
        benchChampions = (try? c.decodeIfPresent([Bench].self, forKey: .benchChampions)) ?? []
        isCustomGame = (try? c.decodeIfPresent(Bool.self, forKey: .isCustomGame)) ?? false
    }

    // MARK: - Derived state

    var me: ChampSelectPlayer? { myTeam.first { $0.cellId == localPlayerCellId } }

    var myPosition: Position? { Position(lcu: me?.assignedPosition) }

    /// Locked or hovered champion of the local player (0 = none).
    var myChampionId: Int {
        guard let me else { return 0 }
        return me.championId != 0 ? me.championId : me.championPickIntent
    }

    private var flatActions: [ChampSelectAction] { actions.flatMap { $0 } }

    /// True once the local player's pick action is completed (or the mode has no pick actions,
    /// e.g. ARAM, and a champion is assigned).
    var isMyPickLocked: Bool {
        let mine = flatActions.filter { $0.actorCellId == localPlayerCellId && $0.type == "pick" }
        if mine.isEmpty { return (me?.championId ?? 0) != 0 }
        return mine.contains { $0.completed && $0.championId != 0 }
    }

    var isMyTurnToPick: Bool {
        flatActions.contains { $0.actorCellId == localPlayerCellId && $0.type == "pick" && $0.isInProgress && !$0.completed }
    }

    /// Ally champions (locked or hovered) excluding the local player.
    var allyChampionIds: [Int] {
        myTeam.filter { $0.cellId != localPlayerCellId }.compactMap { p in
            let id = p.championId != 0 ? p.championId : p.championPickIntent
            return id != 0 ? id : nil
        }
    }

    /// Positions already covered by allies (from assigned positions).
    var allyPositions: [Position] {
        myTeam.filter { $0.cellId != localPlayerCellId }.compactMap { Position(lcu: $0.assignedPosition) }
    }

    /// Enemy champions that are visible to the player (locked picks only; hovers are hidden by the client).
    var visibleEnemyChampionIds: [Int] {
        theirTeam.map(\.championId).filter { $0 != 0 }
    }

    var bannedChampionIds: [Int] {
        var ids = (bans?.myTeamBans ?? []) + (bans?.theirTeamBans ?? [])
        ids += flatActions.filter { $0.type == "ban" && $0.completed }.map(\.championId)
        var seen = Set<Int>()
        return ids.filter { $0 > 0 && seen.insert($0).inserted }
    }

    /// Champions that cannot be picked anymore (picked by anyone or banned).
    var unavailableChampionIds: Set<Int> {
        Set(bannedChampionIds + myTeam.map(\.championId) + theirTeam.map(\.championId)).subtracting([0])
    }

    var benchChampionIds: [Int] { benchChampions.map(\.championId).filter { $0 != 0 } }
}

struct ChampSelectPlayer: Decodable, Equatable {
    let cellId: Int
    let championId: Int
    let championPickIntent: Int
    let assignedPosition: String?
    let spell1Id: Int
    let spell2Id: Int
    let team: Int

    enum CodingKeys: String, CodingKey {
        case cellId, championId, championPickIntent, assignedPosition, spell1Id, spell2Id, team
    }

    init(cellId: Int, championId: Int, championPickIntent: Int = 0, assignedPosition: String? = nil,
         spell1Id: Int = 0, spell2Id: Int = 0, team: Int = 1) {
        self.cellId = cellId
        self.championId = championId
        self.championPickIntent = championPickIntent
        self.assignedPosition = assignedPosition
        self.spell1Id = spell1Id
        self.spell2Id = spell2Id
        self.team = team
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cellId = c.lenientInt(.cellId)
        championId = c.lenientInt(.championId)
        championPickIntent = c.lenientInt(.championPickIntent)
        let pos = try? c.decodeIfPresent(String.self, forKey: .assignedPosition)
        assignedPosition = (pos?.isEmpty ?? true) ? nil : pos
        spell1Id = c.lenientInt(.spell1Id)
        spell2Id = c.lenientInt(.spell2Id)
        team = c.lenientInt(.team)
    }
}

struct ChampSelectAction: Decodable, Equatable {
    let id: Int
    let actorCellId: Int
    let championId: Int
    let completed: Bool
    let type: String
    let isInProgress: Bool

    enum CodingKeys: String, CodingKey {
        case id, actorCellId, championId, completed, type, isInProgress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientInt(.id)
        actorCellId = c.lenientInt(.actorCellId)
        championId = c.lenientInt(.championId)
        completed = (try? c.decodeIfPresent(Bool.self, forKey: .completed)) ?? false
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? ""
        isInProgress = (try? c.decodeIfPresent(Bool.self, forKey: .isInProgress)) ?? false
    }
}
