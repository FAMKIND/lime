import XCTest

/// The composer's one add sheet (LIME-127), in the made-up chat with Sam. The recent strip shows made-up items (no library, no
/// permission prompt); `-lime-demo-photos denied` is the denied case.
@MainActor
final class AddSheetUITests: XCTestCase {
    private func openSheet(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + extra
        app.launch()
        app.buttons["conversation-row-dm:sam"].tap()
        XCTAssertTrue(app.buttons["composer-plus"].waitForExistence(timeout: 10))
        app.buttons["composer-plus"].tap()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testThePlusOpensOneSheetWithCameraRecentItemsPhotosAndFiles() {
        let app = openSheet()
        XCTAssertTrue(app.buttons["add-close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add to your message"].exists)
        XCTAssertTrue(app.buttons["composer-photo-library"].exists, "Photos, top right")
        XCTAssertTrue(app.buttons["composer-take-photo"].exists, "the Camera tile")
        XCTAssertTrue(app.buttons["add-recent-0"].waitForExistence(timeout: 5), "recent photos and videos")
        XCTAssertTrue(app.buttons["composer-files"].exists)
        XCTAssertFalse(app.buttons["composer-video-library"].exists, "the old six-button list is gone")
        XCTAssertFalse(app.buttons["add-selected"].exists, "nothing is selected yet")
        app.buttons["add-close"].tap()
        XCTAssertTrue(app.buttons["add-close"].waitForNonExistence(timeout: 5))
    }

    func testSelectingTwoRecentItemsAddsBothAtOnce() {
        let app = openSheet()
        XCTAssertTrue(app.buttons["add-recent-0"].waitForExistence(timeout: 5))
        app.buttons["add-recent-0"].tap()
        app.buttons["add-recent-1"].tap()
        XCTAssertTrue(app.buttons["add-selected"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["add-selected"].label, "Add (2)")
        app.buttons["add-selected"].tap()
        XCTAssertTrue(app.buttons["add-close"].waitForNonExistence(timeout: 5), "the sheet closes")
        let remove = app.buttons.matching(identifier: "draft-remove")
        XCTAssertTrue(remove.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(remove.count, 2, "both are waiting above the text")
    }

    func testAVideoAndAPhotoCanBeAddedTogetherAndATapUnselects() {
        let app = openSheet()
        XCTAssertTrue(app.buttons["add-recent-3"].waitForExistence(timeout: 5), "the fourth made-up item is a video")
        XCTAssertTrue(app.buttons["add-recent-3"].label.hasPrefix("Video"), app.buttons["add-recent-3"].label)
        app.buttons["add-recent-0"].tap()
        // On a narrow phone the fourth tile is off screen: scroll the strip until it can be tapped.
        for _ in 0..<3 where app.buttons["add-recent-3"].frame.maxX > app.frame.maxX - 8 { app.scrollViews["add-strip"].swipeLeft() }
        app.buttons["add-recent-3"].tap()
        XCTAssertEqual(app.buttons["add-selected"].label, "Add (2)")
        for _ in 0..<3 where app.buttons["add-recent-0"].frame.minX < 8 { app.scrollViews["add-strip"].swipeRight() }
        app.buttons["add-recent-0"].tap()
        XCTAssertEqual(app.buttons["add-selected"].label, "Add (1)", "tapping again takes it out")
        app.buttons["add-recent-0"].tap()
        app.buttons["add-selected"].tap()
        let remove = app.buttons.matching(identifier: "draft-remove")
        XCTAssertTrue(remove.firstMatch.waitForExistence(timeout: 10))
        let two = NSPredicate { _, _ in remove.count == 2 }
        expectation(for: two, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
    }

    func testWhenPhotoAccessIsDeniedTheStripIsHiddenAndTheRestStays() {
        let app = openSheet(["-lime-demo-photos", "denied"])
        XCTAssertTrue(app.buttons["composer-files"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["add-recent-0"].exists, "no recent items without access")
        XCTAssertTrue(app.buttons["composer-take-photo"].exists && app.buttons["composer-photo-library"].exists)
        XCTAssertFalse(app.buttons["add-manage"].exists)
    }

    func testLimitedAccessOffersManage() {
        let app = openSheet(["-lime-demo-photos", "limited"])
        XCTAssertTrue(app.buttons["add-recent-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-manage"].exists)
    }

    func testFilesOpensTheDocumentPicker() {
        let app = openSheet()
        app.buttons["composer-files"].tap()
        XCTAssertTrue(app.buttons["add-close"].waitForNonExistence(timeout: 5), "the sheet makes way")
        let picker = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "the system document picker")
        picker.tap()
        XCTAssertTrue(app.buttons["composer-plus"].waitForExistence(timeout: 10))
    }

    func testPhotosOpensTheSystemPicker() {
        let app = openSheet()
        app.buttons["composer-photo-library"].tap()
        XCTAssertTrue(app.buttons["add-close"].waitForNonExistence(timeout: 5))
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "the system photo picker")
        cancel.tap()
        XCTAssertTrue(app.buttons["composer-plus"].waitForExistence(timeout: 10))
    }
}
