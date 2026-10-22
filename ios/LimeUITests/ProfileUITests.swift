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
        XCTAssertEqual(app.staticTexts["profile-handle"].label, "@sam.park · Lincoln Elementary")
        XCTAssertTrue(app.staticTexts["profile-status"].exists, "the status they shared")
        XCTAssertTrue(app.buttons["profile-message"].exists && app.buttons["profile-voice"].exists && app.buttons["profile-video"].exists)
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
        XCTAssertFalse(app.buttons["profile-mute"].exists && app.buttons["profile-pin"].exists, "the bell and pin are for someone else's profile")
        XCTAssertEqual(app.buttons["profile-change-status"].label, "Status", "one short word, on one line")
        for _ in 0..<4 where !app.buttons["profile-sign-out"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["profile-sign-out"].waitForExistence(timeout: 5), "Sign out is at the bottom of the profile")
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
        if app.buttons["profile-mute"].label == "Unmute" { // left over from an earlier run on this simulator
            app.buttons["profile-mute"].tap()
            XCTAssertTrue(app.buttons["profile-mute"].waitForExistence(timeout: 3))
        }
        XCTAssertEqual(app.buttons["profile-mute"].label, "Mute")
        app.buttons["profile-mute"].tap()
        XCTAssertTrue(app.buttons["mute-hour"].firstMatch.waitForExistence(timeout: 5), "the mute durations, in the confirmation sheet")
        app.buttons["mute-hour"].firstMatch.tap()
        let muted = NSPredicate { _, _ in app.buttons["profile-mute"].label == "Unmute" }
        expectation(for: muted, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        if app.buttons["profile-pin"].label == "Unpin" { // left over from an earlier run
            app.buttons["profile-pin"].tap()
            XCTAssertTrue(app.buttons["profile-pin"].waitForExistence(timeout: 3))
        }
        XCTAssertEqual(app.buttons["profile-pin"].label, "Pin")
        app.buttons["profile-pin"].tap()
        let pinned = NSPredicate { _, _ in app.buttons["profile-pin"].label == "Unpin" }
        expectation(for: pinned, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
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
