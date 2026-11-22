import XCTest
@testable import Galio

final class HistoryTests: XCTestCase {
    @MainActor
    func testRecordFromEndOfGameBlock() throws {
        let store = TestData.store()
        let eog = try Fixture.decode(EndOfGameStats.self, "eog-stats-block.json")
        let mode = ModeInfo.classify(gameMode: "CLASSIC", queueId: 420, mapId: 11, isCustom: false, isRanked: true)
        let r = try XCTUnwrap(HistoryStore.makeRecord(eog: eog, live: nil, mode: mode, position: .middle, store: store))
        XCTAssertEqual(r.id, "7300000420")
        XCTAssertEqual(r.championId, "Galio")
        XCTAssertEqual(r.kills, 5)
        XCTAssertEqual(r.deaths, 3)
        XCTAssertEqual(r.assists, 14)
        XCTAssertEqual(r.creepScore, 190)
        XCTAssertEqual(r.win, true)
        XCTAssertEqual(r.damageToChampions, 24850)
        XCTAssertEqual(r.csPerMinute, 190.0 / (1835.0 / 60.0), accuracy: 0.01)
        XCTAssertFalse(r.plannedCore.isEmpty)
        XCTAssertGreaterThanOrEqual(r.coreFollowed, 2, "fixture items include Hollow Radiance, Riftmaker and Zhonya's")
    }

    @MainActor
    func testRecordFromLiveSnapshotOnly() throws {
        let store = TestData.store()
        let live = try Fixture.decode(LiveGameData.self, "liveclient-sr.json")
        let r = try XCTUnwrap(HistoryStore.makeRecord(eog: nil, live: live, mode: nil, position: nil, store: store))
        XCTAssertEqual(r.championId, "Galio")
        XCTAssertEqual(r.kills, 2)
        XCTAssertEqual(r.creepScore, 98)
        XCTAssertNil(r.win)
        XCTAssertTrue(r.id.hasPrefix("Galio-"))
    }

    func testReviewNotes() {
        var r = GameRecord(id: "1", date: Date(), modeTitle: "Ranked", family: .summonersRift, championKey: 3, championId: "Galio",
                           position: "MIDDLE", win: false, kills: 1, deaths: 9, assists: 2, creepScore: 120, durationSeconds: 1800,
                           damageToChampions: 9000, goldEarned: 8000, visionScore: 8, items: [3157], plannedCore: [6664, 4633, 3157])
        let codes = Set(PostGameReview.notes(for: r).map(\.code))
        XCTAssertTrue(codes.contains("cs.low"))
        XCTAssertTrue(codes.contains("deaths.high"))
        XCTAssertTrue(codes.contains("vision.low"))
        XCTAssertTrue(codes.contains("plan.diverged"))
        r.creepScore = 260; r.deaths = 1; r.kills = 8; r.assists = 6; r.items = [6664, 4633, 3157]
        let good = Set(PostGameReview.notes(for: r).map(\.code))
        XCTAssertTrue(good.isSuperset(of: ["cs.good", "deaths.low", "plan.followed", "kda.good"]))
    }

    @MainActor
    func testHistoryPersistsAndDedupes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("galio-history-\(UUID().uuidString).json")
        let store = HistoryStore(url: url)
        let r = GameRecord(id: "42", date: Date(), modeTitle: "ARAM", family: .aram, championKey: 99, championId: "Lux",
                           position: nil, win: true, kills: 10, deaths: 4, assists: 20, creepScore: 60, durationSeconds: 1200,
                           damageToChampions: nil, goldEarned: nil, visionScore: nil, items: [], plannedCore: [])
        store.upsert(r)
        store.upsert(r)
        XCTAssertEqual(store.records.count, 1)
        let reloaded = HistoryStore(url: url)
        XCTAssertEqual(reloaded.records.first?.championId, "Lux")
        reloaded.delete(["42"])
        XCTAssertTrue(reloaded.records.isEmpty)
    }
}
