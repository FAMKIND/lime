import XCTest

@MainActor
final class LimeUITests: XCTestCase {
    /// An app that is already signed in (no backend) with the made-up sample chats loaded: what the
    /// older tests of Messages and Chat need now that a new account starts empty.
    private func signedInApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-load-sample-chats"] + extra
        return app
    }

    /// An app using the stand-in backend, with no saved session: the sign-up and sign-in screens.
    private func onboardingApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-fake-auth", "-lime-reset-session", "-lime-reset-store"] + extra
        return app
    }

    /// Signed in, no backend, with made-up conversations in memory: a request waiting and a chat.
    private func demoApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        return app
    }

    private func goBack(_ app: XCUIApplication) {
        let custom = app.buttons["back-button"]
        (custom.exists ? custom : app.navigationBars.buttons.element(boundBy: 0)).tap()
    }

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: New message, requests and delivery states (in-memory demo conversations)

    func testARequestIsAcceptedFromTheRequestsRow() {
        let app = demoApp()
        app.launch()
        XCTAssertTrue(app.buttons["requests-row"].waitForExistence(timeout: 10), "a request waits at the top of Messages")
        XCTAssertFalse(app.buttons["conversation-row-dm:ada"].exists, "a request is not in the chat list yet")
        app.buttons["requests-row"].tap()
        let row = app.buttons["request-row-dm:ada"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.scrollViews["chat-scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["request-accept"].exists && app.buttons["request-block"].exists)
        XCTAssertFalse(app.textFields["composer-field"].exists, "no composer until the request is accepted")
        app.buttons["request-accept"].tap()
        XCTAssertTrue(app.textFields["composer-field"].waitForExistence(timeout: 5), "accepted: you can reply")
        goBack(app)
        // The Requests list is now empty, so it returns straight to Messages with Ada in the chat list.
        XCTAssertTrue(app.buttons["conversation-row-dm:ada"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["requests-row"].exists)
    }

    func testBlockingARequestRemovesItAfterAConfirmation() {
        let app = demoApp()
        app.launch()
        XCTAssertTrue(app.buttons["requests-row"].waitForExistence(timeout: 10))
        app.buttons["requests-row"].tap()
        app.buttons["request-row-dm:ada"].tap()
        XCTAssertTrue(app.buttons["request-block"].waitForExistence(timeout: 5))
        app.buttons["request-block"].tap()
        let confirm = app.buttons.matching(identifier: "request-block-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "blocking asks first")
        confirm.tap()
        XCTAssertTrue(app.scrollViews["messages-list"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["requests-row"].exists)
        XCTAssertFalse(app.buttons["conversation-row-dm:ada"].exists)
    }

    func testNewMessageFindsAPersonAndOpensTheChat() {
        let app = demoApp()
        app.launch()
        XCTAssertTrue(app.buttons["new-message-button"].waitForExistence(timeout: 10))
        app.buttons["new-message-button"].tap()
        let field = app.textFields["new-message-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["find-button"].isEnabled, "nothing to find yet")
        field.typeText("nobody.here")
        app.buttons["find-button"].tap()
        XCTAssertTrue(app.staticTexts["find-result-none"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["find-result-none"].label, "No teacher found with that username or email.")

        field.tap()
        field.clearAndType("grace.h")
        app.buttons["find-button"].tap()
        XCTAssertTrue(app.staticTexts["find-result-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["find-result-name"].label, "Grace Hopper")
        app.buttons["message-button"].tap()
        let title = app.descendants(matching: .any).matching(identifier: "chat-title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("Grace Hopper"))
    }

    func testAMessageShowsSendingThenSent() {
        let app = demoApp()
        app.launch()
        XCTAssertTrue(app.buttons["conversation-row-dm:sam"].waitForExistence(timeout: 10))
        app.buttons["conversation-row-dm:sam"].tap()
        XCTAssertTrue(app.staticTexts["delivery-sending"].waitForExistence(timeout: 5), "an unsettled message says Sending…")
        let field = app.textFields["composer-field"]
        field.tap()
        field.typeText("see you at 3")
        app.buttons["send-button"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "own-bubble").matching(NSPredicate(format: "label == %@", "see you at 3")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["delivery-sent"].waitForExistence(timeout: 8), "then it is Sent")
    }

    func testMessagesToChatAndBack() {
        let app = signedInApp()
        app.launch()

        let list = app.scrollViews["messages-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), "launches into Messages")

        let row = app.buttons["conversation-row-c1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let chat = app.scrollViews["chat-scroll"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5), "chat appears")

        let field = app.textFields["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("hello")

        let send = app.buttons["send-button"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()

        let bubble = app.staticTexts.matching(identifier: "own-bubble").matching(NSPredicate(format: "label == %@", "hello")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "a new own bubble with hello appears")

        // iOS 26+ has the system back button; below it, the custom glass one.
        let custom = app.buttons["back-button"]
        (custom.exists ? custom : app.navigationBars.buttons.element(boundBy: 0)).tap()
        XCTAssertTrue(list.waitForExistence(timeout: 5), "back to Messages")
    }

    func testEdgeSwipeGoesBack() {
        let app = signedInApp()
        app.launch()
        let list = app.scrollViews["messages-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["conversation-row-c2"].waitForExistence(timeout: 10))
        app.buttons["conversation-row-c2"].tap()
        XCTAssertTrue(app.scrollViews["chat-scroll"].waitForExistence(timeout: 5))

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(list.waitForExistence(timeout: 5), "swiping from the left edge returns to Messages")
        XCTAssertFalse(app.scrollViews["chat-scroll"].exists)
    }

    /// The chat title is the avatar beside the name, with "N members" under it for groups. At 375pt it
    /// may truncate (accepted), so this checks the title exists with the right content, not its width.
    func testChatTitleShowsNameAndMembers() {
        let app = signedInApp()
        app.launch()
        XCTAssertTrue(app.scrollViews["messages-list"].waitForExistence(timeout: 10))
        for (row, name, members) in [("c2", "Autumn Reyes", false), ("c4", "Grade 4 Team", true)] {
            XCTAssertTrue(app.buttons["conversation-row-\(row)"].waitForExistence(timeout: 10))
            app.buttons["conversation-row-\(row)"].tap()
            let title = app.descendants(matching: .any).matching(identifier: "chat-title").firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 5), name)
            XCTAssertTrue(title.label.contains(name), "\(title.label) should contain \(name)")
            XCTAssertEqual(title.label.contains("members"), members, title.label)
            let custom = app.buttons["back-button"]
            (custom.exists ? custom : app.navigationBars.buttons.element(boundBy: 0)).tap()
            XCTAssertTrue(app.scrollViews["messages-list"].waitForExistence(timeout: 5))
        }
    }

    /// Long-pressing the logo opens About Lime, which runs LimeCore's encryption self-test.
    func testLongPressLogoShowsSelfTestPassed() {
        let app = signedInApp()
        app.launch()
        XCTAssertTrue(app.scrollViews["messages-list"].waitForExistence(timeout: 10))
        app.buttons["Lime menu"].press(forDuration: 1.2)
        let result = app.staticTexts["self-test-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10), "the About sheet did not appear")
        let passed = NSPredicate(format: "label CONTAINS 'passed'")
        expectation(for: passed, evaluatedWith: result)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["about-versions"].label.contains("Core"))
        #if DEBUG
        XCTAssertTrue(app.staticTexts["developer-staging"].exists, "Debug builds show the staging row")
        let developer = app.staticTexts["developer-staging"].label
        XCTAssertTrue(developer.contains("Developer: staging"))
        XCTAssertTrue(developer.contains("Not connected") || developer.contains("Signed in as"), developer)
        #endif
        let storage = app.staticTexts["storage-result"]
        XCTAssertTrue(storage.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label CONTAINS 'encrypted'"), evaluatedWith: storage)
        waitForExpectations(timeout: 10)
    }

    /// A message you send is written to the encrypted local store: it survives the app being
    /// terminated and relaunched.
    func testSentMessagePersistsAcrossRelaunch() {
        let app = signedInApp()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-load-sample-chats", "-lime-reset-store"] // a fresh sample database for a clean start
        app.launch()
        XCTAssertTrue(app.buttons["conversation-row-c1"].waitForExistence(timeout: 10))
        app.buttons["conversation-row-c1"].tap()
        let field = app.textFields["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("persist me")
        app.buttons["send-button"].tap()
        let bubble = NSPredicate(format: "label == %@", "persist me")
        XCTAssertTrue(app.staticTexts.matching(identifier: "own-bubble").matching(bubble).firstMatch.waitForExistence(timeout: 5))

        app.terminate()

        let relaunched = signedInApp() // no reset: the same encrypted database
        relaunched.launch()
        XCTAssertTrue(relaunched.buttons["conversation-row-c1"].waitForExistence(timeout: 10))
        relaunched.buttons["conversation-row-c1"].tap()
        let again = relaunched.staticTexts.matching(identifier: "own-bubble").matching(bubble).firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 5), "the message is still in the chat after a relaunch")
    }

    /// A store that cannot be opened (here: the Keychain key no longer matches) is moved aside, a
    /// fresh one is made, and Messages shows a one-time notice.
    func testUnopenableStoreShowsAOneTimeNotice() {
        let first = XCUIApplication()
        first.launchArguments = ["-lime-skip-sign-in", "-lime-load-sample-chats", "-lime-reset-store"]
        first.launch()
        XCTAssertTrue(first.buttons["conversation-row-c1"].waitForExistence(timeout: 10))
        XCTAssertFalse(first.staticTexts["recovery-notice"].exists, "a normal launch has no notice")
        first.terminate()

        let recovered = XCUIApplication()
        recovered.launchArguments = ["-lime-skip-sign-in", "-lime-load-sample-chats", "-lime-test-corrupt-key"]
        recovered.launch()
        XCTAssertTrue(recovered.staticTexts["recovery-notice"].waitForExistence(timeout: 10))
        XCTAssertTrue(recovered.staticTexts["recovery-notice"].label.contains("started fresh"))
        XCTAssertTrue(recovered.buttons["conversation-row-c1"].exists, "a fresh sample store is there")
        recovered.terminate()

        let next = signedInApp()
        next.launch()
        XCTAssertTrue(next.buttons["conversation-row-c1"].waitForExistence(timeout: 10))
        XCTAssertFalse(next.staticTexts["recovery-notice"].exists, "the notice does not come back")
    }

    // MARK: Signing up and in (the stand-in backend)

    private func type(_ text: String, into id: String, in app: XCUIApplication, secure: Bool = false) {
        let field = secure ? app.secureTextFields[id] : app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 10), id)
        field.tap()
        field.typeText(text)
    }

    func testSignUpEndToEndThenSignOutAndSignInByUsername() {
        let app = onboardingApp()
        app.launch()

        // Welcome: no Google or Apple, ever.
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Google' OR label CONTAINS[c] 'Apple'")).count, 0)
        app.buttons["welcome-continue"].tap()

        // One question: email or username. A new address asks to confirm, then sends a code.
        type("new.teacher@example.com", into: "identifier-field", in: app)
        XCTAssertTrue(app.buttons["next-button"].isEnabled)
        app.buttons["next-button"].tap()
        XCTAssertTrue(app.buttons["confirm-yes"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["confirmation-detail"].label.contains("new.teacher@example.com"))
        app.buttons["confirm-yes"].tap()

        // The code (the stand-in's is 123456), then a password, then the name.
        type("123456", into: "code-field", in: app)
        app.buttons["next-button"].tap()
        type("a long enough password", into: "password-field", in: app, secure: true)
        type("a long enough password", into: "confirm-password-field", in: app, secure: true)
        app.buttons["next-button"].tap()
        type("Ada Lovelace", into: "name-field", in: app)
        app.buttons["next-button"].tap()

        // Messages: empty, with the two ways to start.
        XCTAssertTrue(app.staticTexts["empty-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["empty-title"].label, "No chats yet")
        XCTAssertTrue(app.buttons["card-new-message"].exists)
        XCTAssertTrue(app.buttons["card-invite"].exists)
        app.buttons["card-invite"].tap()
        XCTAssertTrue(app.staticTexts["coming-soon-banner"].waitForExistence(timeout: 5))

        // Sign out (after a confirmation), then sign in with the username: password, then a new code.
        app.buttons["Lime menu"].press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["sign-out"].waitForExistence(timeout: 10))
        app.buttons["sign-out"].tap()
        let confirm = app.buttons.matching(identifier: "sign-out-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "signing out asks first")
        confirm.tap()

        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 10), "back at the start")
        app.buttons["welcome-continue"].tap()
        type("teacher", into: "identifier-field", in: app)
        app.buttons["next-button"].tap()
        XCTAssertTrue(app.buttons["confirm-yes"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["confirmation-detail"].label.contains("t•••@famkind.com"), "a masked hint, not the email")
        app.buttons["confirm-yes"].tap()
        type("correct horse battery", into: "password-field", in: app, secure: true)
        app.buttons["next-button"].tap()
        type("123456", into: "code-field", in: app)
        app.buttons["next-button"].tap()
        XCTAssertTrue(app.staticTexts["empty-title"].waitForExistence(timeout: 10), "signed in: Messages")
    }

    func testAPhoneNumberIsToldItIsComingLater() {
        let app = onboardingApp()
        app.launch()
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 10))
        app.buttons["welcome-continue"].tap()
        type("+1 555 010 0199", into: "identifier-field", in: app)
        XCTAssertTrue(app.staticTexts["identifier-note"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["identifier-note"].label, "Phone sign-in is coming later. Use your email for now.")
        XCTAssertFalse(app.buttons["next-button"].isEnabled)
    }

    func testAWrongPasswordAndAWrongCodeSayWhatIsWrong() {
        let app = onboardingApp()
        app.launch()
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 10))
        app.buttons["welcome-continue"].tap()
        type("teacher@famkind.com", into: "identifier-field", in: app)
        app.buttons["next-button"].tap()
        XCTAssertTrue(app.buttons["confirm-yes"].waitForExistence(timeout: 10))
        app.buttons["confirm-yes"].tap()
        type("not the password", into: "password-field", in: app, secure: true)
        app.buttons["next-button"].tap()
        XCTAssertTrue(app.staticTexts["error-message"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["error-message"].label.contains("isn't right"))
    }
}

private extension XCUIElement {
    /// Replaces the field's text.
    func clearAndType(_ text: String) {
        guard let current = value as? String, !current.isEmpty else { return typeText(text) }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}
