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

/// LIME-137: lists that start as you type, three levels, Indent / Outdent, and Return / Backspace in nested lists.
/// `Typist` plays the keystrokes the text view's delegate would see, calling the same functions.
final class ComposerNestedListTests: XCTestCase {
    private final class Typist {
        let text = NSMutableAttributedString()
        var selection = NSRange(location: 0, length: 0)
        var started: ComposerDocument.AutoStart?

        func type(_ string: String) {
            for character in string {
                insert(String(character))
            }
        }

        private func insert(_ character: String) {
            let pending = started
            started = nil
            if character == " ", let auto = ComposerDocument.autoStart(in: text, selection: &selection) {
                started = auto
                return
            }
            if character == "\n", ComposerDocument.handleReturn(in: text, selection: &selection) { return }
            _ = pending
            let attributes = ComposerDocument.typingAttributes(in: text, caret: selection.location)
            text.replaceCharacters(in: selection, with: NSAttributedString(string: character, attributes: attributes))
            selection = NSRange(location: selection.location + character.utf16.count, length: 0)
            ComposerDocument.renumber(text)
            ComposerDocument.restyle(text)
        }

        /// Backspace the way the delegate handles it at the start of an item's text.
        func backspace() {
            if let auto = started, auto.caret == selection.location {
                started = nil
                if ComposerDocument.undoAutoStart(auto, in: text, selection: &selection) { return }
            }
            started = nil
            let paragraph = ComposerDocument.paragraphs(in: text, covering: selection)[0]
            if let marker = ComposerDocument.markerRange(in: text, paragraph: paragraph), selection.location == NSMaxRange(marker) {
                if ComposerDocument.listLevel(in: text, at: paragraph.location) > 0 {
                    selection = ComposerDocument.shiftLevel(in: text, selection: selection, indent: false)
                } else {
                    text.deleteCharacters(in: marker)
                    let rest = NSRange(location: paragraph.location, length: max(paragraph.length - marker.length, 0))
                    text.removeAttribute(.limeBlock, range: rest)
                    text.removeAttribute(.limeLevel, range: rest)
                    selection = NSRange(location: paragraph.location, length: 0)
                }
                ComposerDocument.renumber(text)
                ComposerDocument.restyle(text)
                return
            }
            guard selection.location > 0 else { return }
            text.deleteCharacters(in: NSRange(location: selection.location - 1, length: 1))
            selection = NSRange(location: selection.location - 1, length: 0)
        }

        func indent(_ indent: Bool = true) {
            selection = ComposerDocument.shiftLevel(in: text, selection: selection, indent: indent)
        }

        var string: String { text.string }
        var markdown: String { ComposerDocument.markdown(from: text) }
    }

    func testTypingAMarkerAndASpaceStartsAList() {
        for (typed, shown, markdown) in [("- ", "• x", "- x"), ("* ", "• x", "- x"), ("• ", "• x", "- x"), ("1. ", "1. x", "1. x"), ("3. ", "3. x", "3. x"), ("  - ", "◦ x", "  - x")] {
            let t = Typist()
            t.type(typed + "x")
            XCTAssertEqual(t.string, shown, typed)
            XCTAssertEqual(t.markdown, markdown, typed)
            XCTAssertNotNil(ComposerDocument.blockKind(in: t.text, at: 0), typed)
        }
    }

    func testANumberedListStartsAtTheTypedNumberAndCountsOn() {
        let t = Typist()
        t.type("3. one\ntwo")
        XCTAssertEqual(t.string, "3. one\n4. two")
        XCTAssertEqual(t.markdown, "3. one\n4. two")
    }

    func testThingsThatLookLikeAMarkerStayText() {
        for typed in ["-5", "1.5 x", "a - b", "text 1. more", "-- x", "1234567890. x"] {
            let t = Typist()
            t.type(typed)
            XCTAssertEqual(t.string, typed, typed)
            XCTAssertNil(ComposerDocument.blockKind(in: t.text, at: 0), typed)
        }
    }

    func testNothingStartsInsideACodeBlock() {
        let t = Typist()
        t.text.append(NSAttributedString(string: "code", attributes: [.limeBlock: BlockKind.code.rawValue]))
        t.selection = NSRange(location: 4, length: 0)
        t.type(" - ")
        XCTAssertEqual(t.string, "code - ")
        XCTAssertTrue(ComposerDocument.blockKind(in: t.text, at: 0) == .code)
    }

