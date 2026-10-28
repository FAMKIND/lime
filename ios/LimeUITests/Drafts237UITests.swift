import XCTest

/// LIME-237: Drafts in jam: group avatars, who is writing, swipe, long press and selection (demo).
@MainActor
final class Drafts237UITests: LimeUITestCase {
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func openDrafts() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-lime-skip-sign-in", "-lime-demo-chat", "-lime-demo-screen", "jam-mine", "-lime-drafts-sim"]
        app.launch()
        let drafts = app.buttons["jam-segment-Drafts"]
        XCTAssertTrue(drafts.waitForExistence(timeout: 10))
        drafts.tap()
        return app
    }

    private func row(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-draft-' AND NOT identifier BEGINSWITH 'jam-draft-live-' AND label BEGINSWITH %@", title)).firstMatch
    }

    func testAThreeAuthorDraftShowsItsAuthorsAndWhoIsWritingNow() {
        let app = openDrafts()
        let roots = row(app, "The roots of the lime tree")
        XCTAssertTrue(roots.waitForExistence(timeout: 8))
        XCTAssertTrue(roots.label.contains("Jean Park") && roots.label.contains("FAM Kind"), "all its authors: \(roots.label)")
        XCTAssertTrue(roots.label.contains("Jean is writing"), "who is in it now: \(roots.label)")
        let live = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-draft-live-'")).firstMatch
        XCTAssertTrue(live.exists)
        XCTAssertTrue(live.label.contains("Jean is writing"), live.label)
        XCTAssertFalse(row(app, "My private notes").label.contains("is writing"))
    }

    func testSwipeShowsDeleteAndCopyOnOneSideEditAndPinOnTheOther() {
        let app = openDrafts()
        let notes = row(app, "My private notes")
        XCTAssertTrue(notes.waitForExistence(timeout: 8))
        notes.swipeLeft()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swipe-draft-delete-'")).firstMatch.waitForExistence(timeout: 3), "Delete")
        let copy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swipe-draft-copy-'")).firstMatch
        XCTAssertTrue(copy.exists, "Copy")
        copy.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'jam-draft-' AND NOT identifier BEGINSWITH 'jam-draft-live-' AND label BEGINSWITH 'My private notes'")).count >= 2, "a copy appeared")
        let fractions = row(app, "Fractions plan")
        fractions.swipeRight()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swipe-draft-edit-'")).firstMatch.waitForExistence(timeout: 3), "Edit")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'swipe-draft-pin-'")).firstMatch.exists, "Pin")
    }

    func testLongPressSelectSelectAllAndDeleteWithOneConfirm() {
        let app = openDrafts()
        let notes = row(app, "My private notes")
        XCTAssertTrue(notes.waitForExistence(timeout: 8))
        notes.press(forDuration: 1.2)
        let select = app.buttons["Select"]
        XCTAssertTrue(select.waitForExistence(timeout: 3), "the long-press menu has Select")
        select.tap()
        XCTAssertEqual(any(app, "jam-drafts-count").label, "1 selected")
        app.buttons["jam-drafts-select-all"].tap()
        XCTAssertEqual(any(app, "jam-drafts-count").label, "3 selected")
        XCTAssertTrue(app.buttons["jam-drafts-copy"].exists && app.buttons["jam-drafts-pin"].exists)
        app.buttons["jam-drafts-bar-delete"].tap()
        let confirm = app.buttons.matching(identifier: "jam-drafts-delete-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "one confirmation for all")
        confirm.tap()
        XCTAssertTrue(any(app, "jam-drafts-empty").waitForExistence(timeout: 5), "they are gone")
    }
}
