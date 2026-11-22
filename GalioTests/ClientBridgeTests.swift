import XCTest
@testable import Galio

final class ClientBridgeTests: XCTestCase {
    // MARK: Gameflow / modes

    func testGameflowPhaseRawValues() {
        XCTAssertEqual(GameflowPhase(rawValue: "ChampSelect"), .champSelect)
        XCTAssertEqual(GameflowPhase(rawValue: "InProgress"), .inProgress)
        XCTAssertTrue(GameflowPhase.inProgress.isInGame)
        XCTAssertFalse(GameflowPhase.inProgress.allowsClientActions)
        XCTAssertTrue(GameflowPhase.champSelect.allowsClientActions)
        XCTAssertTrue(GameflowPhase.endOfGame.isPostGame)
    }

    func testRankedSessionClassifiesAsDraftRift() throws {
        let s = try Fixture.decode(GameflowSession.self, "gameflow-session-ranked.json")
        let m = s.mode
        XCTAssertEqual(m.family, .summonersRift)
        XCTAssertEqual(m.queueId, 420)
        XCTAssertTrue(m.isRanked)
        XCTAssertTrue(m.isDraft)
        XCTAssertTrue(m.usesPositions)
        XCTAssertFalse(m.hasAugments)
        XCTAssertEqual(m.itemMap, 11)
    }

    func testMayhemAndArenaClassification() throws {
        let mayhem = try Fixture.decode(GameflowSession.self, "gameflow-session-mayhem.json").mode
        XCTAssertEqual(mayhem.family, .aramMayhem)
        XCTAssertTrue(mayhem.hasAugments)
        XCTAssertEqual(mayhem.itemMap, 12)
        let arena = try Fixture.decode(GameflowSession.self, "gameflow-session-arena.json").mode
        XCTAssertEqual(arena.family, .arena)
        XCTAssertTrue(arena.hasAugments)
        XCTAssertFalse(arena.usesRunes)
        XCTAssertEqual(arena.itemMap, 30)
        let practice = try Fixture.decode(GameflowSession.self, "gameflow-session-custom.json").mode
        XCTAssertEqual(practice.family, .practiceTool)
    }

    func testModeClassifierCoversAllFamilies() {
        func fam(_ mode: String?, _ q: Int?, _ map: Int? = nil) -> ModeFamily {
            ModeInfo.classify(gameMode: mode, queueId: q, mapId: map, isCustom: false, isRanked: false).family
        }
        XCTAssertEqual(fam("CLASSIC", 400), .summonersRift)
        XCTAssertEqual(fam("CLASSIC", 430), .summonersRift)
        XCTAssertEqual(fam("SWIFTPLAY", 480), .summonersRift)
        XCTAssertEqual(fam("ARAM", 450), .aram)
        XCTAssertEqual(fam("ARAM", 2400), .aramMayhem)
        XCTAssertEqual(fam("KIWI", nil), .aramMayhem)
        XCTAssertEqual(fam("CHERRY", 1700), .arena)
        XCTAssertEqual(fam("URF", 1900), .urf)
        XCTAssertEqual(fam("ARURF", 900), .urf)
        XCTAssertEqual(fam("ONEFORALL", 1020), .oneForAll)
        XCTAssertEqual(fam("PRACTICETOOL", nil), .practiceTool)
        XCTAssertEqual(fam("TUTORIAL_MODULE_1", nil), .tutorial)
        XCTAssertEqual(fam("STRAWBERRY", nil), .swarm)
        XCTAssertEqual(fam(nil, nil, 12), .aram)
        XCTAssertEqual(fam("SOMETHINGNEW", nil), .other)
        XCTAssertTrue(ModeInfo.classify(gameMode: "CLASSIC", queueId: 400, mapId: 11, isCustom: false, isRanked: false).isDraft)
        XCTAssertFalse(ModeInfo.classify(gameMode: "CLASSIC", queueId: 430, mapId: 11, isCustom: false, isRanked: false).isDraft)
    }

    func testPositionParsing() {
        XCTAssertEqual(Position(lcu: "middle"), .middle)
        XCTAssertEqual(Position(lcu: "utility"), .utility)
        XCTAssertEqual(Position(lcu: "BOTTOM"), .bottom)
        XCTAssertNil(Position(lcu: ""))
        XCTAssertNil(Position(lcu: nil))
    }

    // MARK: Champ select

    func testChampSelectWhilePicking() throws {
        let cs = try Fixture.decode(ChampSelectSession.self, "champselect-picking.json")
        XCTAssertEqual(cs.localPlayerCellId, 2)
        XCTAssertEqual(cs.myPosition, .middle)
        XCTAssertEqual(cs.myChampionId, 0)
        XCTAssertFalse(cs.isMyPickLocked)
        XCTAssertTrue(cs.isMyTurnToPick)
        XCTAssertEqual(Set(cs.allyChampionIds), [86, 64, 222, 412]) // locked + hovered allies
        XCTAssertEqual(cs.visibleEnemyChampionIds, [54, 254, 238])
        XCTAssertEqual(cs.bannedChampionIds.count, 10)
        XCTAssertTrue(cs.unavailableChampionIds.contains(157))
        XCTAssertTrue(cs.unavailableChampionIds.contains(54))
    }

