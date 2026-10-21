import XCTest
@testable import Lime

/// LIME-188e: pictures put into an article.
final class JamArticleTests: XCTestCase {
    private func pixel() -> UIImage { UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { $0.fill(CGRect(x: 0, y: 0, width: 10, height: 10)) } }

    func testAPictureInsertedAtTheCaretBecomesAnImageBlockOfItsOwn() {
        let text = NSMutableAttributedString(string: "Before after")
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
}
