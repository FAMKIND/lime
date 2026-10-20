import XCTest
@testable import Lime

/// LIME-181: mentions in the composer's text model, the suggestion matching and the bubble.
final class MentionTests: XCTestCase {
    private let people = [Person(id: "u1", name: "Jean Chung", tone: 0), Person(id: "u2", name: "Shem Rajoon", tone: 1), Person(id: "u3", name: "Éloïse Martin", tone: 2, label: "Grade 4")]

    func testAMentionRoundTripsThroughTheComposerText() {
        let text = ComposerDocument.attributed(fromMarkdown: "hi [@Jean Chung](mention:u1), see this")
        XCTAssertEqual(text.string, "hi @Jean Chung, see this")
        XCTAssertEqual(ComposerDocument.mentionRange(in: text, at: 5), NSRange(location: 3, length: 11))
        XCTAssertNil(ComposerDocument.mentionRange(in: text, at: 2))
        XCTAssertEqual(ComposerDocument.markdown(from: text), "hi [@Jean Chung](mention:u1), see this")
    }

    func testAnEditThatTouchesPartOfAMentionTakesAllOfIt() {
        let text = ComposerDocument.attributed(fromMarkdown: "a [@Jean Chung](mention:u1) b")
        XCTAssertEqual(ComposerDocument.expandedToMentions(NSRange(location: 10, length: 1), in: text), NSRange(location: 2, length: 11), "the last letter")
        XCTAssertEqual(ComposerDocument.expandedToMentions(NSRange(location: 0, length: 4), in: text), NSRange(location: 0, length: 13), "a selection that starts before it")
        XCTAssertEqual(ComposerDocument.expandedToMentions(NSRange(location: 0, length: 1), in: text), NSRange(location: 0, length: 1), "words beside it are untouched")
    }

    func testTheAtSignOpensTheListOnlyAtTheStartOfAWord() {
        let text = NSAttributedString(string: "mail me@j and @je")
        XCTAssertNil(ComposerDocument.mentionTrigger(in: text, caret: 9), "an @ inside a word is not a mention")
        let found = ComposerDocument.mentionTrigger(in: text, caret: 17)
        XCTAssertEqual(found?.query, "je")
        XCTAssertEqual(found?.range, NSRange(location: 14, length: 3))
        XCTAssertEqual(ComposerDocument.mentionTrigger(in: NSAttributedString(string: "@"), caret: 1)?.query, "")
        XCTAssertNil(ComposerDocument.mentionTrigger(in: NSAttributedString(string: "@jean\nnext"), caret: 10), "not across a line")
    }

    func testPickingWritesTheMentionAndASpace() {
        let text = NSMutableAttributedString(string: "hello @je")
        let caret = ComposerDocument.insertMention("Jean Chung", id: "u1", replacing: NSRange(location: 6, length: 3), in: text)
        XCTAssertEqual(text.string, "hello @Jean Chung ")
        XCTAssertEqual(caret, text.length)
        XCTAssertEqual(ComposerDocument.markdown(from: text), "hello [@Jean Chung](mention:u1) ")
    }

    func testSuggestionsMatchByNameWordAndLabelAndAdminsGetEveryone() {
        func ids(_ query: String, everyone: Bool = false) -> [String] { MentionCandidate.matches(for: query, people: people, everyone: everyone).map(\.id) }
        XCTAssertEqual(ids(""), ["u1", "u2", "u3"])
        XCTAssertEqual(ids("je"), ["u1"])
        XCTAssertEqual(ids("chu"), ["u1"], "a later word of the name")
        XCTAssertEqual(ids("eloi"), ["u3"], "accents are ignored")
        XCTAssertEqual(ids("grade"), ["u3"], "my private label")
        XCTAssertEqual(ids("zzz"), [])
        XCTAssertEqual(ids("", everyone: true).first, "everyone")
        XCTAssertEqual(ids("eve", everyone: true), ["everyone"])
        XCTAssertFalse(ids("je").contains("everyone"), "never for non-admins")
    }

    func testABubbleDrawsTheNameThisPhoneKnowsAndLinksToTheProfile() {
        let context = MentionContext(meID: "u2", name: { $0 == "u1" ? "Jean C." : nil }, open: { _ in })
        let span = Span(text: "@Jean Chung", bold: false, italic: false, underline: false, strike: false, code: false, link: nil, mention: "u1")
        let drawn = MessageRender.attributed([span], ink: .black, link: .green, mentions: context)
        XCTAssertEqual(String(drawn.characters), "@Jean C.", "the current name, not the written one")
        XCTAssertEqual(drawn.runs.first?.link.flatMap(MentionContext.userID(from:)), "u1")
        XCTAssertNil(drawn.runs.first?.underlineStyle, "not underlined: it is not a web link")
        XCTAssertNil(drawn.runs.first?.backgroundColor, "no highlight")
        let mine = Span(text: "@Shem", bold: false, italic: false, underline: false, strike: false, code: false, link: nil, mention: "u2")
        XCTAssertNil(MessageRender.attributed([mine], ink: .black, link: .green, mentions: context).runs.first?.backgroundColor, "not even a mention of me (LIME-181c)")
        let unknown = MessageRender.attributed([span], ink: .black, link: .green, mentions: nil)
        XCTAssertEqual(String(unknown.characters), "@Jean Chung", "the written words when the person is not known")
    }
}