    func testBackspaceRightAfterTheConversionGivesBackWhatWasTyped() {
        let t = Typist()
        t.type("- ")
        XCTAssertEqual(t.string, "• ")
        t.backspace()
        XCTAssertEqual(t.string, "- ")
        XCTAssertNil(ComposerDocument.blockKind(in: t.text, at: 0), "the paragraph is plain again")
        XCTAssertEqual(t.selection.location, 2)
        // Any other keystroke first commits the list.
        let u = Typist()
        u.type("1. a")
        u.selection = NSRange(location: 3, length: 0)
        u.backspace()
        XCTAssertEqual(u.string, "a", "after other typing, Backspace at the start removes the marker as before")
    }

    func testATypedMarkerInsideAListSwitchesTheKindAndBackspaceRestoresIt() {
        let t = Typist()
        t.type("- one\n1. ")
        XCTAssertEqual(t.string, "• one\n1. ", "a numbered marker typed in a bulleted list switches that item")
        XCTAssertTrue(ComposerDocument.blockKind(in: t.text, at: 6) == .number)
        t.backspace()
        XCTAssertEqual(t.string, "• one\n• 1. ", "undo returns the item and the typed text")
        XCTAssertTrue(ComposerDocument.blockKind(in: t.text, at: 6) == .bullet)
    }

    func testAThreeLevelOutlineByTyping() {
        let t = Typist()
        t.type("- a\n")
        t.indent()
        t.type("b\n")
        t.indent()
        t.type("c")
        XCTAssertEqual(t.string, "• a\n◦ b\n▪ c")
        XCTAssertEqual(t.markdown, "- a\n  - b\n    - c")
        // The level 2 item cannot go deeper.
        t.indent()
        XCTAssertEqual(t.markdown, "- a\n  - b\n    - c")
        XCTAssertEqual(ComposerDocument.markdown(from: ComposerDocument.attributed(fromMarkdown: t.markdown)), t.markdown)
    }

    func testIndentIsLimitedByTheItemAbove() {
        let t = Typist()
        t.type("- a")
        t.indent()
        XCTAssertEqual(t.markdown, "- a", "the first item cannot be indented")
        t.type("\nb")
        t.indent()
        t.indent()
        XCTAssertEqual(t.markdown, "- a\n  - b", "one deeper than the item above, at most")
        t.indent(false)
        XCTAssertEqual(t.markdown, "- a\n- b")
        t.indent(false)
        XCTAssertEqual(t.markdown, "- a\n- b", "outdent stops at level 0")
        let state = ComposerDocument.state(in: t.text, selection: t.selection, typing: [:])
        XCTAssertTrue(state.inList)
        XCTAssertTrue(state.canIndent)
        XCTAssertFalse(state.canOutdent)
    }

    func testIndentAppliesToEveryItemInTheSelection() {
        let text = ComposerDocument.attributed(fromMarkdown: "- a\n- b\n- c")
        let all = NSRange(location: 0, length: text.length)
        _ = ComposerDocument.shiftLevel(in: text, selection: all, indent: true)
        XCTAssertEqual(ComposerDocument.markdown(from: text), "- a\n  - b\n  - c", "the first item has nothing above; the others go one in")
        XCTAssertFalse(ComposerDocument.state(in: NSAttributedString(string: "plain"), selection: NSRange(location: 0, length: 0), typing: [:]).inList)
    }

    func testReturnContinuesTheLevelAndAnEmptyNestedItemStepsOut() {
        let t = Typist()
        t.type("1. a\n")
        t.indent()
        t.type("b\n")
        XCTAssertEqual(t.string, "1. a\n1. b\n2. ", "the next item has the same level and kind, counted per level")
        let last = (t.string as NSString).range(of: "2. ").location
        XCTAssertEqual(ComposerDocument.listLevel(in: t.text, at: last), 1)
        t.type("\n") // Return on the empty nested item
        XCTAssertEqual(ComposerDocument.listLevel(in: t.text, at: last), 0, "steps back out one level")
        XCTAssertEqual(t.string, "1. a\n1. b\n2. ")
        XCTAssertEqual(t.selection.location, t.text.length, "the caret stays after the marker")
        t.type("\n") // Return on the empty top item ends the list
        XCTAssertEqual(t.string, "1. a\n1. b\n")
        XCTAssertNil(ComposerDocument.typingAttributes(in: t.text, caret: t.text.length)[.limeBlock], "the next line is plain text again")
        XCTAssertEqual(t.markdown, "1. a\n  1. b")
    }

