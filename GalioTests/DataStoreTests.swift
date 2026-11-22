import XCTest
@testable import Galio

final class DataStoreTests: XCTestCase {
    func testBundledDataSetDecodes() {
        let set = TestData.set
        XCTAssertEqual(set.schema, DataStore.supportedSchema)
        XCTAssertGreaterThan(set.champions.count, 160)
        XCTAssertEqual(set.details.count, set.champions.count)
        XCTAssertGreaterThan(set.items.count, 200)
        XCTAssertEqual(set.runes.styles.count, 5)
        XCTAssertNotNil(set.augments["MAYHEM"])
        XCTAssertNotNil(set.augments["ARENA"])
    }

    func testEveryChampionHasBuildsAndValidSkillOrder() {
        for c in TestData.set.champions {
            guard let d = TestData.set.details[c.id] else { return XCTFail("no detail for \(c.id)") }
            XCTAssertEqual(Set(d.skillOrder.max), ["Q", "W", "E"], c.id)
            XCTAssertNotNil(d.builds["ARAM"], c.id)
            for pos in c.positions { XCTAssertNotNil(d.builds[pos], "\(c.id) \(pos)") }
            for (key, b) in d.builds {
                XCTAssertFalse(b.items.core.isEmpty, "\(c.id) \(key) has no core items")
                for page in b.runes { XCTAssertEqual(page.perkIds.count, 9, "\(c.id) \(key)") }
            }
        }
    }

    func testPatchComparison() {
        XCTAssertTrue(PatchVersion.isNewer("16.24.1", than: "16.23.1"))
        XCTAssertTrue(PatchVersion.isNewer("17.1.1", than: "16.24.1"))
        XCTAssertFalse(PatchVersion.isNewer("16.23.1", than: "16.23.1"))
        XCTAssertFalse(PatchVersion.isNewer("16.9.1", than: "16.10.1"))
    }

    @MainActor
    func testLookups() {
        let store = TestData.store()
        XCTAssertEqual(store.champion(key: 3)?.id, "Galio")
        XCTAssertEqual(store.champion(liveId: "MonkeyKing", name: "Wukong")?.key, 62)
        XCTAssertEqual(store.champion(liveId: nil, name: "Lee Sin")?.id, "LeeSin")
        XCTAssertNotNil(store.itemsById[3157])
        XCTAssertNotNil(store.runesById[8010])
        XCTAssertNotNil(store.summonersById[4])
        let mayhem = ModeInfo.classify(gameMode: "KIWI", queueId: 2400, mapId: 12, isCustom: false, isRanked: false)
        XCTAssertGreaterThan(store.augments(for: mayhem).count, 100)
    }

    func testCachedNewerDataWinsOverBundled() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("galio-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundledURL = try XCTUnwrap(Bundle.main.url(forResource: "all", withExtension: "json", subdirectory: "BundledData"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bundledURL)) as? [String: Any])
        json["patch"] = "99.1.1"
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("all.json"))
        let best = try XCTUnwrap(DataStore.loadBest(cacheDir: dir, bundle: .main))
        XCTAssertEqual(best.0.patch, "99.1.1")
        XCTAssertEqual(best.1, .cache)
    }

    func testImageCacheFileNamesAreStable() {
        let url = URL(string: "https://ddragon.leagueoflegends.com/cdn/16.23.1/img/champion/Galio.png")!
        XCTAssertEqual(ImageCache.fileName(for: url), ImageCache.fileName(for: url))
        XCTAssertTrue(ImageCache.fileName(for: url).hasSuffix(".img"))
    }
}