/// LIME-181b: how a mention reads (full name or username) and who gets the highlight.
final class MentionStyleTests: XCTestCase {
    private let context = MentionContext(meID: "me", name: { ["u1": "Jean Chung", "me": "Shem"][$0] },
                                         username: { ["u1": "jean.c"][$0] }, open: { _ in })
    private func mention(_ id: String) -> Span {
        Span(text: "@written", bold: false, italic: false, underline: false, strike: false, code: false, link: nil, mention: id)
    }
    private func text(_ id: String, _ style: MentionStyle) -> AttributedString {
        MessageRender.attributed([mention(id)], ink: .black, link: .green, mentions: context, mentionStyle: style)
    }

    func testFullNameModeShowsTheNameAndUsernameModeShowsTheHandleWhenKnown() {
        XCTAssertEqual(String(text("u1", .fullName).characters), "@Jean Chung")
        XCTAssertEqual(String(text("u1", .username).characters), "@jean.c")
    }

    func testUsernameModeFallsBackToTheNameWhenThereIsNoHandle() {
        XCTAssertEqual(String(text("me", .username).characters), "@Shem")
        XCTAssertEqual(String(text("zz", .username).characters), "@written", "and to the written words when the person is not known at all")
    }

    func testNoMentionHasAHighlightInAnyBubble() {
        for id in ["me", "u1", MentionContext.everyone] {
            XCTAssertNil(text(id, .fullName).runs.first?.backgroundColor, id)
            XCTAssertNil(text(id, .username).runs.first?.backgroundColor, id)
        }
    }

    func testSuggestionsMatchAUsernameToo() {
        let people = [Person(id: "u1", name: "Jean Chung", tone: 0)]
        let found = MentionCandidate.matches(for: "jean.c", people: people, everyone: false, usernames: ["u1": "jean.c"])
        XCTAssertEqual(found.first?.username, "jean.c")
        XCTAssertEqual(MentionCandidate.matches(for: "xyz", people: people, everyone: false, usernames: ["u1": "jean.c"]).count, 0)
    }
}

/// LIME-181b privacy: a username is searched on this phone only, and only where the person's profile already shows it.
final class MentionPrivacyTests: XCTestCase {
    func testSomeoneWhoHidesFromSearchIsNotFoundByUsernameAndShowsByNameInUsernameMode() {
        // What profile-get returns for a person who hid themselves: the name only.
        let hidden = PublicProfile(userId: "h", displayName: "Hana Hidden", username: nil, school: nil, aboutEmoji: nil, aboutText: nil)
        let open = PublicProfile(userId: "o", displayName: "Omar Open", username: "omar.o", school: nil, aboutEmoji: nil, aboutText: nil)
        let usernames = MentionCandidate.usernames(from: ["h": hidden, "o": open])
        XCTAssertNil(usernames["h"], "no username is known for them")
        let people = [Person(id: "h", name: "Hana Hidden", tone: 0), Person(id: "o", name: "Omar Open", tone: 1)]
        XCTAssertEqual(MentionCandidate.matches(for: "omar.o", people: people, everyone: false, usernames: usernames).map(\.id), ["o"])
        // Even the handle they might use elsewhere does not find them: only the name does.
        XCTAssertEqual(MentionCandidate.matches(for: "hana.h", people: people, everyone: false, usernames: usernames).map(\.id), [])
        XCTAssertEqual(MentionCandidate.matches(for: "hana", people: people, everyone: false, usernames: usernames).map(\.id), ["h"])
        let context = MentionContext(meID: "me", name: { $0 == "h" ? "Hana Hidden" : nil }, username: { usernames[$0] }, open: { _ in })
        XCTAssertEqual(context.shown("h", style: .username), "@Hana Hidden", "Username mode shows their name")
    }

    func testAnEmptyUsernameCountsAsNone() {
        let blank = PublicProfile(userId: "b", displayName: "Bo", username: "", school: nil, aboutEmoji: nil, aboutText: nil)
        XCTAssertTrue(MentionCandidate.usernames(from: ["b": blank]).isEmpty)
    }
}