    func testChampSelectLocked() throws {
        let cs = try Fixture.decode(ChampSelectSession.self, "champselect-locked.json")
        XCTAssertEqual(cs.myChampionId, 3)
        XCTAssertTrue(cs.isMyPickLocked)
        XCTAssertFalse(cs.isMyTurnToPick)
        XCTAssertEqual(cs.visibleEnemyChampionIds.count, 5)
    }

    func testAramChampSelectHasBenchAndNoActions() throws {
        let cs = try Fixture.decode(ChampSelectSession.self, "champselect-aram.json")
        XCTAssertTrue(cs.benchEnabled)
        XCTAssertEqual(cs.benchChampionIds, [103, 61, 21])
        XCTAssertEqual(cs.myChampionId, 99)
        XCTAssertTrue(cs.isMyPickLocked)
        XCTAssertNil(cs.myPosition)
    }

    func testChampSelectToleratesHugeUnsignedIds() throws {
        let json = #"{"localPlayerCellId":0,"myTeam":[{"cellId":0,"championId":3,"spell1Id":18446744073709551615,"spell2Id":4}],"theirTeam":[],"actions":[]}"#
        let cs = try JSONDecoder().decode(ChampSelectSession.self, from: Data(json.utf8))
        XCTAssertEqual(cs.me?.spell1Id, 0)
        XCTAssertEqual(cs.me?.spell2Id, 4)
    }

    // MARK: Live client

    func testLiveClientSummonersRift() throws {
        let live = try Fixture.decode(LiveGameData.self, "liveclient-sr.json")
        let me = try XCTUnwrap(live.me)
        XCTAssertEqual(me.championName, "Galio")
        XCTAssertEqual(me.championDataId, "Galio")
        XCTAssertEqual(live.allies.count, 4)
        XCTAssertEqual(live.enemies.count, 5)
        XCTAssertEqual(live.activePlayer?.level, 9)
        XCTAssertEqual(live.activePlayer?.abilityLevel("Q"), 4)
        XCTAssertEqual(live.mode.family, .summonersRift)
        XCTAssertEqual(me.itemIds.first, 1056)
        XCTAssertEqual(me.scores.creepScore, 98)
    }

    func testLiveClientMayhemAndArena() throws {
        let mayhem = try Fixture.decode(LiveGameData.self, "liveclient-mayhem.json")
        XCTAssertEqual(mayhem.mode.family, .aramMayhem)
        XCTAssertEqual(mayhem.me?.championDataId, "Lux")
        let arena = try Fixture.decode(LiveGameData.self, "liveclient-arena.json")
        XCTAssertEqual(arena.mode.family, .arena)
        XCTAssertEqual(arena.allies.count, 1)
        XCTAssertEqual(arena.enemies.count, 2)
    }

    func testEndOfGameStats() throws {
        let eog = try Fixture.decode(EndOfGameStats.self, "eog-stats-block.json")
        XCTAssertEqual(eog.localPlayer?.championId, 3)
        XCTAssertEqual(eog.stat("CHAMPIONS_KILLED"), 5)
        XCTAssertEqual(eog.stat("MINIONS_KILLED"), 182)
        XCTAssertEqual(eog.gameLength, 1835)
        XCTAssertFalse(eog.localPlayer?.items.contains(0) ?? true)
    }

    // MARK: WebSocket events

    func testWebSocketEventParsing() throws {
        let lines = try String(contentsOf: Fixture.url("ws-events.txt"), encoding: .utf8).split(separator: "\n")
        let phase = try XCTUnwrap(LCUEvent.parse(String(lines[0])))
        XCTAssertEqual(phase.uri, "/lol-gameflow/v1/gameflow-phase")
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: XCTUnwrap(phase.data)), "ChampSelect")
        let del = try XCTUnwrap(LCUEvent.parse(String(lines[1])))
        XCTAssertEqual(del.eventType, "Delete")
        XCTAssertNil(del.data)
        XCTAssertNil(LCUEvent.parse("[5,\"OnJsonApiEvent\"]"))
        XCTAssertNil(LCUEvent.parse("garbage"))
    }

    func testSocketURL() {
        let ep = LCUEndpoint(baseURL: URL(string: "https://127.0.0.1:54321")!, authorization: nil)
        XCTAssertEqual(LCUWebSocket.socketURL(for: ep)?.absoluteString, "wss://127.0.0.1:54321/")
    }

    // MARK: TLS + process args

    func testRiotRootCertificateIsBundled() {
        XCTAssertNotNil(RiotTLSDelegate.loadRiotRoot(), "riotgames.pem must be bundled and parseable")
        XCTAssertTrue(RiotTLSDelegate.isLoopback("127.0.0.1"))
        XCTAssertFalse(RiotTLSDelegate.isLoopback("ddragon.leagueoflegends.com"))
    }

    func testProcessArgsParsing() throws {
        let line = "/Applications/League of Legends.app/Contents/LoL/LeagueClient.app/Contents/Frameworks/LeagueClientUx.app/Contents/MacOS/LeagueClientUx --riotclient-auth-token=x --app-port=61234 --remoting-auth-token=abc123 --locale=tr_TR"
        let ep = try XCTUnwrap(ProcessArgsLocator.parse(commandLine: line))
        XCTAssertEqual(ep.port, 61234)
        XCTAssertEqual(ep.authorization, "Basic " + Data("riot:abc123".utf8).base64EncodedString())
        XCTAssertNil(ProcessArgsLocator.parse(commandLine: "/usr/bin/some-other --app-port=1"))
    }
}
