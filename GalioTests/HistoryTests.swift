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
        // The plan is the data set's core for the position (Match-v5 popular core or curated); it changes with data.
        XCTAssertEqual(r.plannedCore, store.detail(for: TestData.champion("Galio"))?.build(for: "MIDDLE")?.items.core)
        XCTAssertEqual(r.coreFollowed, r.plannedCore.prefix(3).filter { r.items.contains($0) }.count)
        XCTAssertGreaterThanOrEqual(r.coreFollowed, 1, "Zhonya's Hourglass is in the fixture inventory and in every Galio core")
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
        XCTAssertTrue(good.isSuperset(of: ["cs.good", "deaths.low", "plan.followed"]))
    }

    func testReviewNotesAgainstSampleAverages() {
        let r = GameRecord(id: "2", date: Date(), modeTitle: "Ranked", family: .summonersRift, championKey: 3, championId: "Galio",
                           position: "MIDDLE", win: false, kills: 2, deaths: 7, assists: 5, creepScore: 180, durationSeconds: 1800,
                           damageToChampions: 12000, goldEarned: 9000, visionScore: 12, items: [6664, 3157], plannedCore: [6664, 4633, 3157])
        let b = BuildBenchmarks(games: 240, csPerMin: 7.4, damagePerMin: 780, visionPerMin: 0.9, goldPerMin: 410, deaths: 3.8)
        let notes = PostGameReview.notes(for: r, benchmark: b) { $0 == 4633 ? "Riftmaker" : "#\($0)" }
        let byCode = Dictionary(notes.map { ($0.code, $0.text) }, uniquingKeysWith: { a, _ in a })
        XCTAssertNotNil(byCode["cs.low"], "6.0 CS/min vs a 7.4 sample average")
        XCTAssertTrue(byCode["cs.low"]?.contains("240") ?? false, "the note names the sample size")
        XCTAssertNotNil(byCode["damage.low"], "400 vs 780 damage per minute")
        XCTAssertNotNil(byCode["deaths.high"], "7 deaths vs 3.8 average")
        XCTAssertNotNil(byCode["vision.low"])
        XCTAssertNotNil(byCode["gold.low"], "300 vs 410 gold per minute")
        XCTAssertTrue(byCode["plan.followed"]?.contains("Riftmaker") ?? false, "the missing planned item is named")
        XCTAssertFalse(notes.contains { $0.text.lowercased().contains("win") || $0.text.contains("kazanma") }, "no win rates")
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
