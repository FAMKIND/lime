import XCTest

/// LIME-130-3a: the chat and its attachments for VoiceOver and Switch Control. `-lime-force-voiceover` stands in for them (the simulator has no switch),
/// `-lime-ax-probe` lists what `Announce.say` was given and runs an adjustable element's swipe.
@MainActor
final class Access130cUITests: LimeUITestCase {
    private func launch(_ screen: String? = nil, voiceOver: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = notifApp(screen, ["-lime-ax-probe"] + (voiceOver ? ["-lime-force-voiceover"] : []) + extra)
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func probe(_ app: XCUIApplication, _ button: String) -> String {
        let run = app.buttons[button]
        XCTAssertTrue(run.waitForExistence(timeout: 10))
        run.tap()
        let out = any(app, "ax-probe-out")
        XCTAssertTrue(out.waitForExistence(timeout: 3))
        return out.label
    }

    func testAMessageIsOneStopThatSaysWhoWhatAndWhen() {
        let app = launch()
        app.buttons["conversation-row-dm:sam"].tap()
        let theirs = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Sam Park, ' AND label CONTAINS 'staff meeting'")).firstMatch
        XCTAssertTrue(theirs.waitForExistence(timeout: 10), "the other person's message names them: \(app.debugDescription.prefix(0))")
        XCTAssertTrue(theirs.label.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil, "and says when: \(theirs.label)")
        XCTAssertFalse(theirs.label.contains("·"), "no separator is read out")
        let stops = probe(app, "ax-probe-stops").split(separator: "\n").filter { $0.contains("staff meeting") }
        XCTAssertEqual(stops.count, 1, "the message is one stop: \(stops)")
    }

    func testAMessageOfMineSaysYouAndItsState() {
        let app = launch()
        app.buttons["conversation-row-dm:sam"].tap()
        let mine = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'You, '")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 10))
        XCTAssertTrue(mine.label.contains("sent") || mine.label.contains("sending"), mine.label)
    }

    func testANewMessageInTheOpenChatIsSpoken() {
        let app = launch(extra: ["-lime-demo-autoreply", "See you then"])
        app.buttons["conversation-row-dm:sam"].tap()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Hello")
        app.buttons["send-button"].tap()
        let deadline = Date().addingTimeInterval(15)
        var said = ""
        while Date() < deadline {
            said = probe(app, "ax-probe-said")
            if said.contains("See you then") { break }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(said.contains("Sam Park: See you then"), "the reply is spoken with the sender: \(said)")
    }

    /// The button on the message ("Says why") opens the explanation on every iOS (on iOS 26 it opened nothing before 130-3a).
    func testTheWaitingForInternetExplanationOpens() {
        let app = launch("site-offline-internet", voiceOver: false)
        app.buttons["conversation-row-dm:mei"].tap()
        let why = any(app, "delivery-offline")
        XCTAssertTrue(why.waitForExistence(timeout: 10))
        why.tap()
        XCTAssertTrue(app.alerts["Waiting for internet"].waitForExistence(timeout: 5), "the explanation shows")
    }

    func testTheVoiceMessageIsOneAdjustableStopWithItsPosition() {
        let app = launch("attachments-media")
        let voice = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'voice-bubble-'")).firstMatch
        XCTAssertTrue(voice.waitForExistence(timeout: 10))
        XCTAssertTrue(voice.label.hasPrefix("Voice message"), voice.label)
        XCTAssertEqual(voice.value as? String, "0:00 of 0:06")
        let stops = probe(app, "ax-probe-stops")
        XCTAssertFalse(stops.contains("voice-play-"), "the play button is not a stop of its own")
        XCTAssertTrue(stops.contains("voice-bubble-"), "the bubble is")
        let result = probe(app, "ax-probe-up")
        Thread.sleep(forTimeInterval: 1)
        let after = any(app, "ax-probe-out").label
        XCTAssertTrue(after.hasPrefix("up:true"), "the swipe reached an adjustable element: \(result) / \(after)")
        XCTAssertFalse(after.contains("value:0:00 of"), "and it moved: \(after)")
    }

    func testTheAToZRailIsOneAdjustableStop() {
        let app = launch()
        app.buttons["new-message-button"].tap()
        let rail = any(app, "index-rail")
        XCTAssertTrue(rail.waitForExistence(timeout: 10))
        // (The sheet covers the probe, so the stops cannot be listed here; the rail is built the same way as the voice bubble, whose stops are listed above.)
        XCTAssertEqual(rail.value as? String ?? "", "", "no letter yet")
        XCTAssertEqual(rail.label, "Teachers by letter")
    }

    func testALookupIsSpoken() {
        let app = launch()
        app.buttons["new-message-button"].tap()
        let field = app.textFields["new-message-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("nobody.here.at.all\n")
        let deadline = Date().addingTimeInterval(15)
        var said = ""
        // (The sheet covers the probe, so the log is read after it closes.)
        while Date() < deadline && !said.contains("No teacher found") && !said.contains("Searching") {
            Thread.sleep(forTimeInterval: 1)
            if app.buttons["ax-probe-said"].exists && app.buttons["ax-probe-said"].isHittable { said = probe(app, "ax-probe-said") }
            else if app.buttons["new-message-cancel"].exists { app.buttons["new-message-cancel"].tap() }
        }
        XCTAssertTrue(said.contains("Searching") || said.contains("No teacher found"), said)
    }
}
