import XCTest

/// LIME-130-3b: a photo's description and a voice or video message's transcript.
@MainActor
final class Access130dUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func probe(_ app: XCUIApplication, _ button: String, waitFor: String? = nil) -> String {
        let run = app.buttons[button]
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        run.tap()
        let out = any(app, "ax-probe-out")
        XCTAssertTrue(out.waitForExistence(timeout: 3))
        if let waitFor {
            // The first request for Speech Recognition shows a system alert; answer it when it comes.
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let end = Date().addingTimeInterval(90)
            while Date() < end, !out.label.contains(waitFor) {
                for name in ["OK", "Allow", "Don’t Allow", "Don't Allow"] where springboard.alerts.buttons[name].exists { springboard.alerts.buttons[name].tap() }
                for name in ["OK", "Allow", "Don’t Allow", "Don't Allow"] where app.alerts.buttons[name].exists { app.alerts.buttons[name].tap() }
                Thread.sleep(forTimeInterval: 1)
            }
        }
        return out.label
    }

    func testAddingADescriptionMakesItTheBubblesLabelAndTheViewerShowsIt() {
        let app = threadApp("attachments-draft")
        app.launch()
        let describe = app.buttons.matching(identifier: "draft-describe").firstMatch
        XCTAssertTrue(describe.waitForExistence(timeout: 10), "each waiting photo offers a description")
        XCTAssertEqual(describe.label, "Add description")
        describe.tap()
        let field = app.textViews["description-field"].exists ? app.textViews["description-field"] : any(app, "description-field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("A red kite over the school field")
        app.buttons["description-save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'draft-describe' AND label == 'Edit description'")).firstMatch.waitForExistence(timeout: 5), "the first photo now has one")
        // Send them; the photo with the description is read by it, the other is "Photo" (never its file name).
        app.buttons["send-button"].tap()
        let described = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-image-' AND label == 'A red kite over the school field'")).firstMatch
        XCTAssertTrue(described.waitForExistence(timeout: 10), "VoiceOver reads the description")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-image-' AND label CONTAINS '.jpg'")).firstMatch.exists, "never the file name")
        described.tap()
        let toggle = app.buttons["attachment-description-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8), "the viewer has a Description toggle for a photo that has one")
        XCTAssertFalse(any(app, "attachment-description").exists, "hidden until asked")
        toggle.tap()
        let shown = any(app, "attachment-description")
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        XCTAssertEqual(shown.label, "A red kite over the school field")
    }

    func testShowTranscriptOnAVoiceMessageShowsTheDemoTextAndHidesAgain() {
        let app = threadApp("attachments-media")
        app.launch()
        let show = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'transcript-show-' OR label == 'Show transcript'")).firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10), "a voice message has Show transcript under it")
        show.tap()
        let text = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'transcript-text-'")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        XCTAssertTrue(text.label.contains("Please bring your reading folders"), text.label)
        app.buttons.matching(NSPredicate(format: "label == 'Hide transcript'")).firstMatch.tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 5))
    }

    func testAVideoMessageHasShowTranscriptToo() {
        let app = threadApp("attachments-media")
        app.launch()
        let video = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'attachment-video-'")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        let shows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'transcript-show-'"))
        XCTAssertGreaterThanOrEqual(shows.count, 3, "two voice messages and a video")
    }

    /// No network request is made by the app while it transcribes, even where the phone has no on-device language (so it says so).
    func testMakingATranscriptMakesNoNetworkCall() {
        let app = notifApp("attachments", ["-lime-ax-probe", "-lime-net-canary"])
        app.launch()
        let before = probe(app, "ax-probe-net")
        XCTAssertTrue(before.hasPrefix("net:0"), "nothing yet: \(before)")
        let result = probe(app, "ax-probe-transcribe", waitFor: "transcribe:")
        XCTAssertTrue(result.contains("transcribe:"), "it answered: \(result)")
        XCTAssertTrue(result.hasSuffix("net:0"), "no request was made while transcribing: \(result)")
        let after = probe(app, "ax-probe-net")
        XCTAssertTrue(after.hasPrefix("net:0"), after)
    }
}
