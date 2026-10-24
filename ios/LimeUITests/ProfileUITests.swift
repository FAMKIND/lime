import XCTest

/// The contact profile (LIME-122a), in the made-up chat with Sam.
@MainActor
final class ProfileUITests: XCTestCase {
    private func app(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"] + extra
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testTappingTheTitleOfADirectChatOpensTheProfileWithHandleSchoolAboutAndStatus() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        XCTAssertTrue(any(app, "chat-title").waitForExistence(timeout: 8))
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["profile-name"].label, "Sam Park")
        XCTAssertEqual(app.staticTexts["profile-handle"].label, "@sam.park")
        XCTAssertEqual(app.staticTexts["profile-school-line"].label, "\u{1F3EB} Lincoln Elementary", "the school on its own line")
        XCTAssertTrue(app.staticTexts["profile-status"].exists, "the status they shared")
        XCTAssertTrue(app.buttons["profile-message"].exists && app.buttons["profile-call-button"].exists)
        XCTAssertTrue(app.staticTexts["profile-about"].label.contains("fractions"), "About")
        XCTAssertTrue(app.buttons["profile-handle"].exists && app.buttons["profile-label"].exists, "the details card")
    }

    func testTheMoreMenusProfileItemOpensIt() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        XCTAssertTrue(app.buttons["chat-more"].waitForExistence(timeout: 8))
        app.buttons["chat-more"].tap()
        XCTAssertTrue(app.buttons["chat-profile"].waitForExistence(timeout: 5))
        app.buttons["chat-profile"].tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
    }

    func testTheSharedSectionListsWhatSamSharedAndCopyingTheUsernameToasts() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        app.buttons["profile-tab-Shared"].tap()
        XCTAssertTrue(any(app, "profile-links").waitForExistence(timeout: 5), "the link Sam sent")
        XCTAssertTrue(any(app, "profile-files").exists, "and the file")
        app.buttons["profile-tab-Info"].tap()
        app.buttons["profile-handle"].tap()
        XCTAssertTrue(any(app, "profile-copied").waitForExistence(timeout: 3), "Copied")
    }

    func testCallDatesOnTheProfileAreOneLineEach() {
        let app = app(["-lime-demo-calls"])
        app.tabBars.buttons["call"].tap()
        app.buttons.matching(identifier: "call-row-avatar").element(boundBy: 1).tap()   // Sam (the picture opens the details, LIME-170)
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        let lines = app.descendants(matching: .any).matching(identifier: "profile-call-line")
        XCTAssertTrue(lines.firstMatch.waitForExistence(timeout: 5))
        for line in lines.allElementsBoundByIndex { XCTAssertLessThan(line.frame.height, 60, "a call is one line: \(line.label)") }
    }

    // MARK: LIME-122a2

    func testYourHeaderAvatarOpensYourProfileWithItsCardsAndSignOutAsksFirst() {
        let app = app()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
        app.buttons["settings-button"].tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["profile-change-status"].exists && app.buttons["profile-edit"].exists && app.buttons["profile-settings"].exists)
        XCTAssertFalse(app.buttons["profile-message"].exists, "no Message / Voice / Video on your own profile")
        XCTAssertTrue(app.buttons["profile-change-status"].label.hasPrefix("Status: "), "the status dot on the avatar")
        XCTAssertLessThan(app.buttons["profile-edit"].frame.minY, 150, "Edit and Settings are in the header")
        XCTAssertFalse(app.buttons["profile-sign-out"].exists, "Sign out is not at the bottom any more")
        app.buttons["profile-more"].tap()
        XCTAssertTrue(app.buttons["profile-sign-out"].waitForExistence(timeout: 5), "Sign out is last in the ⋯ menu")
        app.buttons["profile-sign-out"].tap()
        XCTAssertTrue(app.buttons["profile-sign-out-confirm"].firstMatch.waitForExistence(timeout: 5), "the same confirmation as Settings")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["profile-sign-out-confirm"].firstMatch.waitForNonExistence(timeout: 5))
    }

    func testMuteAndPinToggleFromTheProfileAndPinShowsInMessages() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        app.buttons["profile-more"].tap()
        if app.buttons["Unmute"].waitForExistence(timeout: 2) { // left over from an earlier run on this simulator
            app.buttons["Unmute"].tap()
            app.buttons["profile-more"].tap()
        }
        XCTAssertTrue(app.buttons["Mute"].waitForExistence(timeout: 3))
        app.buttons["Mute"].tap()
        XCTAssertTrue(app.buttons["mute-hour"].firstMatch.waitForExistence(timeout: 5), "the mute durations, in the confirmation sheet")
        app.buttons["mute-hour"].firstMatch.tap()
        app.buttons["profile-more"].tap()
        XCTAssertTrue(app.buttons["Unmute"].waitForExistence(timeout: 5), "muted")
        if app.buttons["Unpin"].exists { // left over from an earlier run
            app.buttons["Unpin"].tap()
            app.buttons["profile-more"].tap()
        }
        XCTAssertTrue(app.buttons["Pin"].waitForExistence(timeout: 3))
        app.buttons["Pin"].tap()
        app.buttons["profile-more"].tap()
        XCTAssertTrue(app.buttons["Unpin"].waitForExistence(timeout: 5), "pinned")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.9)).tap()   // closes the menu
        // Back to Messages: the chat is pinned.
        for _ in 0..<3 where !any(app, "pinned-dm:sam").exists {
            let back = app.buttons["back-button"].exists ? app.buttons["back-button"] : app.navigationBars.buttons.element(boundBy: 0)
            guard back.waitForExistence(timeout: 3) else { break }
            back.tap()
        }
        XCTAssertTrue(any(app, "pinned-dm:sam").waitForExistence(timeout: 5), "Pin shows in the Messages list")
    }

    func testTheMoreMenuHasShareVerifyStorageBlockAndDeleteWithBlockAskingFirst() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        app.buttons["profile-more"].tap()
        for id in ["profile-share", "profile-verify", "profile-storage", "profile-block", "profile-delete"] {
            XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5), id)
        }
        app.buttons["profile-block"].tap()
        XCTAssertTrue(app.buttons["profile-block-confirm"].firstMatch.waitForExistence(timeout: 5), "Block asks first")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["profile-block-confirm"].firstMatch.waitForNonExistence(timeout: 5))
        // Verify in person opens the QR screen.
        app.buttons["profile-more"].tap()
        app.buttons["profile-verify"].tap()
        XCTAssertTrue(app.staticTexts["Scan QR Code"].waitForExistence(timeout: 8), "the existing QR verification")
    }

    func testShareProfileInTheMenuPresentsTheShareSheet() {
        let app = app()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        app.buttons["profile-more"].tap()
        app.buttons["profile-share"].tap()
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 8) || app.otherElements["ActivityListView"].waitForExistence(timeout: 2), "the system share sheet")
    }

    func testAGroupMembersAvatarOpensTheirProfileSharedInThatGroup() {
        let app = app(["-lime-demo-screen", "group"])
        let avatar = any(app, "message-avatar-lee")
        XCTAssertTrue(avatar.waitForExistence(timeout: 10))
        avatar.tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["profile-name"].label, "Lee Wong")
    }

    func testGroupDetailsMemberRowsOpenProfilesAndTheSharedCardOpensAList() {
        let app = app(["-lime-demo-screen", "group-details"])
        let row = app.buttons["group-member-open-lee"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(any(app, "group-shared-media").exists && any(app, "group-shared-files").exists && any(app, "group-shared-links").exists, "the Shared card")
        any(app, "group-shared-links").tap()
        XCTAssertTrue(any(app, "shared-list").waitForExistence(timeout: 5), "opens the group's list")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        row.tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
    }

    func testTappingASharedMediaItemOpensTheViewer() {
        let app = app(["-lime-demo-screen", "attachments-media"])
        XCTAssertTrue(any(app, "chat-title").waitForExistence(timeout: 10))
        any(app, "chat-title").tap()
        XCTAssertTrue(any(app, "profile-screen").waitForExistence(timeout: 8))
        app.buttons["profile-tab-Shared"].tap()
        let cell = app.images.matching(NSPredicate(format: "label == 'Photo' OR label == 'Video'")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "a media cell")
        cell.tap()
        XCTAssertTrue(any(app, "attachment-viewer").waitForExistence(timeout: 8), "the viewer opens")
    }

    func testEditProfileOpensTheProfileEditorItself() {
        let app = app()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["profile-edit"].waitForExistence(timeout: 8))
        app.buttons["profile-edit"].tap()
        XCTAssertTrue(app.buttons["profile-about"].waitForExistence(timeout: 8), "the Edit Profile screen, not the Settings root")
        XCTAssertFalse(app.buttons["settings-profile"].exists)
    }
}