    func testBackspaceAtTheStartOfANestedItemOutdentsThenRemovesTheMarker() {
        let text = ComposerDocument.attributed(fromMarkdown: "- a\n  - b\n    - c")
        let t = Typist()
        t.text.append(text)
        t.selection = NSRange(location: t.text.length, length: 0)
        t.selection = NSRange(location: (t.string as NSString).range(of: "c").location, length: 0)
        t.backspace()
        XCTAssertEqual(t.markdown, "- a\n  - b\n  - c", "level 3 steps out to level 2")
        t.selection = NSRange(location: (t.string as NSString).range(of: "c").location, length: 0)
        t.backspace()
        t.selection = NSRange(location: (t.string as NSString).range(of: "c").location, length: 0)
        XCTAssertEqual(t.markdown, "- a\n  - b\n- c")
        t.backspace()
        XCTAssertEqual(t.string, "• a\n◦ b\nc", "at level 0 the marker goes (as before)")
    }

    func testMarkersAndNumbersAcrossThreeLevelsSurviveMarkdown() {
        let markdown = "1. a\n  1. b\n    1. c\n    2. d\n  2. e\n2. f\n  1. g"
        let text = ComposerDocument.attributed(fromMarkdown: markdown)
        XCTAssertEqual(text.string, "1. a\n1. b\n1. c\n2. d\n2. e\n2. f\n1. g")
        XCTAssertEqual(ComposerDocument.markdown(from: text), markdown)
        let bullets = ComposerDocument.attributed(fromMarkdown: "- a\n  - b\n    - c")
        XCTAssertEqual(bullets.string, "• a\n◦ b\n▪ c")
    }

    func testTheBubbleUsesTheCoresMarkers() {
        let blocks = MessageRender.blocks("- a\n  - b\n    - c\n1. x\n  1. y")
        guard case .list(let items)? = blocks.first else { return XCTFail("\(blocks)") }
        XCTAssertEqual(MessageRender.numbered(items).map(\.marker), ["•", "◦", "▪", "1.", "1."])
    }
}

/// LIME-137-fix: deleting a selection removes exactly the selected text; the single-Backspace marker rules stay.
/// `delete` plays what the text view's delegate and UIKit do for a delete (Select All + Delete, Cut, a drag selection).
final class ComposerDeletionTests: XCTestCase {
    private func text(_ markdown: String) -> NSMutableAttributedString { ComposerDocument.attributed(fromMarkdown: markdown) }

    @discardableResult
    private func delete(_ text: NSMutableAttributedString, _ range: NSRange) -> NSRange {
        var selection = range
        if ComposerDocument.handleMarkerDelete(in: text, range: range, selection: &selection) {
            ComposerDocument.renumber(text); ComposerDocument.restyle(text)
            return selection
        }
        text.deleteCharacters(in: range)
        selection = ComposerDocument.cleanUpAfterEdit(text, selection: NSRange(location: range.location, length: 0))
        ComposerDocument.renumber(text)
        ComposerDocument.restyle(text)
        return selection
    }

    private func range(of needle: String, in text: NSAttributedString, offset: Int = 0) -> Int {
        (text.string as NSString).range(of: needle).location + offset
    }

    func testSelectAllOverAThreeLevelOutlineLeavesNothing() {
        let t = text("- a\n  - b\n    - c")
        let selection = delete(t, NSRange(location: 0, length: t.length))
        XCTAssertEqual(t.string, "")
        XCTAssertEqual(selection.location, 0)
        XCTAssertNil(ComposerDocument.typingAttributes(in: t, caret: 0)[.limeBlock], "the next character typed is plain")
        XCTAssertEqual(ComposerDocument.markdown(from: t), "")
    }

    func testSelectAllOverNumberedAndMixedListsLeavesNothing() {
        let t = text("1. one\n2. two\n\n- x\n- y\n\ntrailing words")
        delete(t, NSRange(location: 0, length: t.length))
        XCTAssertEqual(t.string, "")
    }

