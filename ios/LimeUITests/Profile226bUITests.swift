import XCTest

/// LIME-226b: video backgrounds: they play silently on someone's profile, fall back to the still, and are made in the Background screen.
@MainActor
final class Profile226bUITests: LimeUITestCase {
    private func samProfile(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + extra
        app.launch()
        app.buttons["conversation-row-dm:sam"].tap()
        app.descendants(matching: .any).matching(identifier: "chat-title").firstMatch.tap()
        return app
    }

    func testAContactsVideoShowsItsStillFirstAndThenPlays() {
        let app = samProfile(["-lime-demo-video"])
        XCTAssertTrue(app.descendants(matching: .any)["profile-hero-background"].waitForExistence(timeout: 10), "the still is the poster")
        XCTAssertTrue(app.descendants(matching: .any)["profile-hero-video"].waitForExistence(timeout: 10), "and a player is there")
    }

    func testWithReduceMotionTheStillStaysAndNothingPlays() {
        let app = samProfile(["-lime-demo-video", "-lime-demo-reduce-motion"])
        XCTAssertTrue(app.descendants(matching: .any)["profile-hero-background"].waitForExistence(timeout: 10))
        sleep(2)
        XCTAssertFalse(app.descendants(matching: .any)["profile-hero-video"].exists, "no player with Reduce Motion")
    }

    func testAVideoNotDownloadedOnCellularOffersATapToPlay() {
        let app = samProfile(["-lime-demo-video-pending"])
        let play = app.buttons["profile-hero-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "Play background is offered")
        XCTAssertFalse(app.descendants(matching: .any)["profile-hero-video"].exists)
        play.tap()
        XCTAssertTrue(app.descendants(matching: .any)["profile-hero-video"].waitForExistence(timeout: 10), "a tap fetches and plays it")
        XCTAssertFalse(play.exists)
    }

    func testChoosingAVideoMakesTheStillAndTheClipAndTheVideoCanBeRemovedAlone() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/background", "-lime-demo-pick-video"]
        app.launch()
        XCTAssertTrue(app.buttons["background-choose"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["background-remove-video"].exists)
        app.buttons["background-choose"].tap()
        XCTAssertTrue(app.buttons["background-crop-save"].waitForExistence(timeout: 15), "the frame of the video, to move and scale")
        app.buttons["background-crop-save"].tap()
        XCTAssertTrue(app.buttons["background-remove-video"].waitForExistence(timeout: 40), "the clip was cut, framed and saved")
        XCTAssertTrue(app.buttons["background-remove"].exists)
        app.buttons["background-remove-video"].tap()
        XCTAssertTrue(app.buttons["background-remove-video"].waitForNonExistence(timeout: 10), "the video goes")
        XCTAssertTrue(app.buttons["background-remove"].exists, "the photo stays")
    }
}
