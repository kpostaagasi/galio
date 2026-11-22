import XCTest
@testable import Galio

final class ChampionAdvisorTests: XCTestCase {
    private let ranked = ModeInfo.classify(gameMode: "CLASSIC", queueId: 420, mapId: 11, isCustom: false, isRanked: true)

    func testSuggestsThreeToFiveMidlanersWithReasons() {
        let ctx = ChampSelectContext(mode: ranked, position: .middle,
                                     allies: ["Garen", "LeeSin", "Jinx", "Thresh"].map(TestData.champion),
                                     enemies: ["Malphite", "Vi", "Zed"].map(TestData.champion))
        let out = ChampionAdvisor.suggest(ctx, from: TestData.set.champions)
        XCTAssertGreaterThanOrEqual(out.count, 3)
        XCTAssertLessThanOrEqual(out.count, 5)
        for s in out {
            XCTAssertTrue(s.champion.positions.contains("MIDDLE"), s.champion.id)
            XCTAssertFalse(s.reasons.isEmpty)
        }
        // All-physical allies: the top suggestions should bring magic damage.
        XCTAssertTrue(out.prefix(3).allSatisfy { $0.champion.isMagic }, out.map(\.champion.id).description)
        XCTAssertTrue(out[0].reasons.contains { $0.code == "dmg.needAP" })
    }

    func testAskForFrontlineWhenTeamIsSquishy() {
        let ctx = ChampSelectContext(mode: ranked, position: .top,
                                     allies: ["Ahri", "Jinx", "Lux", "Kaisa"].map(TestData.champion), enemies: [])
        let out = ChampionAdvisor.suggest(ctx, from: TestData.set.champions)
        XCTAssertTrue(out.contains { $0.reasons.contains { $0.code == "comp.frontline" } })
        XCTAssertGreaterThanOrEqual(out[0].champion.attrs.frontline, 2)
    }

    func testRespectsUnavailableAndPickable() {
        var ctx = ChampSelectContext(mode: ranked, position: .middle, allies: [], enemies: [])
        ctx.unavailable = [TestData.champion("Ahri").key]
        ctx.pickable = Set(["Ahri", "Lux", "Orianna", "Galio", "Zed", "Garen"].map { TestData.champion($0).key })
        let out = ChampionAdvisor.suggest(ctx, from: TestData.set.champions)
        XCTAssertFalse(out.contains { $0.champion.id == "Ahri" })
        XCTAssertTrue(out.allSatisfy { ctx.pickable.contains($0.champion.key) })
    }

    func testAramSwapPoolOnlyRanksBenchAndOwnChampion() {
        let aram = ModeInfo.classify(gameMode: "ARAM", queueId: 450, mapId: 12, isCustom: false, isRanked: false)
        let pool = ["Lux", "Ahri", "Orianna", "MissFortune"].map(TestData.champion)
        let ctx = ChampSelectContext(mode: aram, position: nil, allies: ["Sejuani", "Ezreal", "Sona", "Jax"].map(TestData.champion),
                                     enemies: [], swapPool: pool)
        let out = ChampionAdvisor.suggest(ctx, from: TestData.set.champions)
        XCTAssertEqual(Set(out.map(\.champion.id)), Set(pool.map(\.id)))
    }

    func testOwnMasteryIsAPositiveReason() {
        var ctx = ChampSelectContext(mode: ranked, position: .middle, allies: [], enemies: [])
        ctx.mastery = [TestData.champion("Galio").key: 400_000]
        let out = ChampionAdvisor.suggest(ctx, from: TestData.set.champions, limit: 10)
        let galio = out.first { $0.champion.id == "Galio" }
        XCTAssertNotNil(galio)
        XCTAssertTrue(galio?.reasons.contains { $0.code == "mastery" } ?? false)
    }
}

final class RuneAndSpellAdvisorTests: XCTestCase {
    func testRunePagesAreValidAndExplained() throws {
        let galio = TestData.champion("Galio")
        let build = try XCTUnwrap(TestData.set.details["Galio"]?.builds["MIDDLE"])
        let mode = ModeInfo.classify(gameMode: "CLASSIC", queueId: 420, mapId: 11, isCustom: false, isRanked: true)
        let pages = RuneAdvisor.suggest(build: build, champion: galio, enemies: [], mode: mode)
        XCTAssertGreaterThanOrEqual(pages.count, 2)
        XCTAssertLessThanOrEqual(pages.count, 3)
        for p in pages {
            XCTAssertTrue(RuneAdvisor.isValid(p, runes: TestData.set.runes), p.id)
            XCTAssertFalse(p.reasons.isEmpty)
            XCTAssertLessThanOrEqual(p.importName(champion: galio).count, 25)
        }
    }

    func testHeavyCrowdControlSwapsDefenseShardToTenacity() throws {
        let lux = TestData.champion("Lux")
        let build = try XCTUnwrap(TestData.set.details["Lux"]?.builds["MIDDLE"] ?? TestData.set.details["Lux"]?.builds["UTILITY"])
        let enemies = ["Leona", "Nautilus", "Sejuani", "Amumu", "Malphite"].map(TestData.champion)
        let mode = ModeInfo.classify(gameMode: "CLASSIC", queueId: 420, mapId: 11, isCustom: false, isRanked: true)
        let pages = RuneAdvisor.suggest(build: build, champion: lux, enemies: enemies, mode: mode)
        XCTAssertTrue(pages.allSatisfy { $0.perkIds[8] == RuneAdvisor.shardTenacity })
        XCTAssertTrue(pages[0].reasons.contains { $0.code == "rune.tenacity" })
    }

