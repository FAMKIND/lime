import XCTest

/// LIME-210d: the student-privacy check before an Everyone post (demo).
@MainActor
final class Privacy210dUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func chooseEveryoneAndPost(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-demo-open", "-lime-demo-compose-photo"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        XCTAssertTrue(app.buttons["jam-next"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["jam-next"].isEnabled, "the photo alone is a post")
        app.buttons["jam-next"].tap()
        XCTAssertTrue(any(app, "jam-audience").waitForExistence(timeout: 8))
        any(app, "jam-audience").tap(); any(app, "audience-everyone").tap()
        any(app, "audience-confirm-everyone").tap()
        return app
    }

    func testAnEveryonePhotoPostNeedsTheConfirmationBeforeItGoes() {
        let app = chooseEveryoneAndPost([])
        XCTAssertTrue(any(app, "privacy-notice").waitForExistence(timeout: 8))
        XCTAssertEqual(any(app, "privacy-notice").label, "No students can be identified: faces, names or voices.")
        XCTAssertFalse(any(app, "privacy-faces").exists, "no face found")
        let post = app.buttons["jam-post"]
        XCTAssertFalse(post.isEnabled, "needs the confirmation")
        any(app, "privacy-guidance").tap()
        XCTAssertTrue(any(app, "privacy-guide").waitForExistence(timeout: 5))
        app.buttons["privacy-guide-done"].tap()
        any(app, "privacy-confirm").tap()
        XCTAssertTrue(post.isEnabled)
        post.tap()
        let globe = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-card-globe-'")).firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 10), "posted to everyone")
    }

    func testAPhotoWithFacesShowsAWarning() {
        let app = chooseEveryoneAndPost(["-lime-demo-faces"])
        XCTAssertTrue(any(app, "privacy-faces").waitForExistence(timeout: 8))
        XCTAssertTrue(any(app, "privacy-faces").label.contains("This photo has faces"), any(app, "privacy-faces").label)
        XCTAssertFalse(app.buttons["jam-post"].isEnabled, "a warning never replaces the confirmation")
    }

    func testANewAccountSeesWhenEveryoneOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-demo-open", "-lime-demo-new-account"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        let body = app.textViews["composer-field"]
        XCTAssertTrue(body.waitForExistence(timeout: 8))
        body.tap(); body.typeText("New here")
        app.buttons["jam-next"].tap()
        XCTAssertTrue(any(app, "jam-audience").waitForExistence(timeout: 8))
        any(app, "jam-audience").tap()
        let everyone = any(app, "audience-everyone")
        XCTAssertTrue(everyone.waitForExistence(timeout: 5))
        XCTAssertFalse(everyone.isEnabled, "locked for now")
        XCTAssertTrue(everyone.label.contains("opens"), everyone.label)
    }
}
