import XCTest

/// LIME-339: on an iPad with a hardware keyboard Return sends and Shift-Return makes a new line; on an iPhone Return makes a new line. The iPad test runs on an iPad
/// simulator (`./test-full.sh --device <iPad simulator> --only ReturnKey339UITests`) and says there is a hardware keyboard with a launch argument (the simulator's
/// keyboard is not a GCKeyboard); on the iPhone simulator it is skipped.
@MainActor
final class ReturnKey339UITests: LimeUITestCase {
    private func openChat(_ extra: [String]) -> (XCUIApplication, XCUIElement) {
        let app = signedInApp(extra)
        app.launch()
        let row = app.buttons["conversation-row-c2"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        return (app, field)
    }

    func testOnAnIPadWithAHardwareKeyboardReturnSendsAndShiftReturnMakesANewLine() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "an iPad simulator")
        let (app, field) = openChat(["-lime-fake-hardware-keyboard"])
        field.typeText("hello there")
        // Does this simulator deliver hardware key events at all? Shift-Return always makes a new line, so the text must change.
        field.typeKey(.return, modifierFlags: .shift)
        try XCTSkipIf((field.value as? String) == "hello there", "this simulator does not deliver hardware key events to the app (a headless run): check Return on a device or the Simulator app with Connect Hardware Keyboard")
        field.typeKey(.delete, modifierFlags: [])
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["hello there"].waitForExistence(timeout: 10), "Return sent it; field=\(String(describing: field.value))")
        let value = (field.value as? String) ?? ""
        XCTAssertTrue(value.isEmpty || value == "Send message...", "the composer is empty after sending: \(value)")
        // An empty draft: Return sends nothing and makes no new line.
        field.typeKey(.return, modifierFlags: [])
        let after = (field.value as? String) ?? ""
        XCTAssertTrue(after.isEmpty || after == "Send message...", "an empty draft stays empty: \(after)")
        // Shift-Return is a new line (the key is not the send command, so the text view handles it).
        field.typeText("first line")
        field.typeKey(.return, modifierFlags: .shift)
        field.typeText("second line")
        XCTAssertEqual((field.value as? String)?.replacingOccurrences(of: "\u{2028}", with: "\n"), "first line\nsecond line", "Shift-Return is a new line")
    }

    func testOnAnIPhoneReturnMakesANewLine() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "an iPhone simulator")
        let (_, field) = openChat([])
        field.typeText("first line")
        field.typeText("\n")
        field.typeText("second line")
        XCTAssertEqual((field.value as? String)?.replacingOccurrences(of: "\u{2028}", with: "\n"), "first line\nsecond line", "Return is a new line on an iPhone")
    }
}
