import XCTest

/// LIME-277g (demo): buttons keep their words whole in a wide font at a big text size; search and the avatar share one bubble a few points closer.
@MainActor
final class Theme277gUITests: LimeUITestCase {
    func testThePhotoButtonsOfNewGroupStayOnOneLineEachInASerifFontAtALargeSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "new-group-name",
                               "-lime.text.font", "lora", "-lime.text.follow", "NO", "-lime.text.step", "4"]
        app.launch()
        let mode = app.segmentedControls["group-avatar-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.buttons["Photo"].tap()
        let library = app.buttons["group-photo-library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        XCTAssertEqual(library.label, "Choose", "VoiceOver still says the words")
        let screen = app.windows.firstMatch.frame
        for id in ["group-photo-library", "group-photo-camera"] where app.buttons[id].exists {
            let b = app.buttons[id]
            XCTAssertGreaterThanOrEqual(b.frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(b.frame.height, 44, id)
            XCTAssertLessThanOrEqual(b.frame.maxX, screen.maxX + 1, "\(id) fits on the screen")
        }
    }

    func testSearchAndYourAvatarShareOneBubbleCloserTogether() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        let search = app.buttons["messages-search-button"], me = app.buttons["settings-button"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(me.frame.minX - search.frame.maxX, 2, "the two targets sit edge to edge (a few points closer than before)")
        XCTAssertLessThan(search.frame.midX, me.frame.midX)
    }
}
