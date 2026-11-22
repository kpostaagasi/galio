import XCTest
@testable import Galio

final class ClientActionsTests: XCTestCase {
    private func makeServer(_ scenario: String = "champselect-locked") async throws -> (MockServer, LCUClient) {
        let server = MockServer(scenario: try XCTUnwrap(MockScenario.load(named: scenario)))
        _ = try await server.start()
        return (server, LCUClient(endpoint: LCUEndpoint(baseURL: server.baseURL, authorization: nil)))
    }

    private let page = NewPerkPage(name: "Galio: Galio", primaryStyleId: 8400, subStyleId: 8000,
                                   selectedPerkIds: [8439, 8463, 8429, 8451, 9105, 9111, 5007, 5001, 5001], current: true)

    func testImportCreatesPageAndMakesItCurrent() async throws {
        let (server, client) = try await makeServer()
        defer { server.stop() }
        let outcome = try await ClientActions(client: client, phase: .champSelect).importRunes(page)
        XCTAssertEqual(outcome, .created(name: "Galio: Galio"))
        let pages: [LCUPerkPage] = try await client.get("/lol-perks/v1/pages")
        XCTAssertEqual(pages.filter { $0.name == "Galio: Galio" }.count, 1)
        XCTAssertTrue(server.requests.contains { $0.method == "POST" && $0.path == "/lol-perks/v1/pages" })
        XCTAssertTrue(server.requests.contains { $0.method == "PUT" && $0.path == "/lol-perks/v1/currentpage" })
        // Importing again replaces Galio's own page instead of adding a second one.
        _ = try await ClientActions(client: client, phase: .champSelect).importRunes(page)
        let after: [LCUPerkPage] = try await client.get("/lol-perks/v1/pages")
        XCTAssertEqual(after.filter { $0.name.hasPrefix("Galio") }.count, 1)
        XCTAssertEqual(after.count, pages.count)
    }

    func testFullPageLimitAsksBeforeReplacing() async throws {
        let (server, client) = try await makeServer()
        defer { server.stop() }
        server.setRoute("GET /lol-perks/v1/inventory", ["ownedPageCount": 2])
        let actions = ClientActions(client: client, phase: .champSelect)
        let outcome = try await actions.importRunes(page)
        guard case let .needsConfirmation(pageId, pageName) = outcome else { return XCTFail("expected confirmation, got \(outcome)") }
        XCTAssertEqual(pageId, 101)
        XCTAssertEqual(pageName, "Mid Mage")
        XCTAssertFalse(server.requests.contains { $0.method == "POST" }, "nothing may change before the player confirms")
        let confirmed = try await actions.importRunes(page, replacing: pageId)
        XCTAssertEqual(confirmed, .created(name: "Galio: Galio"))
        XCTAssertTrue(server.requests.contains { $0.method == "DELETE" && $0.path == "/lol-perks/v1/pages/101" })
    }

    func testClientActionsRefuseDuringLiveGame() async throws {
        let (server, client) = try await makeServer()
        defer { server.stop() }
        let actions = ClientActions(client: client, phase: .inProgress)
        do {
            _ = try await actions.importRunes(page)
            XCTFail("rune import must be refused in game")
        } catch let e as ClientActions.ActionError {
            XCTAssertEqual(e, .notAllowedInGame)
        }
        do {
            try await actions.setSummonerSpells([4, 14])
            XCTFail("spells must be refused in game")
        } catch let e as ClientActions.ActionError {
            XCTAssertEqual(e, .notAllowedInGame)
        }
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testSetSummonerSpellsPatchesMySelection() async throws {
        let (server, client) = try await makeServer()
        defer { server.stop() }
        try await ClientActions(client: client, phase: .champSelect).setSummonerSpells([4, 12])
        let req = try XCTUnwrap(server.requests.first { $0.path == "/lol-champ-select/v1/session/my-selection" })
        XCTAssertEqual(req.method, "PATCH")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(req.body.utf8)) as? [String: Int])
        XCTAssertEqual(body, ["spell1Id": 4, "spell2Id": 12])
    }

    func testItemSetExportWritesClientFormat() async throws {
        let (server, client) = try await makeServer()
        defer { server.stop() }
        let galio = TestData.champion("Galio")
        let build = try XCTUnwrap(TestData.set.details["Galio"]?.builds["MIDDLE"])
        let payload = ItemSetPayload.from(build: build, champion: galio, position: "MIDDLE", map: 11, threat: EnemyThreat())
        try await ClientActions(client: client, phase: .champSelect).exportItemSet(payload)
        let req = try XCTUnwrap(server.requests.first { $0.method == "PUT" })
        XCTAssertEqual(req.path, "/lol-item-sets/v1/item-sets/1200300/sets")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(req.body.utf8)) as? [String: Any])
        let sets = try XCTUnwrap(root["itemSets"] as? [[String: Any]])
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0]["associatedChampions"] as? [Int], [3])
        let blocks = try XCTUnwrap(sets[0]["blocks"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(blocks.count, 3)
        XCTAssertNotNil((blocks[0]["items"] as? [[String: Any]])?.first?["id"] as? String)
    }
}
