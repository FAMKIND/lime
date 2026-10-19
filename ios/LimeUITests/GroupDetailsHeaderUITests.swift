import XCTest

/// LIME-152h: the group details page has the same top-right actions as a profile: Mute, Pin and ⋯.
@MainActor
final class GroupDetailsHeaderUITests: LimeUITestCase {
    func testGroupDetailsHasMutePinAndTheMenuLikeAProfile() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "group-details"]
        app.launch()
        let mute = app.buttons["group-mute"], pin = app.buttons["group-pin"], more = app.buttons["group-more"]
        XCTAssertTrue(mute.waitForExistence(timeout: 8), "the bell")
        XCTAssertTrue(pin.exists, "the pin")
        XCTAssertTrue(more.exists, "the ⋯ menu")
        XCTAssertLessThan(mute.frame.minX, pin.frame.minX)
        XCTAssertLessThan(pin.frame.minX, more.frame.minX, "bell, pin, ⋯ from left to right")
        // Mute opens the same choices as a profile's, and muting turns the bell into the muted one.
        mute.tap()
        XCTAssertTrue(app.buttons["mute-hour"].waitForExistence(timeout: 5))
        app.buttons["mute-hour"].tap()
        XCTAssertTrue(app.buttons["group-mute"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["group-mute"].label, "Unmute")
        // Pin toggles.
        XCTAssertEqual(pin.label, "Pin")
        pin.tap()
        XCTAssertEqual(app.buttons["group-pin"].label, "Unpin")
        // The menu holds what the page already offers.
        more.tap()
        XCTAssertTrue(app.buttons["group-more-leave"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["group-more-add"].exists)
        XCTAssertTrue(app.buttons["group-more-rename"].exists)
        XCTAssertTrue(app.buttons["group-more-delete"].exists, "the owner can delete")
    }
}
