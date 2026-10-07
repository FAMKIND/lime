import XCTest
@testable import Lime

/// The composer's text model: Markdown to attributed text and back for every feature, and the editing
/// operations the toolbar uses. No views are involved.
final class ComposerDocumentTests: XCTestCase {
    private func roundTrip(_ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        let attributed = ComposerDocument.attributed(fromMarkdown: markdown)
        XCTAssertEqual(ComposerDocument.markdown(from: attributed), normaliseMessageMarkdown(text: markdown), "\(markdown.debugDescription)", file: file, line: line)
    }

    // MARK: Both ways, for every feature

    func testEveryInlineStyleSurvivesTheRoundTrip() {
        roundTrip("plain words")
        roundTrip("a **bold** word")
        roundTrip("an *italic* word")
        roundTrip("an __underlined__ word")
        roundTrip("a ~~struck~~ word")
        roundTrip("some `code` here")
        roundTrip("a [link](https://limechat.org/x?y=1) here")
        roundTrip("mailto [me](mailto:a@b.co) and [web](http://a.b)")
        roundTrip("**bold *and italic* together** ~~__all__~~")
        roundTrip("[**bold link**](https://a.b)")
    }

    func testBlocksSurviveTheRoundTrip() {
        roundTrip("- one\n- two\n- three")
        roundTrip("1. first\n2. second\n3. third")
        roundTrip("- parent\n  - child\n- next")
        roundTrip("1. a\n  1. b\n2. c")
        roundTrip("```\nlet a = 1\nlet b = **raw**\n```")
        roundTrip("before\n\n```\ncode\n```\n\nafter")
        roundTrip("intro **bold**\n\n- item with `code` and *italics*\n- [link](https://a.b)\n\n```\nblock\n```")
        roundTrip("line one\nline two\n\nnew paragraph")
    }

    func testTextThatLooksLikeMarkupIsKeptAsTyped() {
        for typed in ["2 * 3 * 4", "snake_case_name", "a ~ b", "[not a link](nowhere)", "1. not a list", "- not a list", "use ``` fences", "# not a heading", "a\\b"] {
            let text = NSMutableAttributedString(string: typed)
            ComposerDocument.restyle(text)
            let markdown = ComposerDocument.markdown(from: text)
            XCTAssertEqual(messagePlainText(text: markdown), typed, "what was typed is what is read back: \(typed)")
            XCTAssertTrue(parseMessageMarkdown(text: markdown).allSatisfy { if case .paragraph = $0 { true } else { false } }, typed)
        }
        XCTAssertEqual(ComposerDocument.markdown(from: NSAttributedString(string: "2 * 3")), "2 \\* 3")
    }

    func testSpacesAreKeptOutsideTheMarkers() {
        let text = ComposerDocument.attributed(fromMarkdown: "a **b** c")
        let range = (text.string as NSString).range(of: "b ")
        ComposerDocument.toggle(.bold, in: text, range: range)
        XCTAssertEqual(ComposerDocument.markdown(from: text), "a **b** c", "the trailing space of the selection stays outside the markers")
    }

    // MARK: Toggling styles

    func testBoldTogglesOnAndOffForASelection() {
        let text = NSMutableAttributedString(string: "make this bold now")
        let word = (text.string as NSString).range(of: "this")
        XCTAssertTrue(ComposerDocument.toggle(.bold, in: text, range: word))
        XCTAssertEqual(ComposerDocument.markdown(from: text), "make **this** bold now")
        XCTAssertTrue(ComposerDocument.state(in: text, selection: word, typing: [:]).bold)
        XCTAssertFalse(ComposerDocument.state(in: text, selection: NSRange(location: 0, length: 6), typing: [:]).bold, "pressed only when every character has it")
        XCTAssertFalse(ComposerDocument.toggle(.bold, in: text, range: word))
        XCTAssertEqual(ComposerDocument.markdown(from: text), "make this bold now")
    }

