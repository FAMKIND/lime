import XCTest

/// LIME-130-2: the shared parts. Banners, toasts and errors are spoken (`-lime-ax-probe` lists what `Announce.say` was given), banners stay while VoiceOver
/// or Switch Control runs (`-lime-force-voiceover` stands in for it) and have Dismiss / Open actions, and the confirmation sheet scrolls.
@MainActor
final class Access130bUITests: LimeUITestCase {
    private func launch(_ screen: String? = nil, voiceOver: Bool = false, extra: [String] = []) -> XCUIApplication {
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

    private func copyAMessage(_ app: XCUIApplication) {
        app.buttons["conversation-row-dm:sam"].tap()
        longPress(app, "staff meeting")
        app.buttons["action-copy"].tap()
    }

    func testTheCopiedBannerIsSpokenAndStaysUntilDismissedWhileVoiceOverRuns() {
        let app = launch(voiceOver: true)
        XCTAssertTrue(app.buttons["conversation-row-dm:sam"].waitForExistence(timeout: 10))
        copyAMessage(app)
        let banner = any(app, "coming-soon-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "the app banner")
        XCTAssertTrue(probe(app, "ax-probe-said").contains("Copied"), "it was spoken")
        Thread.sleep(forTimeInterval: 7)
        XCTAssertTrue(banner.exists, "it stays past the touch time while VoiceOver runs")
        XCTAssertEqual(probe(app, "ax-probe-dismiss"), "dismiss:true", "it has a Dismiss action")
        XCTAssertTrue(banner.waitForNonExistence(timeout: 3), "and Dismiss removes it")
    }

    func testForTouchUsersTheBannerStaysAtLeastFourSecondsThenGoes() {
        let app = launch()
        XCTAssertTrue(app.buttons["conversation-row-dm:sam"].waitForExistence(timeout: 10))
        copyAMessage(app)
        let banner = any(app, "coming-soon-banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2.5)
        XCTAssertTrue(banner.exists, "still there after 2.5 s (it was 2 s in all before 130-2)")
        XCTAssertTrue(banner.waitForNonExistence(timeout: 6), "and gone by itself")
    }

    func testAnIncomingMessageBannerIsSpokenAndHasOpenAndDismissWhileVoiceOverRuns() {
        let app = launch("notif-banner", voiceOver: true)
        let banner = app.buttons["incoming-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertTrue(probe(app, "ax-probe-said").contains("Message from Lee Wong: Can you cover my bus duty"), "spoken with the sender and the first line")
        Thread.sleep(forTimeInterval: 7)
        XCTAssertTrue(banner.exists, "it stays while VoiceOver runs")
        XCTAssertEqual(probe(app, "ax-probe-dismiss"), "dismiss:true")
        XCTAssertTrue(banner.waitForNonExistence(timeout: 3))
    }

    func testAnErrorIsSpokenWhenItShows() {
        let app = launch()
        let field = openComposer(app)
        field.typeText("see the plan")
        selectAll(field, in: app)
        XCTAssertTrue(app.buttons["fmt-link"].waitForExistence(timeout: 5))
        app.buttons["fmt-link"].tap()
        let address = app.textFields["link-url"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.typeText("javascript:alert(1)")
        app.buttons["link-apply"].tap()
        let error = app.staticTexts["link-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        let words = error.label
        app.buttons["link-cancel"].tap()   // the sheet covers the probe
        XCTAssertTrue(probe(app, "ax-probe-said").contains(words), "the error text was spoken: \(words)")
    }

    func testTheConfirmSheetScrollsToCancelAtTheLargestSize() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime.text.follow", "NO", "-lime.text.step", "6"]
        app.launch()
        let row = app.buttons["conversation-row-dm:sam"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the row")
        row.swipeLeft()
        XCTAssertTrue(app.buttons["swipe-delete-dm:sam"].waitForExistence(timeout: 5), "the swipe action")
        app.buttons["swipe-delete-dm:sam"].tap()
        let delete = app.buttons["delete-chat-confirm"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the sheet's Delete")
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.exists, "Cancel is in the tree")
        var tries = 0
        while !cancel.isHittable && tries < 5 { app.scrollViews.firstMatch.swipeUp(); tries += 1 }
        XCTAssertTrue(cancel.isHittable, "Cancel can be scrolled to and tapped")
        cancel.tap()
        XCTAssertTrue(delete.waitForNonExistence(timeout: 5), "and it closes the sheet")
    }
}
