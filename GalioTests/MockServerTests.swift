import XCTest
@testable import Galio

final class MockServerTests: XCTestCase {
    func testAllScenariosAreBundled() {
        for name in MockScenario.available {
            XCTAssertNotNil(MockScenario.load(named: name), "missing mock scenario \(name)")
        }
    }

    func testRequestParserWaitsForBody() {
        let partial = Data("POST /x HTTP/1.1\r\nContent-Length: 4\r\n\r\nab".utf8)
        XCTAssertNil(MockServer.parseRequest(partial))
        let full = Data("POST /x?y=1 HTTP/1.1\r\nContent-Length: 4\r\n\r\nabcd".utf8)
        let req = MockServer.parseRequest(full)
        XCTAssertEqual(req?.method, "POST")
        XCTAssertEqual(req?.path, "/x")
        XCTAssertEqual(req.map { String(decoding: $0.body, as: UTF8.self) }, "abcd")
    }

    func testLCUClientAgainstMockServer() async throws {
        let scenario = try XCTUnwrap(MockScenario.load(named: "champselect"))
        let server = MockServer(scenario: scenario)
        _ = try await server.start()
        defer { server.stop() }
        let client = LCUClient(endpoint: LCUEndpoint(baseURL: server.baseURL, authorization: nil))

        let phase = try await client.gameflowPhase()
        XCTAssertEqual(phase, .champSelect)
        let session = try await client.gameflowSession()
        XCTAssertEqual(session.mode.queueId, 420)
        let cs = try await client.champSelectSession()
        XCTAssertEqual(cs.myPosition, .middle)
        let summoner = try await client.currentSummoner()
        XCTAssertEqual(summoner.summonerId, 1200300)

        do {
            _ = try await client.request("GET", "/does-not-exist")
            XCTFail("expected 404")
        } catch let LCUError.http(status, _) {
            XCTAssertEqual(status, 404)
        }
    }

    func testLiveClientAgainstMockServer() async throws {
        let scenario = try XCTUnwrap(MockScenario.load(named: "ingame"))
        let server = MockServer(scenario: scenario)
        _ = try await server.start()
        defer { server.stop() }
        let live = try await LiveClient(baseURL: server.baseURL).allGameData()
        XCTAssertEqual(live.me?.championName, "Galio")
        XCTAssertEqual(live.enemies.count, 5)
    }
}
