import XCTest
@testable import Lime

@MainActor
final class SettingsTests: XCTestCase {
    private func profile(name: String = "Ada Lovelace", username: String? = "ada.l", school: String? = "Bay School",
                         emoji: String? = nil, about: String? = nil) -> Profile {
        Profile(displayName: name, username: username, school: school, aboutEmoji: emoji, aboutText: about, maskedEmail: "a•••@example.com")
    }

    // MARK: The editors

    func testTheNameIsRequiredAndAtMostFortyCharacters() {
        let model = FieldEditorModel(field: .name, profile: profile())
        XCTAssertFalse(model.canSave, "nothing has changed yet")
        model.text = "   "
        XCTAssertFalse(model.canSave)
        XCTAssertEqual(model.validationMessage, "Your name can't be empty.")
        model.text = String(repeating: "n", count: 41)
        XCTAssertFalse(model.canSave)
        model.text = String(repeating: "n", count: 40)
        XCTAssertTrue(model.canSave)
        model.text = "  Ada L  "
        XCTAssertEqual(model.draft().displayName, "Ada L", "saved trimmed")
        XCTAssertEqual(model.draft().username, "ada.l", "the other fields travel with it")
    }

    func testTheCheckIsDimmedUntilThereIsAValidChange() {
        let model = FieldEditorModel(field: .school, profile: profile())
        XCTAssertFalse(model.canSave)
        model.text = "Another School"
        XCTAssertTrue(model.canSave)
        model.text = "Bay School"
        XCTAssertFalse(model.canSave, "back to what it was: nothing to save")
        model.text = ""
        XCTAssertTrue(model.canSave, "clearing a school is a change")
        XCTAssertNil(model.draft().school)
        model.text = String(repeating: "s", count: 121)
        XCTAssertFalse(model.canSave)
    }

