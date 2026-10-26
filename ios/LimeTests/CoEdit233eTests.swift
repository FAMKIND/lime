import XCTest
@testable import Lime

/// LIME-233e: pictures that arrive in a draft's Markdown are drawn into the editor text without touching its words.
final class CoEdit233eTests: XCTestCase {
    func testPicturesInDraftMarkdownAreDrawnWhereTheyAreAndTheWordsStay() {
        let text = ComposerDocument.attributed(fromMarkdown: "First.\n\n![A picture](attachment:5)\n\nLast.", post: true)
        let words = text.string
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { UIColor.red.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 40, height: 20)) }
        var asked: [Int] = []
        ComposerDocument.attachImages(in: text, width: 200) { index in asked.append(index); return index == 5 ? image : nil }
        XCTAssertEqual(asked, [5])
        XCTAssertEqual(text.string, words, "the words are not changed")
        var drawn = 0
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in if value is NSTextAttachment { drawn += 1 } }
        XCTAssertEqual(drawn, 1)
        // A file this phone does not know yet keeps what it has.
        let again = ComposerDocument.attributed(fromMarkdown: "![x](attachment:9)", post: true)
        ComposerDocument.attachImages(in: again, width: 200) { _ in nil }
        var none = 0
        again.enumerateAttribute(.attachment, in: NSRange(location: 0, length: again.length)) { value, _, _ in if value is NSTextAttachment { none += 1 } }
        XCTAssertEqual(none, 0)
    }
}
