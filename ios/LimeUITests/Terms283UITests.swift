import XCTest

/// LIME-283 (demo): sign-up asks "people who teach, 18 or older" once, before the password; signing in does not.
@MainActor
final class Terms283UITests: LimeUITestCase {
    private func onboarding() -> XCUIApplication {
        onboardingApp()
    }

    private func toTheCode(_ app: XCUIApplication, identifier: String) {
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 10))
        app.buttons["welcome-continue"].tap()
        type(identifier, into: "identifier-field", in: app)
        app.buttons["next-button"].tap()
        XCTAssertTrue(app.buttons["confirm-yes"].waitForExistence(timeout: 10))
        app.buttons["confirm-yes"].tap()
    }

    func testSignUpShowsTheTermsScreenAndContinueWaitsForTheBox() {
        let app = onboarding()
        app.launch()
        toTheCode(app, identifier: "new.teacher@example.com")
        type("123456", into: "code-field", in: app)
        app.buttons["next-button"].tap()
        let box = app.descendants(matching: .any).matching(identifier: "terms-agree").firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["terms-link"].exists && app.buttons["privacy-link"].exists && app.buttons["guidelines-link"].exists)
        XCTAssertFalse(app.buttons["terms-continue"].isEnabled, "Continue waits for the box")
        box.tap()
        XCTAssertEqual(box.value as? String, "checked")
        XCTAssertTrue(app.buttons["terms-continue"].isEnabled)
        app.buttons["terms-continue"].tap()
        XCTAssertTrue(app.secureTextFields["password-field"].waitForExistence(timeout: 5), "then the password")
    }

    func testSigningInDoesNotAskAgain() {
        let app = onboarding()
        app.launch()
        toTheCode(app, identifier: "s.park")
        type("correct horse battery", into: "password-field", in: app, secure: true)
        app.buttons["next-button"].tap()
        XCTAssertTrue(app.textFields["code-field"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "terms-agree").firstMatch.exists)
    }
}
