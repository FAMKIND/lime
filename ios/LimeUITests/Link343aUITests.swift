import XCTest

/// LIME-343a (demo, a scripted other device): linking from the new device, and the phone's Linked Devices screen.
@MainActor
final class Link343aUITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func phoneApp(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-fake-lock-auth", "-lime-demo-screen", "settings/devices"] + extra
        return app
    }

    func testTheNewDeviceOffersLinkingShowsTheCodeAndTheTwoStepsThenOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-demo-move-offer"]
        app.launch()
        XCTAssertTrue(app.buttons["link-to-phone"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["move-start-fresh"].exists)
        app.buttons["link-to-phone"].tap()
        XCTAssertTrue(any(app, "link-qr").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "move-code").waitForExistence(timeout: 10))
        app.buttons["move-match"].tap()
        XCTAssertTrue(app.staticTexts["Getting your chats"].waitForExistence(timeout: 5), "the first step is named")
        XCTAssertTrue(any(app, "move-progress").exists)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "lime opens")
    }

    func testCancellingTheLinkGoesBackToTheChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-demo-move-offer"]
        app.launch()
        app.buttons["link-to-phone"].tap()
        XCTAssertTrue(any(app, "move-code").waitForExistence(timeout: 10))
        app.buttons["move-nomatch"].tap()
        XCTAssertTrue(app.buttons["link-to-phone"].waitForExistence(timeout: 5))
    }

    func testTheListShowsThisDeviceFirstAndOnlyAComputerCanBeUnlinked() {
        let app = phoneApp()
        app.launch()
        XCTAssertTrue(app.staticTexts["devices-this"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["device-unlink-demo-mac"].exists, "a computer can be unlinked")
        XCTAssertFalse(app.buttons["device-unlink-demo-ipad"].exists, "a tablet cannot, from here")
        XCTAssertTrue(any(app, "device-unlink-elsewhere-demo-ipad").exists, "it says where to do it")
        XCTAssertTrue(app.buttons["link-a-device"].exists)
    }

    func testUnlinkingAComputerAsksFirstThenRemovesIt() {
        let app = phoneApp()
        app.launch()
        app.buttons["device-unlink-demo-mac"].tap()
        let confirm = app.buttons.matching(identifier: "device-unlink-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "a confirmation first")
        confirm.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.buttons["device-unlink-demo-mac"])
        waitForExpectations(timeout: 10)
    }

    func testFiveOfFiveSaysUnlinkOneFirst() {
        let app = phoneApp(extra: ["-lime-demo-devices-full"])
        app.launch()
        XCTAssertTrue(any(app, "devices-full").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["link-a-device"].exists)
    }

    func testThePhoneTakesACodeComparesItAndLinks() {
        let app = phoneApp()
        app.launch()
        app.buttons["link-enter"].tap()
        let field = app.textFields["link-code-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("lime-link-v1:demo")
        app.buttons["link-continue-code"].tap()
        XCTAssertTrue(any(app, "move-code").waitForExistence(timeout: 10))
        app.buttons["move-match"].tap()
        XCTAssertTrue(any(app, "link-linked").waitForExistence(timeout: 30), "Device linked")
        app.buttons["link-done"].tap()
        XCTAssertTrue(app.buttons["link-a-device"].waitForExistence(timeout: 5))
    }
}
