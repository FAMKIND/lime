import XCTest
@testable import Lime

/// LIME-188e: pictures put into an article.
final class JamArticleTests: XCTestCase {
    private func pixel() -> UIImage { UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { $0.fill(CGRect(x: 0, y: 0, width: 10, height: 10)) } }

    func testAPictureInsertedAtTheCaretBecomesAnImageBlockOfItsOwn() {
        let text = NSMutableAttributedString(string: "Before\nafter")
        let caret = ComposerDocument.insertImage(pixel(), index: 0, into: text, at: 7, width: 300)
        XCTAssertEqual(ComposerDocument.imageIndexes(in: text), [0])
        let markdown = ComposerDocument.markdown(from: text)
        XCTAssertEqual(markdown, "Before\n\n![](attachment:0)\n\nafter", "its own paragraph, between the words either side of the caret")
        XCTAssertGreaterThan(caret, 7)
        XCTAssertFalse(markdown.contains("\u{FFFC}"), "the placeholder character never reaches the text")
    }

    func testTwoPicturesKeepTheirNumbersAndOrder() {
        let text = NSMutableAttributedString(string: "One")
        var caret = ComposerDocument.insertImage(pixel(), index: 0, into: text, at: 3, width: 300)
        text.insert(NSAttributedString(string: "Two"), at: caret)
        caret += 3
        _ = ComposerDocument.insertImage(pixel(), index: 1, into: text, at: caret, width: 300)
        XCTAssertEqual(ComposerDocument.markdown(from: text), "One\n\n![](attachment:0)\n\nTwo\n\n![](attachment:1)")
        XCTAssertEqual(ComposerDocument.imageIndexes(in: text), [0, 1])
    }

    func testAPostReadsImageBlocksAndAChatNeverDoes() {
        let line = "![A caption](attachment:2)"
        if case .image(let caption, let index)? = MessageRender.blocks(line, post: true).first { XCTAssertEqual([caption, String(index)], ["A caption", "2"]) } else { XCTFail("a post reads it") }
        if case .paragraph? = MessageRender.blocks(line).first {} else { XCTFail("a chat leaves it as text") }
        XCTAssertEqual(JamInline.placed(in: "Hi\n\n![](attachment:0)\n\n![x](attachment:3)"), [0, 3])
    }

    func testTheTextOfAnImageBlockWritesBackTheSame() {
        let text = ComposerDocument.attributed(fromMarkdown: "x")
        XCTAssertEqual(ComposerDocument.markdown(from: text), "x")
        XCTAssertEqual(normalisePostMarkdown(text: "![Fig 1](attachment:0)"), "![Fig 1](attachment:0)")
        XCTAssertEqual(postPlainText(text: "Words\n\n![Fig 1](attachment:0)"), "Words\nFig 1")
    }

    // MARK: LIME-188l

    func testHeadingsQuotesIndentsAndButtonsRoundTripThroughTheEditor() {
        let markdown = "# Big\n\n## Medium\n\n### Small\n\n> quoted\n> twice\n\n  indented\n\n[[Go]](https://example.com/a)\n\nplain"
        let text = ComposerDocument.attributed(fromMarkdown: markdown, post: true)
        XCTAssertEqual(ComposerDocument.markdown(from: text, post: true), markdown)
        XCTAssertFalse(text.string.contains("#"), "the markers are not text in the editor")
        XCTAssertEqual(MessageRender.blocks(markdown, post: true).count, 7)
        // A chat reads the same words as plain paragraphs.
        XCTAssertTrue(MessageRender.blocks(markdown).allSatisfy { if case .paragraph = $0 { true } else { false } })
    }

    func testTheStripTogglesAParagraphStyleOnAndOff() {
        let text = ComposerDocument.attributed(fromMarkdown: "One\n\nTwo", post: true)
        let first = NSRange(location: 1, length: 0)
        XCTAssertTrue(ComposerDocument.toggleParagraphStyle("h2", in: text, selection: first))
        XCTAssertEqual(ComposerDocument.markdown(from: text, post: true), "## One\n\nTwo")
        XCTAssertFalse(ComposerDocument.toggleParagraphStyle("h2", in: text, selection: first), "the same again takes it off")
        ComposerDocument.shiftParagraphs(indent: true, in: text, selection: first)
        XCTAssertEqual(ComposerDocument.markdown(from: text, post: true), "  One\n\nTwo")
        ComposerDocument.shiftParagraphs(indent: false, in: text, selection: first)
        XCTAssertEqual(ComposerDocument.markdown(from: text, post: true), "One\n\nTwo")
        let caret = ComposerDocument.insertButton("Go", url: "https://example.com", into: text, at: text.length)
        XCTAssertGreaterThan(caret, 0)
        XCTAssertTrue(ComposerDocument.markdown(from: text, post: true).hasSuffix("[[Go]](https://example.com)"))
    }
}
