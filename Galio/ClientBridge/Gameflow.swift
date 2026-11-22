import Foundation

/// `/lol-gameflow/v1/gameflow-phase` values.
enum GameflowPhase: String, Codable, CaseIterable {
    case none = "None"
    case lobby = "Lobby"
    case matchmaking = "Matchmaking"
    case checkedIntoTournament = "CheckedIntoTournament"
    case readyCheck = "ReadyCheck"
    case champSelect = "ChampSelect"
    case gameStart = "GameStart"
    case failedToLaunch = "FailedToLaunch"
    case inProgress = "InProgress"
    case reconnect = "Reconnect"
    case waitingForStats = "WaitingForStats"
    case preEndOfGame = "PreEndOfGame"
    case endOfGame = "EndOfGame"
    case terminatedInError = "TerminatedInError"
    case unknown = "Unknown"

    /// The live game is running (Live Client Data API is only polled in these phases).
    var isInGame: Bool { self == .inProgress || self == .reconnect }
    var isPostGame: Bool { self == .waitingForStats || self == .preEndOfGame || self == .endOfGame }
    /// Client conveniences (rune import, item sets) are never offered during the live game.
    var allowsClientActions: Bool { !isInGame && self != .gameStart }

    var title: String {
        switch self {
        case .none: return Loc.tr("İstemci bekliyor")
        case .lobby: return Loc.tr("Lobi")
        case .matchmaking: return Loc.tr("Sıra aranıyor")
        case .checkedIntoTournament: return Loc.tr("Turnuva kaydı")
        case .readyCheck: return Loc.tr("Maç bulundu")
        case .champSelect: return Loc.tr("Şampiyon seçimi")
        case .gameStart: return Loc.tr("Oyun yükleniyor")
        case .failedToLaunch: return Loc.tr("Oyun başlatılamadı")
        case .inProgress: return Loc.tr("Oyunda")
        case .reconnect: return Loc.tr("Yeniden bağlan")
        case .waitingForStats: return Loc.tr("İstatistikler bekleniyor")
        case .preEndOfGame, .endOfGame: return Loc.tr("Oyun sonu")
        case .terminatedInError: return Loc.tr("Oyun hatayla bitti")
        case .unknown: return Loc.tr("Bilinmeyen durum")
        }
    }
}

/// `/lol-gameflow/v1/session` (only the fields Galio needs).
struct GameflowSession: Decodable, Equatable {
    struct Queue: Decodable, Equatable {
        let id: Int?
        let gameMode: String?
        let mapId: Int?
        let type: String?
        let description: String?
        let isRanked: Bool?
    }
    struct GameData: Decodable, Equatable {
        let queue: Queue?
        let isCustomGame: Bool?
        let gameId: Int64?
    }
    struct GameMap: Decodable, Equatable {
        let id: Int?
        let gameMode: String?
        let name: String?
    }

    let phase: String?
    let gameData: GameData?
    let map: GameMap?

    var mode: ModeInfo {
        ModeInfo.classify(
            gameMode: gameData?.queue?.gameMode ?? map?.gameMode,
            queueId: gameData?.queue?.id,
            mapId: gameData?.queue?.mapId ?? map?.id,
            isCustom: gameData?.isCustomGame ?? false,
            isRanked: gameData?.queue?.isRanked ?? false
        )
    }
}

enum ModeFamily: String, Codable, CaseIterable {
    case summonersRift, aram, aramMayhem, arena, urf, oneForAll, nexusBlitz, swarm, brawl, practiceTool, tutorial, other
}

/// Normalised game mode used by every advisor.
struct ModeInfo: Equatable, Codable {
    var family: ModeFamily
    var queueId: Int?
    var gameMode: String
    var mapId: Int?
    var isRanked: Bool
    var isCustom: Bool
    var isDraft: Bool

    /// Augment offers exist (ARAM Mayhem, Arena).
    var hasAugments: Bool { family == .aramMayhem || family == .arena }
    /// Lanes/positions matter (Summoner's Rift style maps).
    var usesPositions: Bool { family == .summonersRift || family == .urf || family == .oneForAll }
    /// Arena has no rune pages.
    var usesRunes: Bool { family != .arena && family != .swarm }
    /// Map id used to filter items (11 SR, 12 Howling Abyss, 30 Arena).
    var itemMap: Int {
        switch family {
        case .aram, .aramMayhem: return 12
        case .arena: return 30
        default: return mapId == 12 ? 12 : 11
        }
    }
    /// Key into the champion build table: "ARAM" for the Howling Abyss, else a position.
    var usesAramBuild: Bool { family == .aram || family == .aramMayhem || family == .arena }

