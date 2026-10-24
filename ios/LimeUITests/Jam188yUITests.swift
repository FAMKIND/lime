import XCTest

/// LIME-188y: media and cards, corrected: the viewer's actions, the video's timeline, even action rows, the audio card's player beside the cover.
@MainActor
final class Jam188yUITests: LimeUITestCase {
    private func launch(_ screen: String = "jam-following") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testThePhotoViewerHasTheFourActions() {
        let app = launch()
        app.showJamArticles()
        let card = app.buttons["jam-post-demo-post-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        let photo = any(app, "jam-row-photo-0")
        for _ in 0..<4 where !photo.exists { app.swipeUp() }
        XCTAssertTrue(photo.waitForExistence(timeout: 8))
        photo.tap()
        func pill(_ label: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", label)).firstMatch }
        XCTAssertTrue(pill("like").waitForExistence(timeout: 5))
        for label in ["like", "comment", "remix", "share"] { XCTAssertTrue(pill(label).exists, label) }
        let xs = ["like", "comment", "remix", "share"].map { pill($0).frame.midX }
        let gaps = zip(xs, xs.dropFirst()).map { $1 - $0 }
        XCTAssertEqual(gaps.max() ?? 0, gaps.min() ?? 0, accuracy: 1.5, "evenly spaced")
    }

    func testTheVideoCardShowsElapsedAndTotalAsMinutesAndSeconds() {
        let app = launch()
        app.openDemoVideoPost()
        let time = any(app, "jam-video-time")
        for _ in 0..<6 where !time.exists { app.swipeUp() }
        XCTAssertTrue(time.waitForExistence(timeout: 8))
        XCTAssertNotNil(time.label.range(of: #"^\d+:\d\d / \d+:\d\d$"#, options: .regularExpression), time.label)
        XCTAssertTrue(any(app, "jam-video-timeline").exists, "and a line to drag")
    }

    func testTheCardsActionsAreFourEqualColumns() {
        let app = launch()
        let like = any(app, "jam-like-demo-post-2"), share = any(app, "jam-action-share-demo-post-2")
        XCTAssertTrue(like.waitForExistence(timeout: 10))
        let width = app.windows.firstMatch.frame.width
        XCTAssertLessThan(like.frame.midX, width * 0.25 + 10, "the first column's centre")
        XCTAssertGreaterThan(share.frame.midX, width * 0.75 - 10, "the last column reaches the right side")
    }
}
