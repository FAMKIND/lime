import XCTest

/// LIME-276 (demo): drafts of podcasts and quick posts kept on this phone: save, list, reopen, publish (the draft goes), delete.
@MainActor
final class Drafts276UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func localRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-local-draft-' AND NOT identifier CONTAINS 'confirm'"))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-demo-open"]
        app.launch()
        return app
    }

    private func openDrafts(_ app: XCUIApplication) {
        let drafts = app.buttons["jam-segment-Drafts"]
        // The pills scroll with the feed: tapping a row further down scrolls the feed itself (the demo has many drafts), so come back to the top first (LIME-183c).
        for _ in 0..<8 where !drafts.waitForExistence(timeout: 1) { app.swipeDown() }
        XCTAssertTrue(drafts.waitForExistence(timeout: 10))
        for _ in 0..<4 where !drafts.isSelected {
            sleep(1)
            drafts.tap()
        }
    }

    func testAPodcastIsSavedAsADraftListedReopenedPublishedAndThenGone() {
        let app = launch()
        app.buttons["new-jam-post"].tap(); app.buttons["jam-record"].tap()
        app.buttons["podcast-record"].tap(); sleep(3); app.buttons["podcast-stop"].tap()
        XCTAssertTrue(app.buttons["podcast-play"].waitForExistence(timeout: 8))
        let title = any(app, "podcast-title"); title.tap(); title.typeText("Pine walk")
        // The discard sheet offers Save draft.
        app.buttons["podcast-close"].tap()
        XCTAssertTrue(app.buttons["podcast-close-save-draft"].waitForExistence(timeout: 5), "Discard / Save draft / Keep editing")
        app.buttons["podcast-close-save-draft"].tap()
        openDrafts(app)
        if !localRows(app).firstMatch.waitForExistence(timeout: 8) { print("DEBUGTREE", app.debugDescription) }
        XCTAssertTrue(localRows(app).firstMatch.exists, "Drafts lists it")
        XCTAssertTrue(localRows(app).firstMatch.label.contains("Pine walk") && localRows(app).firstMatch.label.contains("Podcast"), localRows(app).firstMatch.label)
        // Reopen: the recording and the words are back on the details page.
        localRows(app).firstMatch.tap()
        XCTAssertTrue(app.buttons["podcast-play"].waitForExistence(timeout: 10), "the details page with the recording")
        XCTAssertEqual(any(app, "podcast-title").value as? String, "Pine walk")
        // Next, Publish: the draft is gone.
        app.buttons["podcast-next"].tap()
        XCTAssertTrue(app.navigationBars["Step 2 of 2"].waitForExistence(timeout: 8))
        app.buttons["podcast-post"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-card-' OR identifier == 'jam-video'")).firstMatch.waitForExistence(timeout: 10), "published")
        openDrafts(app)
        XCTAssertFalse(localRows(app).firstMatch.waitForExistence(timeout: 3), "publishing deleted the draft")
    }

    func testTheMenuSavesADraftAndAQuickPostIsSavedFromTheCancelSheetThenDeletedBySwipe() {
        let app = launch()
        app.buttons["new-jam-post"].tap()
        let body = app.textViews["composer-field"]
        XCTAssertTrue(body.waitForExistence(timeout: 8))
        body.tap(); body.typeText("Seed swap on Friday")
        app.buttons["jam-compose-cancel"].tap()
        XCTAssertTrue(app.buttons["jam-compose-save-draft"].waitForExistence(timeout: 5), "Save draft / Discard / Keep writing")
        app.buttons["jam-compose-save-draft"].tap()
        openDrafts(app)
        let row = localRows(app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.contains("Seed swap on Friday") && row.label.contains("Post"), row.label)
        // Reopen: the words come back.
        row.tap()
        let again = app.textViews["composer-field"]
        XCTAssertTrue(again.waitForExistence(timeout: 8))
        expectation(for: NSPredicate(format: "value CONTAINS 'Seed swap on Friday'"), evaluatedWith: again)
        waitForExpectations(timeout: 8)
        app.buttons["jam-compose-cancel"].tap()
        // Nothing changed, so it asks again; Discard removes the draft.
        XCTAssertTrue(app.buttons["jam-compose-discard"].waitForExistence(timeout: 5))
        app.buttons["jam-compose-discard"].tap()
        openDrafts(app)
        XCTAssertFalse(localRows(app).firstMatch.waitForExistence(timeout: 3), "discarding a resumed draft deletes it")
    }

    func testASwipeDeletesALocalDraftAfterAsking() {
        let app = launch()
        app.buttons["new-jam-post"].tap()
        let body = app.textViews["composer-field"]
        XCTAssertTrue(body.waitForExistence(timeout: 8))
        body.tap(); body.typeText("To delete")
        app.buttons["jam-compose-cancel"].tap()
        app.buttons["jam-compose-save-draft"].tap()
        openDrafts(app)
        let row = localRows(app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        row.swipeLeft()
        let delete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swipe-local-draft-delete-'")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        any(app, "jam-local-draft-delete-confirm").tap()
        XCTAssertFalse(localRows(app).firstMatch.waitForExistence(timeout: 3))
    }
}