/// LIME-213: the profile's header: Subscribe before ⋯ on someone else's, the status dot on your avatar.
@MainActor
final class Profile213UITests: LimeUITestCase {
    func testSomeoneElsesHeaderHasMessageCallsAndMoreAndSubscribeIsAPillUnderTheSchool() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        app.buttons["conversation-row-dm:sam"].tap()
        app.descendants(matching: .any).matching(identifier: "chat-title").firstMatch.tap()
        let subscribe = app.buttons["profile-jam-subscribe"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 10))
        let more = app.buttons["profile-more"]
        for id in ["profile-message", "profile-call-button"] {
            let b = app.buttons[id]
            XCTAssertTrue(b.exists, id)
            XCTAssertLessThan(b.frame.midY, 120, "\(id) is in the header")
            XCTAssertLessThan(b.frame.maxX, more.frame.minX + 1, "\(id) is left of the ⋯")
        }
        XCTAssertGreaterThan(subscribe.frame.minY, 150, "Subscribe is a pill in the page, not the header")
        XCTAssertGreaterThan(subscribe.frame.minY, app.staticTexts["profile-school-line"].frame.maxY - 1, "under the school")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'profile-org-chip-'")).firstMatch.exists, "no org chips")
        subscribe.tap()
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Subscribed'"), evaluatedWith: subscribe)
        waitForExpectations(timeout: 8)
    }

    func testTheStatusDotOnYourAvatarOpensThePicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        app.launch()
        app.buttons["settings-button"].tap()
        let dot = app.buttons["profile-change-status"]
        XCTAssertTrue(dot.waitForExistence(timeout: 10))
        XCTAssertTrue(dot.label.hasPrefix("Status: "))
        dot.tap()
        XCTAssertTrue(app.descendants(matching: .any)["status-sheet"].waitForExistence(timeout: 5))
    }
}