    func testAMixedSelectionTurnsTheStyleOnForAll() {
        let text = ComposerDocument.attributed(fromMarkdown: "one **two** three")
        let all = NSRange(location: 0, length: text.length)
        XCTAssertTrue(ComposerDocument.toggle(.bold, in: text, range: all), "partly bold: bold for all")
        XCTAssertEqual(ComposerDocument.markdown(from: text), "**one two three**")
        XCTAssertFalse(ComposerDocument.toggle(.bold, in: text, range: all), "now all bold: off")
    }

    func testEveryStyleAppliesAndStacks() {
        let text = NSMutableAttributedString(string: "styled")
        let all = NSRange(location: 0, length: 6)
        for format in InlineFormat.allCases where format != .code { ComposerDocument.toggle(format, in: text, range: all) }
        XCTAssertEqual(ComposerDocument.markdown(from: text), "~~__***styled***__~~")
        let state = ComposerDocument.state(in: text, selection: all, typing: [:])
        XCTAssertTrue(state.bold && state.italic && state.underline && state.strike)
        XCTAssertFalse(state.code || state.link || state.bullets || state.numbers)
    }

    func testCaretStateComesFromTheTypingAttributes() {
        let text = NSAttributedString(string: "abc")
        let typing: [NSAttributedString.Key: Any] = [.limeItalic: true]
        let state = ComposerDocument.state(in: text, selection: NSRange(location: 3, length: 0), typing: typing)
        XCTAssertTrue(state.italic)
        XCTAssertFalse(state.bold)
    }

    func testALinkIsAddedAndCleared() {
        let text = NSMutableAttributedString(string: "see the plan today")
        let range = (text.string as NSString).range(of: "the plan")
        ComposerDocument.setLink(URL(string: "https://limechat.org/plan"), in: text, range: range)
        XCTAssertEqual(ComposerDocument.markdown(from: text), "see [the plan](https://limechat.org/plan) today")
        XCTAssertTrue(ComposerDocument.state(in: text, selection: range, typing: [:]).link)
        ComposerDocument.setLink(nil, in: text, range: range)
        XCTAssertEqual(ComposerDocument.markdown(from: text), "see the plan today")
    }

    // MARK: Lists and code

    func testABulletedListFromTwoLinesAndBackToPlain() {
        let text = NSMutableAttributedString(string: "apples\nbananas")
        var selection = NSRange(location: 0, length: text.length)
        selection = ComposerDocument.toggleList(.bullet, in: text, selection: selection)
        XCTAssertEqual(text.string, "• apples\n• bananas")
        XCTAssertEqual(ComposerDocument.markdown(from: text), "- apples\n- bananas")
        XCTAssertTrue(ComposerDocument.state(in: text, selection: selection, typing: [:]).bullets)
        selection = ComposerDocument.toggleList(.bullet, in: text, selection: selection)
        XCTAssertEqual(text.string, "apples\nbananas")
        XCTAssertEqual(ComposerDocument.markdown(from: text), "apples\nbananas")
    }

    func testANumberedListCountsAndSwitchingKindsReplacesTheMarker() {
        let text = NSMutableAttributedString(string: "one\ntwo\nthree")
        let all = NSRange(location: 0, length: text.length)
        _ = ComposerDocument.toggleList(.number, in: text, selection: all)
        XCTAssertEqual(text.string, "1. one\n2. two\n3. three")
        XCTAssertEqual(ComposerDocument.markdown(from: text), "1. one\n2. two\n3. three")
        _ = ComposerDocument.toggleList(.bullet, in: text, selection: NSRange(location: 0, length: text.length))
        XCTAssertEqual(text.string, "• one\n• two\n• three", "a numbered list becomes a bulleted one")
    }

