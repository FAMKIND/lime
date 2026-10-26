import XCTest
@testable import Lime

/// LIME-233g: someone else's change goes into the editor's text in place (only what differs), for every kind of block, and my caret moves by the change.
@MainActor
final class CoEdit233gTests: XCTestCase {
    private func view(_ markdown: String) -> UITextView {
        let view = UITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        view.attributedText = ComposerDocument.attributed(fromMarkdown: markdown, post: true)
        return view
    }

    private func change(_ before: String, _ after: String, caretAt: (NSString) -> Int, expect: (NSString) -> Int, file: StaticString = #filePath, line: UInt = #line) {
        let v = view(before)
        let old = v.text as NSString
        v.selectedRange = NSRange(location: caretAt(old), length: 0)
        let target = ComposerDocument.attributed(fromMarkdown: after, post: true)
        CoEditSplice.apply(target, into: v)
        XCTAssertEqual(v.text, target.string, file: file, line: line)
        XCTAssertEqual(v.selectedRange.location, expect(v.text as NSString), file: file, line: line)
    }

    func testAnInsertionBeforeMyCaretShiftsItAfterItDoesNot() {
        // Mid-word, before the caret (caret at the end of the paragraph).
        change("Hello world", "Hel-X-lo world", caretAt: { $0.length }, expect: { $0.length })
        // After the caret: the caret stays on the same character.
        change("Hello world", "Hello world, again", caretAt: { _ in 3 }, expect: { _ in 3 })
        // At the caret exactly: it stays before what arrived.
        change("Hello world", "HelXlo world", caretAt: { _ in 3 }, expect: { _ in 3 })
    }

    func testEveryKindOfBlockCanChangeInPlace() {
        let before = "# Plan\n\nFirst paragraph.\n\n- one\n- two\n\n> A quote\n\n![A picture](attachment:0)\n\n[Go](https://example.org)\n\nLast one."
        // A heading, a list item, a quote, a paragraph after a picture and the last paragraph each take a remote change, caret at the very end.
        for (from, to) in [("# Plan", "# Plans for us"), ("- two", "- two and three"), ("> A quote", "> A quote, said twice"), ("First paragraph.", "First paragraphs.")] {
            change(before, before.replacingOccurrences(of: from, with: to), caretAt: { $0.length }, expect: { $0.length })
        }
        // Words added exactly at my caret (the end of my text) arrive after it: my caret stays before them.
        change(before, before.replacingOccurrences(of: "Last one.", with: "Last one. Edited."), caretAt: { $0.length }, expect: { $0.length - " Edited.".count })
        // A new block in the middle and a removed one.
        change(before, before.replacingOccurrences(of: "Last one.", with: "New block.\n\nLast one."), caretAt: { $0.length }, expect: { $0.length })
        change(before, before.replacingOccurrences(of: "\n\n> A quote", with: ""), caretAt: { _ in 2 }, expect: { _ in 2 })
    }

    func testTheSameWordsInOtherStylesAreChangedInPlaceToo() {
        let v = view("Hello world")
        v.selectedRange = NSRange(location: 4, length: 0)
        let target = ComposerDocument.attributed(fromMarkdown: "**Hello** world", post: true)
        CoEditSplice.apply(target, into: v)
        XCTAssertEqual(ComposerDocument.markdown(from: v.textStorage, post: true), "**Hello** world")
        XCTAssertEqual(v.selectedRange.location, 4)
    }
}
