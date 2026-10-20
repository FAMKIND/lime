import XCTest

/// LIME-168: lime's own text size and typeface (Settings → Customize → Text size & font).
@MainActor
final class TextSizeUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func testThePageHasAPreviewTheSwitchTheSliderAndTheFonts() {
        let app = XCUIApplication()
        // The defaults as a new install has them (a launch argument wins over what an earlier test left stored).
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "settings/text-size", "-lime.text.follow", "YES", "-lime.text.step", "2", "-lime.text.font", "system"]
        app.launch()
        XCTAssertTrue(any(app, "text-size-preview").waitForExistence(timeout: 8), "the live preview")
        let follow = app.switches["text-size-follow"]
        XCTAssertTrue(follow.exists)
        XCTAssertEqual(follow.value as? String, "1", "by default lime uses the iPhone's text size")
        let slider = app.sliders["text-size-slider"]
        XCTAssertTrue(slider.exists)
        XCTAssertFalse(slider.isEnabled, "the slider waits for the switch to be turned off")
        follow.switches.firstMatch.tap()
        XCTAssertTrue(slider.isEnabled)
        slider.adjust(toNormalizedSliderPosition: 1.0)
        XCTAssertEqual(slider.value as? String, "Largest", "VoiceOver says the step: \(String(describing: slider.value))")
        XCTAssertEqual(any(app, "text-size-name").label, "Largest")
        // At the largest size the page is long: scroll to the slider (the preview scrolls in its own box, so the controls are never far).
        var swipes = 0
        while !slider.isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        slider.adjust(toNormalizedSliderPosition: 0.0)
        XCTAssertEqual(slider.value as? String, "Extra Small")
        // The font tab: six faces, one checked.
        app.segmentedControls["text-size-tabs"].buttons["Font"].tap()
        XCTAssertTrue(app.buttons["font-system"].waitForExistence(timeout: 5))
        for id in ["font-system", "font-figtree", "font-atkinson", "font-lexend", "font-mozillaText", "font-mozillaHeadline", "font-comicNeue", "font-newsreader", "font-lora"] {
            XCTAssertTrue(app.buttons[id].exists, id)
        }
        XCTAssertTrue(app.buttons["font-system"].isSelected)
        app.buttons["font-figtree"].tap()
        XCTAssertTrue(app.buttons["font-figtree"].isSelected)
        XCTAssertFalse(app.buttons["font-system"].isSelected)
    }

    /// At the largest accessibility size the chat, its composer and the long-press menu still fit the screen (closes 152d's "AX sizes not tried").
    func testAtTheLargestSizeTheChatTheComposerAndTheLongPressMenuStillFit() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime.text.follow", "NO", "-lime.text.step", "6"]
        app.launch()
        app.buttons["conversation-row-dm:sam"].tap()
        let screen = app.windows.firstMatch.frame
        let composer = app.textViews["composer-field"].exists ? app.textViews["composer-field"] : any(app, "composer-field")
        XCTAssertTrue(composer.waitForExistence(timeout: 8), "the composer")
        XCTAssertTrue(screen.contains(composer.frame), "the composer is on the screen: \(composer.frame)")
        let bubble = app.staticTexts["Are you coming to the staff meeting?"].firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        bubble.press(forDuration: 0.8)
        let reactions = any(app, "reaction-row"), lifted = any(app, "lifted-bubble"), actions = any(app, "message-actions")
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        for (name, frame) in [("reactions", reactions.frame), ("message", lifted.frame), ("actions", actions.frame)] {
            XCTAssertTrue(screen.contains(frame.insetBy(dx: 1, dy: 1)), "\(name) fits the screen at the largest size: \(frame) in \(screen)")
        }
        XCTAssertLessThanOrEqual(reactions.frame.maxY, lifted.frame.minY + 2)
        XCTAssertGreaterThanOrEqual(actions.frame.minY, lifted.frame.maxY - 2)
    }
}
