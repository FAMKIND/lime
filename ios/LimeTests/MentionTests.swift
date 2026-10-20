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
        XCTAssertNil(drawn.runs.first?.backgroundColor, "not me")
        let mine = Span(text: "@Shem", bold: false, italic: false, underline: false, strike: false, code: false, link: nil, mention: "u2")
        XCTAssertNotNil(MessageRender.attributed([mine], ink: .black, link: .green, mentions: context).runs.first?.backgroundColor, "mine is a little stronger")
        let unknown = MessageRender.attributed([span], ink: .black, link: .green, mentions: nil)
        XCTAssertEqual(String(unknown.characters), "@Jean Chung", "the written words when the person is not known")
    }
}