    func testAMiddleToMiddleSelectionLeavesOneItemAtTheFirstItemsLevelAndKind() {
        let t = text("- alpha\n  - beta\n    - gamma")
        let start = range(of: "pha", in: t)
        let end = range(of: "mma", in: t)
        delete(t, NSRange(location: start, length: end - start))
        XCTAssertEqual(t.string, "• almma")
        XCTAssertEqual(ComposerDocument.markdown(from: t), "- almma")
        for index in 0..<t.length {
            XCTAssertEqual(ComposerDocument.listLevel(in: t, at: index), 0, "every character at \(index) is at item 1's level")
            XCTAssertTrue(ComposerDocument.blockKind(in: t, at: index) == .bullet)
        }
        let numbered = text("1. one\n2. two\n3. three")
        let from = range(of: "ne", in: numbered)
        let to = range(of: "ree", in: numbered)
        delete(numbered, NSRange(location: from, length: to - from))
        XCTAssertEqual(numbered.string, "1. oree")
        XCTAssertEqual(ComposerDocument.markdown(from: numbered), "1. oree")
    }

    func testASelectionFromPlainTextIntoAListLeavesPlainTextAndNoStrayMarker() {
        let t = text("intro\n\n- one\n- two")
        let start = range(of: "tro", in: t)
        let end = range(of: "wo", in: t)
        delete(t, NSRange(location: start, length: end - start))
        XCTAssertEqual(t.string, "inwo")
        XCTAssertNil(ComposerDocument.blockKind(in: t, at: 0))
        XCTAssertNil(ComposerDocument.blockKind(in: t, at: 3), "the list attributes of what was left are cleared")
        XCTAssertEqual(ComposerDocument.markdown(from: t), "inwo")
    }

    func testASelectionThatStartsInsideAMarkerLeavesNoHalfMarker() {
        let t = text("- a\n- b")
        delete(t, NSRange(location: 1, length: t.length - 1))
        XCTAssertEqual(t.string, "", "the stray bullet is not left behind")
        let numbered = text("1. a\n2. b")
        delete(numbered, NSRange(location: 1, length: numbered.length - 1))
        XCTAssertEqual(numbered.string, "")
    }

    func testASelectionThatEndsInsideALaterMarkerLeavesNoHalfMarker() {
        let t = text("- one\n- two")
        let start = range(of: "ne", in: t)
        let end = range(of: "• two", in: t, offset: 1) // after the bullet, before its space
        delete(t, NSRange(location: start, length: end - start))
        XCTAssertEqual(ComposerDocument.markdown(from: t), "- otwo", "item two's half marker is not kept as text")
        XCTAssertFalse(t.string.contains("•\u{20}") && t.string.hasSuffix("• two"))
    }

    func testBackspaceOverTheLineBreakJoinsTwoItemsWithoutAStrayMarker() {
        let t = text("- a\n- b")
        let newline = range(of: "\n", in: t)
        delete(t, NSRange(location: newline, length: 1))
        XCTAssertEqual(t.string, "• ab")
        XCTAssertEqual(ComposerDocument.markdown(from: t), "- ab")
    }

    func testASingleBackspaceAtTheStartOfAnItemStillFollowsTheMarkerRules() {
        let nested = text("- a\n  - b\n    - c")
        let cStart = range(of: "c", in: nested)
        delete(nested, NSRange(location: cStart - 1, length: 1))
        XCTAssertEqual(ComposerDocument.markdown(from: nested), "- a\n  - b\n  - c", "a nested item steps out one level")
        let top = text("- a\n- b")
        let bStart = range(of: "b", in: top)
        delete(top, NSRange(location: bStart - 1, length: 1))
        XCTAssertEqual(top.string, "• a\nb", "a level-0 item loses its marker")
        XCTAssertEqual(ComposerDocument.markdown(from: top), "- a\n\nb")
    }

    func testSelectingJustTheMarkerRemovesTheMarker() {
        let t = text("1. one\n2. two")
        delete(t, NSRange(location: 0, length: 3))
        XCTAssertEqual(t.string, "one\n1. two")
        XCTAssertNil(ComposerDocument.blockKind(in: t, at: 0))
    }
}
