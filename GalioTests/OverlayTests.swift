import XCTest
@testable import Galio

final class OverlayTests: XCTestCase {
    func testOverlayFollowsTheGameFlow() {
        for phase in [GameflowPhase.champSelect, .gameStart, .inProgress, .reconnect] {
            XCTAssertTrue(OverlayController.wantsOverlay(phase), phase.rawValue)
            XCTAssertFalse(OverlayController.hidesOverlay(phase), phase.rawValue)
        }
    }

    func testOverlayHidesAfterTheGameAndWhenTheClientIsClosed() {
        for phase in [GameflowPhase.none, .waitingForStats, .preEndOfGame, .endOfGame, .lobby] {
            XCTAssertTrue(OverlayController.hidesOverlay(phase), phase.rawValue)
            XCTAssertFalse(OverlayController.wantsOverlay(phase), phase.rawValue)
        }
    }
}
