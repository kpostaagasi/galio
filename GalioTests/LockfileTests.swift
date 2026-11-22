import XCTest
@testable import Galio

final class LockfileTests: XCTestCase {
    func testParsesValidLockfile() throws {
        let lf = try XCTUnwrap(Lockfile(contents: "LeagueClient:12345:54321:abcDEF123:https\n"))
        XCTAssertEqual(lf.processName, "LeagueClient")
        XCTAssertEqual(lf.pid, 12345)
        XCTAssertEqual(lf.port, 54321)
        XCTAssertEqual(lf.password, "abcDEF123")
        XCTAssertEqual(lf.baseURL.absoluteString, "https://127.0.0.1:54321")
    }

    func testAuthorizationHeaderUsesRiotUser() throws {
        let lf = try XCTUnwrap(Lockfile(contents: "LeagueClient:1:2999:abc:https"))
        XCTAssertEqual(lf.authorizationHeader, "Basic cmlvdDphYmM=")
        XCTAssertEqual(LCUEndpoint(lockfile: lf).authorization, "Basic cmlvdDphYmM=")
    }

    func testRejectsMalformedInput() {
        XCTAssertNil(Lockfile(contents: ""))
        XCTAssertNil(Lockfile(contents: "LeagueClient:1:2:pw"))
        XCTAssertNil(Lockfile(contents: "LeagueClient:x:2999:pw:https"))
        XCTAssertNil(Lockfile(contents: "LeagueClient:1:70000:pw:https"))
        XCTAssertNil(Lockfile(contents: "LeagueClient:1:2999::https"))
        XCTAssertNil(Lockfile(contents: "LeagueClient:1:2999:pw:ftp"))
    }
}
