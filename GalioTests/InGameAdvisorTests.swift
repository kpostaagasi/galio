import XCTest
@testable import Galio

final class ItemAdvisorTests: XCTestCase {
    private var items: [Int: ItemInfo] { Dictionary(TestData.set.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    func testThreatFromLiveFixture() throws {
        let live = try Fixture.decode(LiveGameData.self, "liveclient-sr.json")
        let champs = live.enemies.compactMap { p in TestData.set.champions.first { $0.id == p.championDataId } }
        XCTAssertEqual(champs.count, 5)
        let threat = EnemyThreat(champions: champs, items: live.enemies.map { $0.itemIds.compactMap { items[$0] } })
        XCTAssertGreaterThan(threat.adShare, 0.6, "Malphite/Vi/Zed/Caitlyn vs Soraka is AD heavy")
        XCTAssertGreaterThanOrEqual(threat.healing, 1.2, "Soraka + Moonstone means healing")
        XCTAssertGreaterThanOrEqual(threat.crit, 1.0, "Caitlyn with Infinity Edge")
    }

    func testAntiHealAndArmorRiseAgainstHealingADTeam() throws {
        let build = try XCTUnwrap(TestData.set.details["Galio"]?.build(for: "MIDDLE"))
        let enemies = ["Soraka", "Darius", "Zed", "Caitlyn", "Vi"].map(TestData.champion)
        let threat = EnemyThreat(champions: enemies)
        let out = ItemAdvisor.suggest(build: build, owned: [1056, 3111], gold: 1200, threat: threat, items: items, map: 11, limit: 5)
        XCTAssertGreaterThanOrEqual(out.count, 3)
        XCTAssertTrue(out.contains { $0.reasons.contains { $0.code == "vs.heal" } }, out.map(\.item.name).description)
        XCTAssertTrue(out.contains { $0.reasons.contains { $0.code == "vs.ad" } })
        XCTAssertFalse(out.contains { $0.item.id == 3111 }, "owned items are never suggested")
    }

    func testMagicResistAgainstAPTeamAndNoArmorBonus() throws {
        let build = try XCTUnwrap(TestData.set.details["Garen"]?.build(for: "TOP"))
        let enemies = ["Lux", "Brand", "Veigar", "Katarina", "Amumu"].map(TestData.champion)
        let out = ItemAdvisor.suggest(build: build, owned: [1055], gold: 500, threat: EnemyThreat(champions: enemies), items: items, map: 11)
        XCTAssertTrue(out.prefix(3).contains { $0.reasons.contains { $0.code == "vs.ap" } }, out.map(\.item.name).description)
        XCTAssertFalse(out.contains { $0.reasons.contains { $0.code == "vs.ad" } })
    }

    func testGoldStatusCreditsOwnedComponents() throws {
        let zhonya = try XCTUnwrap(items[3157])
        let comp = try XCTUnwrap(zhonya.from.first)
        let full = ItemAdvisor.goldStatus(for: zhonya, owned: [], gold: 0, items: items)
        XCTAssertEqual(full.0, zhonya.gold)
        let partial = ItemAdvisor.goldStatus(for: zhonya, owned: [comp], gold: 0, items: items)
        XCTAssertEqual(partial.0, zhonya.gold - (items[comp]?.gold ?? 0))
        let affordable = ItemAdvisor.goldStatus(for: zhonya, owned: [], gold: 5000, items: items)
        XCTAssertEqual(affordable.0, 0)
        XCTAssertNil(affordable.1)
        let component = ItemAdvisor.goldStatus(for: zhonya, owned: [], gold: 1300, items: items)
        XCTAssertNotNil(component.1, "a component should be buyable with 1300 gold")
    }

    func testRespectsMapAvailability() throws {
        let build = try XCTUnwrap(TestData.set.details["Lux"]?.builds["ARAM"])
        let out = ItemAdvisor.suggest(build: build, owned: [], gold: 0, threat: EnemyThreat(), items: items, map: 12)
        XCTAssertTrue(out.allSatisfy { $0.item.maps.contains(12) })
    }

    @MainActor
    func testInGameAdviceFromFixture() throws {
        // Build the in-game advice pieces the way AdviceBuilder does, from the recorded fixture.
        let store = TestData.store()
        let live = try Fixture.decode(LiveGameData.self, "liveclient-sr.json")
        let me = try XCTUnwrap(live.me)
        let galio = try XCTUnwrap(store.champion(liveId: me.championDataId, name: me.championName))
        let plan = SkillOrderAdvisor.plan(for: try XCTUnwrap(store.detail(for: galio)).skillOrder)
        let ranks = ["Q": live.activePlayer!.abilityLevel("Q"), "W": live.activePlayer!.abilityLevel("W"),
                     "E": live.activePlayer!.abilityLevel("E"), "R": live.activePlayer!.abilityLevel("R")]
        XCTAssertNotNil(SkillOrderAdvisor.nextSkill(plan: plan, level: live.activePlayer!.level, current: ranks),
                        "fixture has one unspent skill point")
    }
}

final class AugmentAdvisorTests: XCTestCase {
    private func augment(_ name: String, family: String = "MAYHEM") throws -> AugmentInfo {
        try XCTUnwrap(TestData.set.augments[family]?.first { $0.name == name }, "missing augment \(name)")
    }

    func testTiersAreChampionRelative() throws {
        let archmage = try augment("Archmage")      // AP / ability haste flavoured
        let blunt = try augment("Blunt Force")      // attack damage
        let lux = TestData.champion("Lux")
        let darius = TestData.champion("Darius")
        let luxArch = AugmentAdvisor.rate(archmage, champion: lux)
        let luxBlunt = AugmentAdvisor.rate(blunt, champion: lux)
        XCTAssertGreaterThan(luxArch.tier, luxBlunt.tier)
        XCTAssertGreaterThan(AugmentAdvisor.rate(blunt, champion: darius).tier, luxBlunt.tier)
        XCTAssertTrue(luxBlunt.reasons.contains { !$0.positive })
    }

    func testEveryAugmentGetsATierAndNoWinRate() throws {
        let lux = TestData.champion("Lux")
        for family in ["MAYHEM", "ARENA"] {
            let ranked = AugmentAdvisor.rank(TestData.set.augments[family] ?? [], champion: lux)
            XCTAssertFalse(ranked.isEmpty)
            XCTAssertTrue(Tier.allCases.contains(ranked[0].tier))
            // Tiers are ordered best-first.
            for (a, b) in zip(ranked, ranked.dropFirst()) { XCTAssertGreaterThanOrEqual(a.tier, b.tier) }
            for r in ranked { for reason in r.reasons { XCTAssertFalse(reason.text.contains("%"), "no percentages/win rates") } }
        }
    }

    func testFuzzyMatchingOfOCRLines() throws {
        let augments = TestData.set.augments["MAYHEM"] ?? []
        let matches = FuzzyMatcher.match(lines: ["Archmage", "Blunt Forse", "Celestial B0dy", "Level 11", "SELECT"], augments: augments)
        XCTAssertEqual(Set(matches.map(\.augment.name)), ["Archmage", "Blunt Force", "Celestial Body"])
        XCTAssertGreaterThan(FuzzyMatcher.similarity("Hepsi Senin İçin", "Hepsi Senin Icin"), 0.95)
        XCTAssertLessThan(FuzzyMatcher.similarity("Archmage", "Blunt Force"), 0.5)
        XCTAssertEqual(FuzzyMatcher.normalize("Crit 'n Cast"), "critncast")
    }

    func testTurkishNamesMatchToo() throws {
        let augments = TestData.set.augments["MAYHEM"] ?? []
        let target = try XCTUnwrap(augments.first { $0.nameTR != $0.name && $0.nameTR.count > 6 })
        let matches = FuzzyMatcher.match(lines: [target.nameTR.uppercased()], augments: augments)
        XCTAssertEqual(matches.first?.augment.id, target.id)
    }
}