    func testReturnInAListContinuesItAndOnAnEmptyItemEndsIt() {
        let text = NSMutableAttributedString(string: "first")
        var selection = ComposerDocument.toggleList(.number, in: text, selection: NSRange(location: 5, length: 0))
        selection = NSRange(location: text.length, length: 0)
        XCTAssertTrue(ComposerDocument.handleReturn(in: text, selection: &selection))
        XCTAssertEqual(text.string, "1. first\n2. ", "the next item starts with the next number")
        XCTAssertEqual(selection.location, text.length)
        text.replaceCharacters(in: selection, with: NSAttributedString(string: "second", attributes: [.limeBlock: "number", .limeLevel: 0]))
        selection = NSRange(location: text.length, length: 0)
        XCTAssertEqual(ComposerDocument.markdown(from: text), "1. first\n2. second")
        XCTAssertTrue(ComposerDocument.handleReturn(in: text, selection: &selection))
        XCTAssertEqual(text.string, "1. first\n2. second\n3. ")
        // Return on the empty third item ends the list.
        XCTAssertTrue(ComposerDocument.handleReturn(in: text, selection: &selection))
        XCTAssertEqual(text.string, "1. first\n2. second\n")
        XCTAssertEqual(ComposerDocument.markdown(from: text), "1. first\n2. second")
        // Return outside a list is an ordinary new line (not handled here).
        let plain = NSMutableAttributedString(string: "plain")
        var caret = NSRange(location: 5, length: 0)
        XCTAssertFalse(ComposerDocument.handleReturn(in: plain, selection: &caret))
    }

    func testRemovingAnItemRenumbers() {
        let text = ComposerDocument.attributed(fromMarkdown: "1. a\n2. b\n3. c")
        let second = (text.string as NSString).paragraphRange(for: NSRange(location: 6, length: 0))
        text.deleteCharacters(in: second)
        ComposerDocument.renumber(text)
        XCTAssertEqual(text.string, "1. a\n2. c")
    }

    func testACodeBlockAcrossLinesAndInlineCodeForAWord() {
        let text = NSMutableAttributedString(string: "let a = 1\nlet b = 2")
        _ = ComposerDocument.toggleCode(in: text, selection: NSRange(location: 0, length: text.length))
        XCTAssertEqual(ComposerDocument.markdown(from: text), "```\nlet a = 1\nlet b = 2\n```")
        XCTAssertTrue(ComposerDocument.blockKind(in: text, at: 0) == .code)
        // The same selection again turns it back to plain lines.
        _ = ComposerDocument.toggleCode(in: text, selection: NSRange(location: 0, length: text.length))
        XCTAssertEqual(ComposerDocument.markdown(from: text), "let a = 1\nlet b = 2")

        let inline = NSMutableAttributedString(string: "call run() now")
        let word = (inline.string as NSString).range(of: "run()")
        _ = ComposerDocument.toggleCode(in: inline, selection: word)
        XCTAssertEqual(ComposerDocument.markdown(from: inline), "call `run()` now")
        XCTAssertTrue(ComposerDocument.state(in: inline, selection: word, typing: [:]).code)
    }

    func testACodeBlockInTheMiddleOfAMessage() {
        let text = ComposerDocument.attributed(fromMarkdown: "Here is the fix:\n\n```\nx = 1\n```\n\nThanks")
        XCTAssertEqual(ComposerDocument.markdown(from: text), "Here is the fix:\n\n```\nx = 1\n```\n\nThanks")
        let blocks = ComposerDocument.blocks(from: text)
        XCTAssertEqual(blocks.count, 3)
        if case .code(let code) = blocks[1] { XCTAssertEqual(code, "x = 1") } else { XCTFail("the middle block is code") }
    }

    func testBlankLinesSeparateParagraphsAndNewlinesAreLineBreaks() {
        let text = NSAttributedString(string: "line one\nline two\n\nsecond paragraph")
        XCTAssertEqual(ComposerDocument.markdown(from: text), "line one\nline two\n\nsecond paragraph")
        XCTAssertEqual(ComposerDocument.markdown(from: NSAttributedString(string: "  \n")), "")
    }

    func testThePlainTextOfAComposedMessageHasNoMarkup() {
        let text = ComposerDocument.attributed(fromMarkdown: "**Hi** [team](https://a.b)\n\n- one\n- two")
        XCTAssertEqual(messagePlainText(text: ComposerDocument.markdown(from: text)), "Hi team\n• one\n• two")
    }
}