    var title: String {
        var base: String
        switch family {
        case .summonersRift:
            switch queueId {
            case 420: base = Loc.tr("Dereceli Tek/Çift")
            case 440: base = Loc.tr("Dereceli Esnek")
            case 400: base = Loc.tr("Seçmeli Normal")
            case 430: base = Loc.tr("Kapalı Seçim")
            case 480, 490: base = Loc.tr("Hızlı Oyun")
            case 700: base = "Clash"
            default: base = Loc.tr("Sihirdar Vadisi")
            }
        case .aram: base = "ARAM"
        case .aramMayhem: base = "ARAM: Mayhem"
        case .arena: base = Loc.tr("Arena")
        case .urf: base = queueId == 900 ? "ARURF" : "URF"
        case .oneForAll: base = Loc.tr("Hep Birimiz Tek Birimiz")
        case .nexusBlitz: base = "Nexus Blitz"
        case .swarm: base = "Swarm"
        case .brawl: base = "Brawl"
        case .practiceTool: base = Loc.tr("Antrenman Aracı")
        case .tutorial: base = Loc.tr("Eğitim")
        case .other: base = gameMode.isEmpty ? Loc.tr("Bilinmeyen mod") : gameMode
        }
        if isCustom && family != .practiceTool { base += " · " + Loc.tr("Özel") }
        return base
    }

    static let draftQueues: Set<Int> = [400, 420, 440, 700, 3140]

    static func classify(gameMode rawMode: String?, queueId: Int?, mapId: Int?, isCustom: Bool, isRanked: Bool) -> ModeInfo {
        let mode = (rawMode ?? "").uppercased()
        let family: ModeFamily
        switch (mode, queueId ?? -1) {
        case (_, 2400), ("KIWI", _): family = .aramMayhem
        case ("CHERRY", _), (_, 1700), (_, 1710): family = .arena
        case ("ARAM", _), (_, 450), (_, 720): family = .aram
        case ("URF", _), ("ARURF", _), (_, 900), (_, 1900), (_, 1010): family = .urf
        case ("ONEFORALL", _), (_, 1020): family = .oneForAll
        case ("NEXUSBLITZ", _), (_, 1300): family = .nexusBlitz
        case ("STRAWBERRY", _): family = .swarm
        case ("BRAWL", _), (_, 2300): family = .brawl
        case ("PRACTICETOOL", _): family = .practiceTool
        case (let m, _) where m.hasPrefix("TUTORIAL"): family = .tutorial
        case ("CLASSIC", _), ("SWIFTPLAY", _): family = .summonersRift
        default:
            if mapId == 11 { family = .summonersRift }
            else if mapId == 12 { family = .aram }
            else if mapId == 30 { family = .arena }
            else { family = .other }
        }
        let draft = isRanked || draftQueues.contains(queueId ?? -1)
        return ModeInfo(family: family, queueId: queueId, gameMode: mode, mapId: mapId,
                        isRanked: isRanked, isCustom: isCustom, isDraft: draft && family == .summonersRift)
    }
}

/// League positions as used by LCU (`assignedPosition`) and by Galio's data (upper-case).
enum Position: String, CaseIterable, Codable, Identifiable {
    case top = "TOP", jungle = "JUNGLE", middle = "MIDDLE", bottom = "BOTTOM", utility = "UTILITY"

    var id: String { rawValue }

    init?(lcu value: String?) {
        guard let v = value?.uppercased(), !v.isEmpty else { return nil }
        switch v {
        case "TOP": self = .top
        case "JUNGLE": self = .jungle
        case "MIDDLE", "MID": self = .middle
        case "BOTTOM", "BOT", "ADC": self = .bottom
        case "UTILITY", "SUPPORT": self = .utility
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .top: return Loc.tr("Üst koridor")
        case .jungle: return Loc.tr("Orman")
        case .middle: return Loc.tr("Orta koridor")
        case .bottom: return Loc.tr("Alt koridor")
        case .utility: return Loc.tr("Destek")
        }
    }
}