    func testTheUsernameFollowsTheWebRulesAndStripsAnAt() {
        let model = FieldEditorModel(field: .username, profile: profile())
        model.text = "ab"
        XCTAssertEqual(model.validationMessage, "Use 3 to 20 characters.")
        XCTAssertFalse(model.canSave)
        model.text = "has space"
        XCTAssertEqual(model.validationMessage, "Use only letters, numbers, dots and underscores.")
        model.text = "Admin"
        XCTAssertEqual(model.validationMessage, "That username is reserved. Try another.")
        model.text = "@new.name"
        XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.draft().username, "new.name")
        model.text = ""
        XCTAssertTrue(model.canSave, "a username is optional: clearing it is allowed")
        XCTAssertNil(model.draft().username)
    }

    func testAboutCountsDownFromOneHundredAndFortyWithTheEmojiAsOne() {
        let model = FieldEditorModel(field: .about, profile: profile())
        XCTAssertEqual(model.title, "About (140)")
        XCTAssertFalse(model.canSave)
        model.text = "Happy to help"
        XCTAssertEqual(model.title, "About (127)")
        XCTAssertTrue(model.canSave)
        model.pickEmoji("👋")
        XCTAssertEqual(model.title, "About (126)", "the emoji uses one")
        // A family emoji is one character, however many scalars it has.
        model.pickEmoji("👨‍👩‍👧")
        XCTAssertEqual(model.emoji, "👨‍👩‍👧")
        XCTAssertEqual(model.used, 14)

        model.text = String(repeating: "a", count: 139)
        XCTAssertEqual(model.remaining, 0)
        XCTAssertTrue(model.canSave, "emoji + 139 is exactly 140")
        model.text = String(repeating: "a", count: 140)
        XCTAssertEqual(model.remaining, -1)
        XCTAssertFalse(model.canSave, "emoji + 140 is one too many")
        XCTAssertEqual(model.validationMessage, "About is at most 140 characters.")
        model.emoji = ""
        XCTAssertTrue(model.canSave, "140 words and no emoji fits")
    }

    func testAnEmojiPickedFromTheKeyboardReplacesTheLeadingOne() {
        let model = FieldEditorModel(field: .about, profile: profile(emoji: "🍎", about: "In class"))
        XCTAssertEqual(model.emoji, "🍎")
        model.pickEmoji("☕🔒")
        XCTAssertEqual(model.emoji, "🔒", "only the last emoji typed counts")
        model.pickEmoji("")
        XCTAssertEqual(model.emoji, "🔒")
    }

    func testAPresetFillsTheEmojiAndTheText() {
        let model = FieldEditorModel(field: .about, profile: profile())
        let preset = AboutPreset.all.first { $0.text == "Planning lessons" }!
        model.applyPreset(preset)
        XCTAssertEqual(model.emoji, "📚")
        XCTAssertEqual(model.text, "Planning lessons")
        XCTAssertTrue(model.canSave)
        XCTAssertEqual(model.draft().aboutEmoji, "📚")
        XCTAssertEqual(model.draft().aboutText, "Planning lessons")
        XCTAssertEqual(AboutPreset.all.count, 7)
        XCTAssertEqual(AboutPreset.all.map(\.text), ["Happy to help", "Planning lessons", "In class", "Coffee lover", "Grading", "Taking a break", "Encrypted"])
    }

    func testClearingAboutRemovesBothParts() {
        let model = FieldEditorModel(field: .about, profile: profile(emoji: "🍎", about: "In class"))
        model.clear()
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(model.emoji, "")
        XCTAssertTrue(model.canSave)
        XCTAssertNil(model.draft().aboutEmoji)
        XCTAssertNil(model.draft().aboutText)
    }

    func testTheAboutLineShowsAsOneString() {
        XCTAssertEqual(profile(emoji: "👋", about: "Happy to help").about, "👋 Happy to help")
        XCTAssertEqual(profile(emoji: nil, about: "Just words").about, "Just words")
        XCTAssertEqual(profile(emoji: "🔒", about: nil).about, "🔒")
        XCTAssertNil(profile().about)
        let person = FoundUser(userId: "u", displayName: "G", username: nil, school: nil, aboutEmoji: "⚓", aboutText: "Debugging", isSelf: false)
        XCTAssertEqual(NewMessageSheet.about(person), "⚓ Debugging", "it shows in New message results")
    }

    // MARK: Changing the password

    func testChangingThePasswordNeedsTheCurrentOneAMatchingNewOneAndTheCode() async {
        var sentCurrent: String?
        var finished: (String, String)?
        let model = ChangePasswordModel(start: { sentCurrent = $0 }, finish: { finished = ($0, $1) })
        XCTAssertFalse(model.canSend)
        model.current = "old password 1"
        model.newPassword = "short"
        model.confirmation = "short"
        XCTAssertFalse(model.canSend, "at least 10 characters")
        model.newPassword = "a brand new password"
        model.confirmation = "something else"
        XCTAssertFalse(model.canSend)
        XCTAssertEqual(model.hint, "The two new passwords don't match.")
        model.confirmation = "a brand new password"
        XCTAssertTrue(model.canSend)
        model.newPassword = "old password 1"; model.confirmation = "old password 1"
        XCTAssertFalse(model.canSend, "it must differ from the current one")
        model.newPassword = "a brand new password"; model.confirmation = "a brand new password"

        await model.sendCode()
        XCTAssertEqual(sentCurrent, "old password 1")
        XCTAssertEqual(model.step, .code)
        model.code = "12345"
        XCTAssertFalse(model.canVerify)
        model.code = "123456"
        XCTAssertTrue(model.canVerify)
        await model.verify()
        XCTAssertEqual(finished?.0, "123456")
        XCTAssertEqual(finished?.1, "a brand new password")
        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(model.newPassword, "", "nothing is kept once it is done")
    }

    func testAWrongCurrentPasswordAndAWrongCodeSayWhatIsWrong() async {
        let wrongCurrent = ChangePasswordModel(start: { _ in throw AuthError.invalidCredentials }, finish: { _, _ in })
        wrongCurrent.current = "nope"; wrongCurrent.newPassword = "a brand new password"; wrongCurrent.confirmation = "a brand new password"
        await wrongCurrent.sendCode()
        XCTAssertEqual(wrongCurrent.errorMessage, "That isn't your current password.")
        XCTAssertEqual(wrongCurrent.step, .passwords)

        let wrongCode = ChangePasswordModel(start: { _ in }, finish: { _, _ in throw AuthError.badCode(message: "That code isn't right. 4 tries left.") })
        wrongCode.current = "x"; wrongCode.newPassword = "a brand new password"; wrongCode.confirmation = "a brand new password"
        await wrongCode.sendCode()
        wrongCode.code = "000000"
        await wrongCode.verify()
        XCTAssertEqual(wrongCode.errorMessage, "That code isn't right. 4 tries left.")
        XCTAssertEqual(wrongCode.step, .code)
        wrongCode.code = "000001"
        XCTAssertNil(wrongCode.errorMessage, "editing the code clears its error")

        let ended = ChangePasswordModel(start: { _ in throw AuthError.notVerified }, finish: { _, _ in })
        ended.current = "x"; ended.newPassword = "a brand new password"; ended.confirmation = "a brand new password"
        await ended.sendCode()
        XCTAssertEqual(ended.errorMessage, "Your session has ended. Please sign in again.")
    }

    // MARK: Appearance, donate, acknowledgements

    func testTheAppearanceIsKeptAndUnknownMeansSystem() {
        let defaults = UserDefaults(suiteName: "lime-appearance-\(UUID().uuidString)")!
        XCTAssertEqual(AppearanceSetting.stored(in: defaults), .system)
        AppearanceSetting.dark.save(in: defaults)
        XCTAssertEqual(AppearanceSetting.stored(in: defaults), .dark, "it survives: a new read sees it")
        defaults.set("sepia", forKey: AppearanceSetting.storageKey)
        XCTAssertEqual(AppearanceSetting.stored(in: defaults), .system)
        XCTAssertNil(AppearanceSetting.system.colorScheme)
        XCTAssertEqual(AppearanceSetting.light.colorScheme, .light)
        XCTAssertEqual(AppearanceSetting.dark.colorScheme, .dark)
        XCTAssertEqual(AppearanceSetting.allCases.map(\.title), ["System", "Light", "Dark"])
    }

    func testTheDonateRowIsHiddenUnlessASecureLinkIsConfigured() {
        XCTAssertNil(DonateLink.url(from: nil))
        XCTAssertNil(DonateLink.url(from: ""))
        XCTAssertNil(DonateLink.url(from: "   "))
        XCTAssertNil(DonateLink.url(from: "http://example.com/donate"), "only https")
        XCTAssertNil(DonateLink.url(from: "not a link"))
        XCTAssertEqual(DonateLink.url(from: "https://example.com/donate")?.absoluteString, "https://example.com/donate")
        XCTAssertNil(DonateLink.current, "none is configured in this build")
    }

    func testTheAcknowledgementsShipWithTheSQLCipherNotice() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"), "the licences are in the app")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("Zetetic LLC"), "the SQLCipher notice that binary distribution must reproduce")
        XCTAssertTrue(text.contains("Redistributions in binary form must reproduce the above copyright"))
        XCTAssertTrue(text.contains("vodozemac"))
        XCTAssertTrue(text.contains("uniffi"))
        XCTAssertGreaterThan(AcknowledgementsScreen.loadBlocks().count, 10)
    }
}
