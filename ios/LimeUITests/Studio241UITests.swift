import XCTest

/// LIME-241: the podcast details page with a scrub line, small preview, one left margin, and the two steps (demo).
@MainActor
final class Studio241UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func recordedDetails() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-demo-open"]
        app.launch()
        app.buttons["new-jam-post"].tap(); app.buttons["jam-record"].tap()
        app.buttons["podcast-record"].tap()
        sleep(3)
        app.buttons["podcast-stop"].tap()
        XCTAssertTrue(app.buttons["podcast-play"].waitForExistence(timeout: 8))
        return app
    }

    func testThePreviewIsSmallTheFieldsShareOneLeftEdgeAndThePlayheadScrubs() {
        let app = recordedDetails()
        let window = app.windows.firstMatch.frame
        let preview = app.buttons["podcast-play"].frame
        XCTAssertEqual(preview.width / window.width, 0.45, accuracy: 0.06, "about 45% of the width: \(preview)")
        XCTAssertEqual(preview.midX, window.midX, accuracy: 4, "the preview is centred (LIME-242)")
        XCTAssertGreaterThan(any(app, "podcast-add-cover").frame.minY, any(app, "podcast-post-as").frame.maxY - 2, "Add cover is under the author row, so the name shows in full")
        XCTAssertEqual(any(app, "podcast-step").label, "Step 1 of 2")
        // One margin: Post as, Add cover, the title, the subtitle and the description start at the same x.
        let edges = [any(app, "podcast-post-as").frame.minX, any(app, "podcast-add-cover").frame.minX, any(app, "podcast-title").frame.minX, any(app, "podcast-subtitle").frame.minX, any(app, "podcast-description").frame.minX]
        for edge in edges { XCTAssertEqual(edge, edges[0], accuracy: 2, "left-aligned: \(edges)") }
        // The playhead: a line that moves when dragged, and says where it is.
        let head = any(app, "podcast-playhead")
        XCTAssertTrue(head.waitForExistence(timeout: 3))
        let before = head.value as? String ?? ""
        // Scrubbing: a drag on the track (not on a handle) moves the line, as in Photos.
        let end = any(app, "podcast-trim-end")
        end.coordinate(withNormalizedOffset: CGVector(dx: -3, dy: 0.5)).press(forDuration: 0.1, thenDragTo: end.coordinate(withNormalizedOffset: CGVector(dx: -9, dy: 0.5)))
        XCTAssertNotEqual(head.value as? String, before, "the playhead moved: \(before) -> \(String(describing: head.value))")
    }

    func testNextOpensBeforeYouPublishWithSeriesAudienceAndTagsThenPublish() {
        let app = recordedDetails()
        let title = any(app, "podcast-title")
        title.tap(); title.typeText("Pine walk")
        XCTAssertFalse(any(app, "jam-series").exists)
        app.buttons["podcast-next"].tap()
        XCTAssertTrue(app.navigationBars["Step 2 of 2"].waitForExistence(timeout: 8))
        for id in ["jam-series", "jam-audience", "jam-topics"] { XCTAssertTrue(any(app, id).exists, id) }
        XCTAssertEqual(app.buttons["podcast-post"].label, "Publish")
        // Everyone asks the student-privacy confirmation here.
        any(app, "jam-audience").tap(); any(app, "audience-everyone").tap(); any(app, "audience-confirm-everyone").tap()
        XCTAssertTrue(any(app, "privacy-notice").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["podcast-post"].isEnabled)
        any(app, "privacy-confirm").tap()
        app.buttons["podcast-post"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-audio-card-' OR identifier == 'jam-video'")).firstMatch.waitForExistence(timeout: 10), "published")
    }
}
