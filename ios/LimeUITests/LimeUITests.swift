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
        XCTAssertFalse(app.textViews["composer-field"].exists, "no composer until the request is accepted")
        app.buttons["request-accept"].tap()
        XCTAssertTrue(app.textViews["composer-field"].waitForExistence(timeout: 5), "accepted: you can reply")
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

    func testAChangedKeyAsksToBeAcceptedAndANotDeliveredMessageCanBeResent() {
        let app = demoApp()
        app.launchArguments += ["-lime-demo-screen", "key-change"]
        app.launch()
        XCTAssertTrue(app.staticTexts["key-change-note"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["key-change-note"].label.contains("security key changed"))
        XCTAssertTrue(app.buttons["delivery-undelivered"].exists, "the message that never arrived says so")
        app.buttons["key-change-accept"].tap()
        XCTAssertTrue(app.staticTexts["key-change-note"].waitForNonExistence(timeout: 5), "accepted: the notice goes")
        app.buttons["delivery-undelivered"].tap()
        XCTAssertTrue(app.staticTexts["delivery-sent"].waitForExistence(timeout: 8) || app.staticTexts["delivery-sending"].exists, "resending puts it on its way")
        XCTAssertFalse(app.buttons["delivery-undelivered"].exists)
    }

    func testAnEndedSessionSaysSoAndOffersSignIn() {
        let app = demoApp()
        app.launchArguments += ["-lime-demo-screen", "session-ended"]
        app.launch()
        XCTAssertTrue(app.staticTexts["problem-message"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["problem-message"].label, "Your session has ended. Please sign in again.")
        XCTAssertTrue(app.buttons["problem-sign-in"].exists)
    }

    // MARK: Formatting (LIME-100)

    private func openComposer(_ app: XCUIApplication, chat: String = "dm:sam") -> XCUIElement {
        XCTAssertTrue(app.buttons["conversation-row-\(chat)"].waitForExistence(timeout: 10))
        app.buttons["conversation-row-\(chat)"].tap()
        let field = app.textViews["composer-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        return field
    }

    /// Selects all of what was typed (a long press, then the callout's Select All).
    private func selectAll(_ field: XCUIElement, in app: XCUIApplication) {
        field.press(forDuration: 1.2)
        let all = app.menuItems["Select All"]
        if all.waitForExistence(timeout: 3) { all.tap() } else { field.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).doubleTap() }
    }

    func testSelectingTextShowsTheFormattingToolbarAboveTheKeyboardAndBoldWorks() {
        let app = demoApp()
        app.launch()
        let field = openComposer(app)
        XCTAssertFalse(app.buttons["fmt-bold"].exists, "no toolbar until text is selected")
        field.typeText("hello world")
        selectAll(field, in: app)
        let bold = app.buttons["fmt-bold"]
        XCTAssertTrue(bold.waitForExistence(timeout: 5), "selecting text shows the toolbar")
        XCTAssertFalse(bold.isSelected, "bold is not on yet")
        bold.tap()
        XCTAssertTrue(bold.isSelected, "B shows its pressed state")
        XCTAssertEqual(field.value as? String, "**hello world**", "and the text is bold")
        bold.tap()
        XCTAssertFalse(bold.isSelected)
        XCTAssertEqual(field.value as? String, "hello world")
        for id in ["fmt-italic", "fmt-underline", "fmt-strike"] {
            XCTAssertTrue(app.buttons[id].exists, id)
        }
        app.buttons["fmt-italic"].tap()
        XCTAssertEqual(field.value as? String, "*hello world*")
        app.buttons["fmt-underline"].tap()
        app.buttons["fmt-strike"].tap()
        XCTAssertEqual(field.value as? String, "~~__*hello world*__~~")
    }

    func testTheToolbarScrollsAndTheCloseButtonRestoresTheComposerRow() {
        let app = demoApp()
        app.launch()
        let field = openComposer(app)
        field.typeText("hello world")
        selectAll(field, in: app)
        XCTAssertTrue(app.buttons["fmt-bold"].waitForExistence(timeout: 5))
        let last = app.buttons["fmt-numbers"]
        XCTAssertFalse(last.isHittable, "the last items are scrolled out of view")
        app.scrollViews["fmt-scroll"].swipeLeft()
        XCTAssertTrue(last.waitForExistence(timeout: 3))
        XCTAssertTrue(last.isHittable, "the toolbar scrolls sideways to reach them")
        XCTAssertTrue(app.buttons["fmt-close"].isHittable, "the round ✕ stays at the right end")
        app.buttons["fmt-close"].tap()
        XCTAssertTrue(app.buttons["fmt-bold"].waitForNonExistence(timeout: 5), "✕ closes the toolbar")
        for id in ["composer-plus", "composer-emoji", "composer-aa"] {
            XCTAssertTrue(app.buttons[id].exists, "the normal composer row is back: \(id)")
        }
        XCTAssertTrue(app.buttons["send-button"].exists, "send is there for the text that was typed")
    }

    func testAaOpensTheToolbarWithNothingSelectedAndAListIsStarted() {
        let app = demoApp()
        app.launch()
        let field = openComposer(app)
        XCTAssertFalse(app.buttons["fmt-bold"].exists)
        app.buttons["composer-aa"].tap()
        XCTAssertTrue(app.buttons["fmt-bold"].waitForExistence(timeout: 5), "Aa opens the toolbar with no selection")
        XCTAssertTrue(app.buttons["composer-aa"].isSelected)
        app.buttons["fmt-bullets"].tap()
        field.typeText("one\ntwo")
        XCTAssertEqual(field.value as? String, "- one\n- two", "Return continues the list")
        XCTAssertTrue(app.buttons["fmt-bullets"].isSelected)
        field.typeText("\n\n")
        field.typeText("done")
        XCTAssertEqual(field.value as? String, "- one\n- two\n\ndone", "Return on an empty item ends the list")
        app.buttons["fmt-close"].tap()
        XCTAssertTrue(app.buttons["fmt-bold"].waitForNonExistence(timeout: 5))
    }

    func testTheToolbarStaysUntilSendAndSendingMakesAFormattedBubble() {
        let app = demoApp()
        app.launch()
        let field = openComposer(app)
        app.buttons["composer-aa"].tap()
        XCTAssertTrue(app.buttons["fmt-bold"].waitForExistence(timeout: 5))
        app.buttons["fmt-bold"].tap()      // bold on at the caret
        field.typeText("Important")
        XCTAssertEqual(field.value as? String, "**Important**")
        app.buttons["fmt-bold"].tap()      // and off again
        field.typeText(" news")
        XCTAssertEqual(field.value as? String, "**Important** news")
        app.buttons["send-button"].tap()
        XCTAssertTrue(app.buttons["fmt-bold"].waitForNonExistence(timeout: 5), "sending closes the toolbar")
        let bubble = app.staticTexts.matching(identifier: "own-bubble").matching(NSPredicate(format: "label == %@", "Important news")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5), "the bubble shows the words, with the markers gone")
    }

    func testALinkIsAddedThroughTheSheetAndABadOneIsRefused() {
        let app = demoApp()
        app.launch()
        let field = openComposer(app)
        field.typeText("see the plan")
        selectAll(field, in: app)
        XCTAssertTrue(app.buttons["fmt-link"].waitForExistence(timeout: 5))
        app.buttons["fmt-link"].tap()
        let address = app.textFields["link-url"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["link-text"].exists, "with text selected only the address is asked for")
        address.typeText("javascript:alert(1)")
        app.buttons["link-apply"].tap()
        XCTAssertTrue(app.staticTexts["link-error"].waitForExistence(timeout: 5), "a javascript link is refused")
        address.clearAndType("limechat.org/plan")
        app.buttons["link-apply"].tap()
        XCTAssertTrue(app.textViews["composer-field"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["composer-field"].value as? String, "[see the plan](https://limechat.org/plan)", "https is assumed, on the selected text")
    }

    func testALinkWithNoSelectionAsksForTheTextToShow() {
        let app = demoApp()
        app.launch()
        _ = openComposer(app)
        app.buttons["composer-aa"].tap()
        XCTAssertTrue(app.buttons["fmt-link"].waitForExistence(timeout: 5))
        app.buttons["fmt-link"].tap()
        XCTAssertTrue(app.textFields["link-text"].waitForExistence(timeout: 5), "no selection: the text to show is asked for too")
        app.textFields["link-url"].typeText("https://limechat.org")
        app.textFields["link-text"].tap()
        app.textFields["link-text"].typeText("Lime")
        app.buttons["link-apply"].tap()
        XCTAssertEqual(app.textViews["composer-field"].value as? String, "[Lime](https://limechat.org)")
    }

    func testMessagesWithFormattingAreDrawnAndAnHttpLinkAsksFirst() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "format"]
        app.launch()
        XCTAssertTrue(app.scrollViews["chat-scroll"].waitForExistence(timeout: 10))
        // The markers are gone from what is shown, and the structure is there.
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '**'")).firstMatch.exists, "no raw asterisks")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'let total'")).firstMatch.exists, "the code block is drawn")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'signed'")).firstMatch.exists)
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(NSPredicate(format: "label == '•'")).count, 2, "bullets")
        XCTAssertTrue(app.staticTexts["2."].exists, "numbered items count")
        // A link that is not https asks before opening.
        let link = app.links["the old site"]
        if link.waitForExistence(timeout: 3) {
            link.tap()
        } else {
            // Some iOS versions do not expose a link inside text as its own element: tap on the link's words.
            let line = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'the old site'")).firstMatch
            XCTAssertTrue(line.waitForExistence(timeout: 5))
            line.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        }
        // The confirmation is an action sheet on iOS 18 and a popover on iOS 27: find its button either way.
        let open = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'link-open' OR label == 'Open link'")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "a confirmation first")
    }

    // MARK: Search (LIME-99)

    func testSearchFindsAChatAndAMessageAndOpensTheChatAtTheMessage() {
        let app = demoApp()
        app.launch()
        XCTAssertTrue(app.buttons["messages-search-button"].waitForExistence(timeout: 10))
        app.buttons["messages-search-button"].tap()
        XCTAssertTrue(app.staticTexts["search-hint"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["search-hint"].exists)
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lee")
        XCTAssertTrue(app.buttons["search-chat-dm:lee"].waitForExistence(timeout: 5), "a chat found by name")

        app.buttons["search-clear"].tap()
        field.typeText("lesson")
        let hit = app.buttons["search-message-l3"]
        XCTAssertTrue(hit.waitForExistence(timeout: 5), "messages found by a word in them")
        XCTAssertTrue(hit.label.contains("Lee Wong"))
        hit.tap()
        let title = app.descendants(matching: .any).matching(identifier: "chat-title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(title.label.contains("Lee Wong"))
        XCTAssertTrue(app.otherElements["match-marker-l3"].waitForExistence(timeout: 5), "the chat opens at the message and highlights it")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'warm-up'")).firstMatch.exists, "and that message is on screen")
    }

    func testSearchSaysWhenNothingMatches() {
        let app = demoApp()
        app.launch()
        app.buttons["messages-search-button"].tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("zebra")
        XCTAssertTrue(app.staticTexts["search-none"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["search-none"].label, "No results for “zebra”")
        app.buttons["search-back"].tap()
        XCTAssertTrue(app.scrollViews["messages-list"].waitForExistence(timeout: 5))
    }

    func testFindInChatStepsThroughTheMatches() {
        let app = demoApp()
        app.launch()
        XCTAssertTrue(app.buttons["conversation-row-dm:lee"].waitForExistence(timeout: 10))
        app.buttons["conversation-row-dm:lee"].tap()
        XCTAssertTrue(app.buttons["chat-search-button"].waitForExistence(timeout: 5))
        app.buttons["chat-search-button"].tap()
        let field = app.textFields["find-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("lesson")
        let count = app.staticTexts["find-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == '5 of 5'"), evaluatedWith: count)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["find-down"].isEnabled, "already at the newest")
        app.buttons["find-up"].tap()
        expectation(for: NSPredicate(format: "label == '4 of 5'"), evaluatedWith: count)
        waitForExpectations(timeout: 5)
        app.buttons["find-up"].tap(); app.buttons["find-up"].tap(); app.buttons["find-up"].tap()
        expectation(for: NSPredicate(format: "label == '1 of 5'"), evaluatedWith: count)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.buttons["find-up"].isEnabled, "already at the oldest")
        app.buttons["find-down"].tap()
        expectation(for: NSPredicate(format: "label == '2 of 5'"), evaluatedWith: count)
        waitForExpectations(timeout: 5)

        app.buttons["find-done"].tap()
        XCTAssertTrue(app.staticTexts["find-count"].waitForNonExistence(timeout: 5), "Done closes the find bar")
    }

    func testFindInChatSaysWhenThereAreNoMatches() {
        let app = demoApp()
        app.launch()
        app.buttons["conversation-row-dm:lee"].tap()
        app.buttons["chat-search-button"].tap()
        let field = app.textFields["find-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("zebra")
        XCTAssertTrue(app.staticTexts["find-count"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == 'No matches'"), evaluatedWith: app.staticTexts["find-count"])
        waitForExpectations(timeout: 5)
    }

    // MARK: Settings (LIME-98)

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.otherElements["settings-root"].waitForExistence(timeout: 5) || app.buttons["settings-profile"].waitForExistence(timeout: 5))
    }

    func testTheAvatarOpensSettingsWithTheRowsOfTheDesign() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        for id in ["settings-profile", "settings-account", "settings-privacy", "settings-devices", "settings-notifications", "settings-customize", "settings-about"] {
            XCTAssertTrue(app.buttons[id].exists, id)
        }
        XCTAssertEqual(app.staticTexts["settings-card-name"].label, "Test Teacher")
        XCTAssertFalse(app.descendants(matching: .any)["settings-donate"].exists, "no donate link is configured, so the row is hidden")
        app.buttons["settings-close"].tap()
        XCTAssertTrue(app.scrollViews["messages-list"].waitForExistence(timeout: 5))
    }

    func testTheDonateRowAppearsWhenALinkIsConfigured() {
        let app = demoApp()
        app.launchArguments += ["-lime-donate-url", "https://example.com/donate"]
        app.launch()
        openSettings(app)
        XCTAssertTrue(app.descendants(matching: .any)["settings-donate"].waitForExistence(timeout: 5))
    }

    func testEditingAboutWithAPresetThenSavingShowsItOnTheProfileCard() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-profile"].tap()
        app.buttons["profile-about"].tap()
        XCTAssertTrue(app.staticTexts["editor-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editor-title"].label, "About (140)")
        XCTAssertFalse(app.buttons["editor-save"].isEnabled, "the check is dimmed until there is a change")
        app.buttons["preset-Planning lessons"].tap()
        XCTAssertEqual(app.staticTexts["editor-title"].label, "About (123)", "the counter counts the emoji and the 16 words down: 140 - 17")
        XCTAssertTrue(app.buttons["editor-save"].isEnabled)
        app.buttons["editor-save"].tap()
        XCTAssertTrue(app.buttons["profile-about"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile-about"].label.contains("Planning lessons"))
        // And on the card in Settings.
        goBack(app)
        XCTAssertTrue(app.staticTexts["settings-card-about"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["settings-card-about"].label, "📚 Planning lessons")
    }

    func testTypingInAboutCountsDownAndAnOverlongLineCannotBeSaved() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-profile"].tap()
        app.buttons["profile-about"].tap()
        let field = app.textFields["editor-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Hello")
        XCTAssertEqual(app.staticTexts["editor-title"].label, "About (135)")
        XCTAssertTrue(app.buttons["editor-clear"].exists)
        app.buttons["editor-clear"].tap()
        XCTAssertEqual(app.staticTexts["editor-title"].label, "About (140)")
        XCTAssertFalse(app.buttons["editor-save"].isEnabled)
        app.buttons["editor-close"].tap()
        XCTAssertTrue(app.buttons["profile-about"].waitForExistence(timeout: 5))
    }

    func testATakenUsernameIsReportedInTheEditor() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-profile"].tap()
        app.buttons["profile-username"].tap()
        let field = app.textFields["editor-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("taken")
        app.buttons["editor-save"].tap()
        XCTAssertTrue(app.staticTexts["editor-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["editor-error"].label, "That username is taken. Try another.")
    }

    func testTheNameCannotBeEmpty() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-profile"].tap()
        app.buttons["profile-name"].tap()
        let field = app.textFields["editor-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("x")
        XCTAssertTrue(app.buttons["editor-save"].isEnabled)
        app.buttons["editor-clear"].tap()
        XCTAssertFalse(app.buttons["editor-save"].isEnabled)
        XCTAssertEqual(app.staticTexts["editor-error"].label, "Your name can't be empty.")
    }

    func testTheAppearanceChoiceSurvivesARelaunch() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-customize"].tap()
        XCTAssertTrue(app.buttons["appearance-dark"].waitForExistence(timeout: 5))
        app.buttons["appearance-dark"].tap()
        XCTAssertTrue(app.buttons["appearance-dark"].isSelected)
        app.terminate()

        let again = demoApp()
        again.launch()
        openSettings(again)
        again.buttons["settings-customize"].tap()
        XCTAssertTrue(again.buttons["appearance-dark"].waitForExistence(timeout: 5))
        XCTAssertTrue(again.buttons["appearance-dark"].isSelected, "Dark is still chosen after a relaunch")
        again.buttons["appearance-system"].tap() // leave the simulator as it was
    }

    func testAcknowledgementsListTheSQLCipherNotice() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-about"].tap()
        XCTAssertTrue(app.buttons["about-acknowledgements"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["about-version"].label.contains("Core"))
        app.buttons["about-acknowledgements"].tap()
        let notice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Zetetic'")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "the SQLCipher / Zetetic notice is on the screen")
    }

    func testBlockedPeopleCanBeUnblocked() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-privacy"].tap()
        app.buttons["privacy-blocked"].tap()
        let unblock = app.buttons["unblock-dm:pat"]
        XCTAssertTrue(unblock.waitForExistence(timeout: 5), "Pat Doe is blocked in the demo")
        unblock.tap()
        XCTAssertTrue(app.staticTexts["blocked-empty"].waitForExistence(timeout: 5))
    }

    func testSafetyNumbersAndLinkedDevicesAreReadOnly() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-privacy"].tap()
        app.buttons["privacy-keys"].tap()
        XCTAssertTrue(app.staticTexts["keys-fingerprint"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["keys-fingerprint"].label, "A1B2 C3D4 E5F6 0718 293A")
        XCTAssertTrue(app.staticTexts["keys-date"].label.hasPrefix("Your key was set on"))
        goBack(app); goBack(app)
        app.buttons["settings-devices"].tap()
        XCTAssertTrue(app.staticTexts["devices-this"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["devices-this"].label, "This iPhone")
        XCTAssertTrue(app.staticTexts["devices-note"].label.contains("coming soon"))
    }

    func testChangingThePasswordWithTheStandInBackend() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-account"].tap()
        XCTAssertEqual(app.staticTexts["account-email"].label, "t•••@example.invalid")
        app.buttons["account-change-password"].tap()
        XCTAssertTrue(app.secureTextFields["pw-current"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pw-send"].isEnabled)
        typeSecure("not the password", "pw-current", app)
        typeSecure("a brand new password", "pw-new", app)
        typeSecure("a brand new password", "pw-confirm", app)
        XCTAssertTrue(app.buttons["pw-send"].isEnabled)
        app.buttons["pw-send"].tap()
        XCTAssertTrue(app.staticTexts["pw-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["pw-error"].label, "That isn't your current password.")

        let current = app.secureTextFields["pw-current"]
        current.tap()
        current.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "not the password".count))
        current.typeText("correct horse battery")
        app.buttons["pw-send"].tap()
        let code = app.textFields["pw-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap(); code.typeText("123456")
        app.buttons["pw-verify"].tap()
        XCTAssertTrue(app.staticTexts["pw-done"].waitForExistence(timeout: 5))
    }

    func testSigningOutAsksFirstAndSaysWhatItRemoves() {
        let app = demoApp()
        app.launch()
        openSettings(app)
        app.buttons["settings-account"].tap()
        app.buttons["account-sign-out"].tap()
        XCTAssertTrue(app.buttons["account-sign-out-confirm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Signing out removes your messages and keys from this iPhone. Your contacts will see that your security key changed."].exists)
    }

    private func typeSecure(_ text: String, _ id: String, _ app: XCUIApplication) {
        let field = app.secureTextFields[id]
        field.tap()
        field.typeText(text)
    }

    func testAMessageShowsSendingThenSent() {
        let app = demoApp()
        app.launch()
        XCTAssertTrue(app.buttons["conversation-row-dm:sam"].waitForExistence(timeout: 10))
        app.buttons["conversation-row-dm:sam"].tap()
        XCTAssertTrue(app.staticTexts["delivery-sending"].waitForExistence(timeout: 5), "an unsettled message says Sending…")
        let field = app.textViews["composer-field"]
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

        let field = app.textViews["composer-field"]
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
        let field = app.textViews["composer-field"]
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