    func testArenaHasNoRunesOrSpells() throws {
        let darius = TestData.champion("Darius")
        let build = try XCTUnwrap(TestData.set.details["Darius"]?.builds["ARAM"])
        let arena = ModeInfo.classify(gameMode: "CHERRY", queueId: 1700, mapId: 30, isCustom: false, isRanked: false)
        XCTAssertTrue(RuneAdvisor.suggest(build: build, champion: darius, enemies: [], mode: arena).isEmpty)
        XCTAssertTrue(SummonerSpellAdvisor.suggest(build: build, champion: darius, position: nil, enemies: [], mode: arena).isEmpty)
    }

    func testSpellOptionsPerRole() throws {
        let mode = ModeInfo.classify(gameMode: "CLASSIC", queueId: 420, mapId: 11, isCustom: false, isRanked: true)
        let lee = TestData.champion("LeeSin")
        let jungle = SummonerSpellAdvisor.suggest(build: TestData.set.details["LeeSin"]?.builds["JUNGLE"], champion: lee,
                                                  position: .jungle, enemies: [], mode: mode)
        XCTAssertTrue(jungle.allSatisfy { $0.spells.contains(SummonerSpellAdvisor.smite) })
        let jinx = TestData.champion("Jinx")
        let bot = SummonerSpellAdvisor.suggest(build: nil, champion: jinx, position: .bottom,
                                               enemies: ["Zed", "Talon", "Leona", "Nautilus", "Sejuani"].map(TestData.champion), mode: mode)
        XCTAssertGreaterThanOrEqual(bot.count, 2)
        XCTAssertTrue(bot.contains { $0.spells.contains(SummonerSpellAdvisor.barrier) || $0.spells.contains(SummonerSpellAdvisor.cleanse) })
        let aram = ModeInfo.classify(gameMode: "ARAM", queueId: 450, mapId: 12, isCustom: false, isRanked: false)
        let lux = SummonerSpellAdvisor.suggest(build: TestData.set.details["Lux"]?.builds["ARAM"], champion: TestData.champion("Lux"),
                                               position: nil, enemies: [], mode: aram)
        XCTAssertTrue(lux.contains { $0.spells.contains(SummonerSpellAdvisor.mark) })
    }

    func testFlashKeepsItsKey() {
        XCTAssertEqual(SummonerSpellAdvisor.orderForPlayer([4, 14], currentSpell1: 12, currentSpell2: 4), [14, 4])
        XCTAssertEqual(SummonerSpellAdvisor.orderForPlayer([14, 4], currentSpell1: 4, currentSpell2: 7), [4, 14])
        XCTAssertEqual(SummonerSpellAdvisor.orderForPlayer([4, 14], currentSpell1: 4, currentSpell2: 7), [4, 14])
    }
}

final class SkillOrderAdvisorTests: XCTestCase {
    func testStandardPlan() {
        let plan = SkillOrderAdvisor.plan(maxOrder: ["Q", "E", "W"], first: ["Q", "E", "W"])
        XCTAssertEqual(plan.sequence.count, 18)
        XCTAssertEqual(plan.firstThree, ["Q", "E", "W"])
        XCTAssertEqual(plan.sequence[5], "R")
        XCTAssertEqual(plan.sequence[10], "R")
        XCTAssertEqual(plan.sequence[15], "R")
        let r = plan.ranks(atLevel: 18)
        XCTAssertEqual(r, ["Q": 5, "E": 5, "W": 5, "R": 3])
        XCTAssertEqual(plan.ranks(atLevel: 9)["Q"], 5) // Q maxed at 9
        // A basic ability never exceeds rank n before level 2n-1.
        for level in 1...18 {
            let ranks = plan.ranks(atLevel: level)
            for k in ["Q", "W", "E"] { XCTAssertLessThanOrEqual(2 * ranks[k]! - 1, level, "\(k) at \(level)") }
        }
    }

    func testUltAtLevelOneChampions() {
        let plan = SkillOrderAdvisor.plan(maxOrder: ["Q", "W", "E"], first: ["Q", "W", "E"], ultLevels: [1, 6, 11, 16])
        XCTAssertEqual(plan.sequence[0], "R")
        XCTAssertEqual(plan.ranks(atLevel: 18)["R"], 4)
    }

    func testNextSkillReminder() {
        let plan = SkillOrderAdvisor.plan(maxOrder: ["Q", "E", "W"], first: ["Q", "E", "W"])
        // Level 6 with Q3 E1 W1, ult not yet taken -> R.
        XCTAssertEqual(SkillOrderAdvisor.nextSkill(plan: plan, level: 6, current: ["Q": 3, "E": 1, "W": 1, "R": 0]), "R")
        // Level 4 with Q1 E1 W1 -> Q.
        XCTAssertEqual(SkillOrderAdvisor.nextSkill(plan: plan, level: 4, current: ["Q": 1, "E": 1, "W": 1, "R": 0]), "Q")
        // No unspent point -> nil.
        XCTAssertNil(SkillOrderAdvisor.nextSkill(plan: plan, level: 3, current: ["Q": 1, "E": 1, "W": 1, "R": 0]))
        // Fixture: level 9, Q5 W1 E3 R1 (all points spent: 10 > 9 is impossible, use 9 points).
        XCTAssertNil(SkillOrderAdvisor.nextSkill(plan: plan, level: 9, current: ["Q": 5, "W": 1, "E": 2, "R": 1]))
    }

    func testEveryChampionPlanIsLegal() {
        for (id, d) in TestData.set.details {
            let plan = SkillOrderAdvisor.plan(for: d.skillOrder)
            XCTAssertEqual(plan.sequence.count, 18, id)
            let r = plan.ranks(atLevel: 18)
            XCTAssertEqual((r["Q"] ?? 0) + (r["W"] ?? 0) + (r["E"] ?? 0) + (r["R"] ?? 0), 18, id)
        }
    }
}
