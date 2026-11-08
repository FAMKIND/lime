import XCTest

/// LIME-246c: a band's Members and Groups tabs (members only), invite link, roles, groups, Members audience, joining from a link (demo).
@MainActor
final class Band246UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openMyBand(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine-profile", "-lime-demo-band-people"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-band-demo-my-jam").tap()
        return app
    }

    func testAnOwnerSeesMembersByRoleChangesARoleAndHasAnInviteLinkThatTurnsOff() {
        let app = openMyBand()
        XCTAssertTrue(app.buttons["profile-tab-Members"].waitForExistence(timeout: 10), "the band's own people see Members")
        XCTAssertTrue(app.buttons["profile-tab-Groups"].exists)
        app.buttons["profile-tab-Members"].tap()
        XCTAssertTrue(app.staticTexts["org-members-private"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["org-members-private"].label, "Only members see who’s here.")
        for header in ["Owners", "Writers", "Members"] { XCTAssertTrue(app.staticTexts[header].exists, header) }
        XCTAssertEqual(any(app, "org-member-lee").label, "Lee Wong, member")
        XCTAssertEqual(any(app, "org-member-sam").label, "Sam Park, writer")
        // The row's menu: Lee becomes a writer.
        app.buttons["org-member-menu-lee"].tap()
        XCTAssertTrue(app.buttons["org-role-owner"].waitForExistence(timeout: 5), "the band's owner makes owners")
        app.buttons["org-role-writer"].tap()
        XCTAssertTrue(NSPredicate(format: "label == 'Lee Wong, writer'").evaluate(with: nil) || any(app, "org-member-lee").waitForExistence(timeout: 3))
        XCTAssertEqual(any(app, "org-member-lee").label, "Lee Wong, writer")
        // The invite link: shown, then off.
        app.buttons["org-invite-link"].tap()
        XCTAssertTrue(app.staticTexts["org-invite-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["org-invite-text"].label.hasPrefix("https://limemessenger.com/b/#"))
        app.buttons["org-invite-off"].tap()
        XCTAssertTrue(app.staticTexts["org-invite-is-off"].waitForExistence(timeout: 5), "turned off")
    }

    func testOwnersMakeAGroupInsideTheBandOpenOrInviteOnly() {
        let app = openMyBand()
        _ = app.buttons["profile-tab-Groups"].waitForExistence(timeout: 10)
        app.buttons["profile-tab-Groups"].tap()
        XCTAssertTrue(app.staticTexts["Science"].waitForExistence(timeout: 5) && app.staticTexts["Leads"].exists)
        app.buttons["org-new-group"].tap()
        let name = app.textFields["org-group-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["org-group-create"].isEnabled, "a name is required")
        name.tap(); name.typeText("Fourth grade")
        any(app, "org-group-pick-sam").tap()
        app.buttons["org-group-create"].tap()
        XCTAssertTrue(app.staticTexts["Fourth grade"].waitForExistence(timeout: 8), "the new group is listed")
    }

    func testSomeoneWhoIsNotAMemberSeesNeitherTabAndAMemberSeesBothCanJoinAnOpenGroupAndLeave() {
        // A non-member (the default demo): Sam's band shows only the public tabs.
        let outsider = XCUIApplication()
        outsider.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat"]
        outsider.launch()
        outsider.buttons["conversation-row-dm:sam"].tap()
        any(outsider, "chat-title").tap()
        XCTAssertTrue(outsider.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        outsider.buttons["profile-tab-Orgs"].tap()
        any(outsider, "profile-org-demo-sam-band-1").tap()
        XCTAssertTrue(outsider.buttons["profile-tab-Info"].waitForExistence(timeout: 8))
        XCTAssertFalse(outsider.buttons["profile-tab-Members"].exists || outsider.buttons["profile-tab-Groups"].exists, "members only")
        outsider.terminate()

        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-band-member"]
        app.launch()
        app.buttons["conversation-row-dm:sam"].tap()
        any(app, "chat-title").tap()
        XCTAssertTrue(app.buttons["profile-tab-Orgs"].waitForExistence(timeout: 10))
        app.buttons["profile-tab-Orgs"].tap()
        any(app, "profile-org-demo-sam-band-1").tap()
        XCTAssertTrue(app.buttons["profile-tab-Members"].waitForExistence(timeout: 8), "a member sees Members")
        app.buttons["profile-tab-Groups"].tap()
        let join = app.buttons["org-group-join-grp:demo-science"]
        XCTAssertTrue(join.waitForExistence(timeout: 5), "Join on an open group")
        XCTAssertFalse(app.buttons["org-group-join-grp:demo-leads"].exists, "an invitation-only group has no Join")
        XCTAssertFalse(app.buttons["org-new-group"].exists, "only owners make groups")
        join.tap()
        XCTAssertTrue(app.staticTexts["org-group-waiting-grp:demo-science"].waitForExistence(timeout: 5), "You'll be added when an owner's phone is next online")
        // A member leaves from Members.
        app.buttons["profile-tab-Members"].tap()
        XCTAssertFalse(app.buttons["org-add-members"].exists, "a member does not invite")
        app.buttons["org-leave"].tap()
        app.buttons["org-leave-confirm"].tap()
        XCTAssertTrue(app.buttons["profile-tab-Members"].waitForNonExistence(timeout: 8), "no longer a member")
    }

    func testPostingAsABandOffersMembersAsTheAudience() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        XCTAssertTrue(app.buttons["new-jam-post"].waitForExistence(timeout: 10))
        app.buttons["new-jam-post"].tap()
        app.buttons["jam-post-as"].tap()
        app.buttons["jam-post-as-jam-demo-band-demo-my-jam"].tap()
        let body = app.textViews["composer-field"]
        body.tap(); body.typeText("Staff meeting notes")
        app.buttons["jam-next"].tap()
        let chip = any(app, "jam-audience")
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "posting as a band shows Audience")
        chip.tap()
        XCTAssertTrue(any(app, "audience-members").waitForExistence(timeout: 5))
        any(app, "audience-members").tap()
        XCTAssertTrue(any(app, "jam-audience").label.contains("members"), any(app, "jam-audience").label)
        app.buttons["jam-post"].tap()
        // The card says Members.
        let label = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-card-members-'")).firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 10), "a members post has its label")
    }

    func testAPersonalPostHasNoMembersChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine"]
        app.launch()
        app.buttons["new-jam-post"].tap()
        let body = app.textViews["composer-field"]
        XCTAssertTrue(body.waitForExistence(timeout: 8))
        body.tap(); body.typeText("Just me")
        app.buttons["jam-next"].tap()
        XCTAssertTrue(app.buttons["jam-post"].waitForExistence(timeout: 8))
        XCTAssertFalse(any(app, "jam-audience").exists, "no audience choice for a post as yourself")
    }

    func testAnInviteFromALinkAsksToJoinThenWaits() {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-join-band"]
        app.launch()
        XCTAssertTrue(app.buttons["org-join"].waitForExistence(timeout: 10), "Join <band>?")
        app.buttons["org-join"].tap()
        XCTAssertTrue(app.staticTexts["org-join-waiting"].waitForExistence(timeout: 5), "the waiting state")
    }
}
