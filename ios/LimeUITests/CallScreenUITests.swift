import XCTest

/// The 1:1 call screen (LIME-118), with no media: `-lime-demo-call voice|video` shows it in a made-up active call.
@MainActor
final class CallScreenUITests: XCTestCase {
    private func app(_ kind: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-call", kind]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testAVoiceCallHasOneRowOfControlsAndAVideoCallHasTheStack() {
        let voice = app("voice")
        XCTAssertTrue(any(voice, "call-screen").waitForExistence(timeout: 10))
        XCTAssertTrue(any(voice, "call-controls-voice").exists, "voice: one row")
        XCTAssertFalse(any(voice, "call-controls-video").exists)
        XCTAssertTrue(voice.buttons["call-end"].exists)
        XCTAssertTrue(voice.buttons["call-mute"].exists && voice.buttons["call-speaker"].exists)
        XCTAssertFalse(any(voice, "call-self-view").exists, "no self-view on a voice call")
        XCTAssertTrue(any(voice, "call-avatar").exists, "a large avatar until there is video")
        XCTAssertTrue(voice.staticTexts["call-status"].label.contains(":"), "the timer runs: \(voice.staticTexts["call-status"].label)")
        voice.terminate()

        let video = app("video")
        XCTAssertTrue(any(video, "call-controls-video").waitForExistence(timeout: 10), "video: the stack")
        XCTAssertFalse(any(video, "call-controls-voice").exists)
        XCTAssertTrue(video.buttons["call-flip"].exists && video.buttons["call-video"].exists && video.buttons["call-end"].exists)
        XCTAssertTrue(any(video, "call-self-view").exists, "my own picture in a tile")
    }

    func testVideoControlsFadeAfterFiveSecondsAndATapBringsThemBack() {
        let video = app("video")
        let end = video.buttons["call-end"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        XCTAssertTrue(end.isHittable, "shown at first")
        // They fade after 5 s without a touch: no longer hittable (and invisible).
        let faded = NSPredicate { _, _ in !end.isHittable }
        expectation(for: faded, evaluatedWith: nil)
        waitForExpectations(timeout: 12)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        let back = NSPredicate { _, _ in end.isHittable }
        expectation(for: back, evaluatedWith: nil)
        waitForExpectations(timeout: 3)
    }

    func testTheSelfViewDragsToAnotherCornerAndSwapsOnTap() {
        let video = app("video")
        let tile = any(video, "call-self-view")
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        let before = tile.frame
        let handle = any(video, "call-tile-handle")
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: video.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.8)))
        let moved = NSPredicate { _, _ in tile.frame.minX < before.minX - 100 && tile.frame.minY > before.minY + 100 }
        expectation(for: moved, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertLessThan(tile.frame.width, 200, "still a tile in the new corner")
        // A tap swaps the big and small pictures: my own picture becomes the big one.
        any(video, "call-tile-handle").tap()
        let big = NSPredicate { _, _ in tile.frame.width > 300 }
        expectation(for: big, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }

    func testTheNamePillOpensTheSmallSheetWithMessage() {
        let voice = app("voice")
        XCTAssertTrue(voice.buttons["call-name-pill"].waitForExistence(timeout: 10))
        voice.buttons["call-name-pill"].tap()
        XCTAssertTrue(any(voice, "call-person-sheet").waitForExistence(timeout: 5))
        XCTAssertTrue(voice.buttons["call-person-message"].exists)
    }
}
