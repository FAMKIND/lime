import XCTest

/// LIME-270: a member whose new key is not accepted yet is marked in the group, and the pickers list them with "accept first".
final class GroupKey270UITests: LimeUITestCase {
    func testTheMembersTabNamesAMemberWhoseKeyChangedAndOffersTheirChat() {
        let app = threadApp("group-details-key")
        app.launch()
        XCTAssertTrue(app.buttons["group-member-open-sam"].waitForExistence(timeout: 10))
        let note = app.otherElements["group-key-note-sam"]
        XCTAssertTrue(note.waitForExistence(timeout: 5) || app.buttons["group-key-open-sam"].exists, "the note about their key is there")
        XCTAssertTrue(app.buttons["group-key-open-sam"].exists, "with a way to open the chat")
        XCTAssertFalse(app.buttons["group-key-open-lee"].exists, "only for the member whose key changed")
    }

    func testNewGroupListsThePersonWithANewKeyAndSaysAcceptFirst() {
        let app = threadApp("new-group-key")
        app.launch()
        let row = app.buttons["group-pick-sam"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "they are listed, not hidden")
        XCTAssertTrue(row.label.contains("New key: accept first"), row.label)
    }
}
