import XCTest

/// LIME-130-1: the message actions, the voice recording and the call controls for VoiceOver, Switch Control and Voice Control. XCTest cannot list custom
/// actions, so `-lime-ax-probe` (debug builds) walks the app's accessibility tree and prints it; the simulator has no VoiceOver switch, so
/// `-lime-force-voiceover` stands in for it in the call.
@MainActor
final class Access130UITests: XCTestCase {
    private func chat(_ screen: String = "attachments") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", screen, "-lime-ax-probe"]
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

    func testEveryMessageElementOffersTheMenusActionsInTheMenusOrder() {
        let app = chat()
        XCTAssertTrue(any(app, "other-bubble").waitForExistence(timeout: 10) || any(app, "own-bubble").waitForExistence(timeout: 3))
        let dump = probe(app, "ax-probe-dump")
        let lines = dump.split(separator: "\n").map(String.init)
        func actions(_ label: String) -> String? { lines.first { $0.hasPrefix(label) }?.components(separatedBy: " | ").last }
        XCTAssertEqual(actions("Trip 1"), "React, Reply, Forward, Copy, Select, Report, Delete, More actions", "someone else's photo, in the menu's order:\n\(dump)")
        XCTAssertEqual(actions("Field trip photos"), "React, Reply, Forward, Copy, Select, Report, Delete, More actions", "someone else's words:\n\(dump)")
        XCTAssertEqual(actions("Permission slip.pdf"), "React, Reply, Forward, Select, Report, Delete, More actions", "a file:\n\(dump)")
        XCTAssertEqual(actions("Poster"), "React, Reply, Forward, Copy, Select, Delete, More actions", "my photo (no caption, so no Edit, no Report):\n\(dump)")
    }

    func testMoreActionsOpensTheMenuAndEscapeClosesIt() {
        let app = chat()
        XCTAssertTrue(any(app, "other-bubble").waitForExistence(timeout: 10))
        XCTAssertEqual(probe(app, "ax-probe-more"), "more:true")
        XCTAssertTrue(any(app, "message-actions").waitForExistence(timeout: 3), "the same overlay the long-press opens")
        XCTAssertTrue(app.buttons["action-delete"].exists && app.buttons["reply-in-thread"].exists, "its buttons are labelled")
        XCTAssertEqual(app.buttons["action-delete"].label, "Delete")
        XCTAssertEqual(probe(app, "ax-probe-escape"), "escape:true")
        XCTAssertFalse(any(app, "message-actions").waitForExistence(timeout: 2), "Escape closes it")
    }

    func testAnAccessibilityActivationOfTheMicStartsALockedRecording() {
        let app = chat()
        let mic = any(app, "composer-mic")
        XCTAssertTrue(mic.waitForExistence(timeout: 10))
        XCTAssertEqual(mic.label, "Record voice message")
        let before = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'voice-bubble-'")).count
        XCTAssertEqual(probe(app, "ax-probe-mic"), "mic:true")
        XCTAssertTrue(app.buttons["voice-send"].waitForExistence(timeout: 5), "locked, with Send")
        XCTAssertEqual(app.buttons["voice-send"].label, "Send voice message")
        XCTAssertEqual(app.buttons["voice-cancel"].label, "Cancel recording")
        let time = any(app, "recording-time")
        XCTAssertTrue(time.exists)
        XCTAssertEqual(time.label, "Recording", "the recording element")
        XCTAssertTrue((time.value as? String ?? "").contains("second"), "with the time so far as its value: \(String(describing: time.value))")
        sleep(1)
        app.buttons["voice-send"].tap()
        let sent = NSPredicate(format: "count == %d", before + 1)
        expectation(for: sent, evaluatedWith: app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'voice-bubble-'")))
        waitForExpectations(timeout: 8)
        XCTAssertFalse(any(app, "recording-bar").exists)
        // The voice message just sent has the message actions too.
        let dump = probe(app, "ax-probe-dump")
        XCTAssertTrue(dump.split(separator: "\n").contains { $0.contains("voice message") && $0.hasSuffix("Delete, More actions") }, "a voice message has them:\n\(dump)")
    }

    func testCancelFromALockedRecordingSendsNothing() {
        let app = chat()
        XCTAssertTrue(any(app, "composer-mic").waitForExistence(timeout: 10))
        let before = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'voice-bubble-'")).count
        _ = probe(app, "ax-probe-mic")
        XCTAssertTrue(app.buttons["voice-cancel"].waitForExistence(timeout: 5))
        app.buttons["voice-cancel"].tap()
        XCTAssertFalse(any(app, "recording-bar").waitForExistence(timeout: 2))
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'voice-bubble-'")).count, before)
    }

    // MARK: Calls

    private func call(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-call", "video"] + extra
        app.launch()
        return app
    }

    func testWithVoiceOverRunningTheVideoControlsStayAfterTenSeconds() {
        let app = call(["-lime-force-voiceover"])
        let end = app.buttons["call-end"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        sleep(10)
        XCTAssertTrue(end.isHittable, "still there after 10 s")
        XCTAssertTrue(app.buttons["call-mute"].isHittable)
        XCTAssertFalse(any(app, "call-show-controls").exists, "nothing to show: they never hid")
    }

    func testForTouchUsersThePictureBecomesAShowCallControlsButtonWhenTheControlsHide() {
        let app = call()
        let end = app.buttons["call-end"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        XCTAssertFalse(any(app, "call-show-controls").exists, "while the controls show, there is no such element")
        let hidden = NSPredicate { _, _ in !end.isHittable }
        expectation(for: hidden, evaluatedWith: nil)
        waitForExpectations(timeout: 12)
        let show = any(app, "call-show-controls")
        XCTAssertTrue(show.waitForExistence(timeout: 3))
        XCTAssertEqual(show.label, "Show call controls")
        // An accessibility activation brings the controls back.
        XCTAssertTrue(show.isHittable || show.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        let back = NSPredicate { _, _ in end.isHittable }
        expectation(for: back, evaluatedWith: nil)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(any(app, "call-show-controls").exists)
    }
}
