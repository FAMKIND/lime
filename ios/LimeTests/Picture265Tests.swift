import XCTest
@testable import Lime

/// LIME-265: the video track's on/off is the controller's, so a player that closes in Listen can switch it back on for the feed card.
@MainActor
final class Picture265Tests: XCTestCase {
    func testThePictureIsOnUntilListenAndOnAgainAfterwards() {
        let controller = PodcastController(duration: 10, title: "t", artist: "a", isVideo: true)
        XCTAssertTrue(controller.pictureOn)
        controller.setPicture(false)
        XCTAssertFalse(controller.pictureOn)
        controller.setPicture(true)
        XCTAssertTrue(controller.pictureOn)
    }
}
