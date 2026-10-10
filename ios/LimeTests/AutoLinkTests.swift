import XCTest
@testable import Lime

final class AutoLinkTests: XCTestCase {
    private func plain(_ text: String, link: String? = nil, code: Bool = false) -> Span {
        Span(text: text, bold: false, italic: false, underline: false, strike: false, code: code, link: link)
    }

    func testBareWebAddressesBecomeLinksInAnyCaseOfTheScheme() {
        let spans = MessageRender.autoLinked([plain("see https://famkind.com and HTTPS://famkind.com/x, then http://example.org.")])
        let links = spans.compactMap(\.link)
        XCTAssertEqual(links, ["https://famkind.com", "https://famkind.com/x", "http://example.org"], "the scheme is lower-cased and trailing punctuation stays outside")
        XCTAssertEqual(spans.map(\.text).joined(), "see https://famkind.com and HTTPS://famkind.com/x, then http://example.org.", "the words are unchanged")
    }

    func testCodeExistingLinksAndWordsThatAreNotAddressesAreLeftAlone() {
        XCTAssertEqual(MessageRender.autoLinked([plain("https://famkind.com", code: true)]).compactMap(\.link), [])
        XCTAssertEqual(MessageRender.autoLinked([plain("a link", link: "https://x.org")]).compactMap(\.link), ["https://x.org"])
        XCTAssertEqual(MessageRender.autoLinked([plain("no address, just http://localhost words")]).compactMap(\.link), [], "needs a dotted host")
        XCTAssertEqual(MessageRender.autoLinked([plain("")]).count, 1)
    }

    func testTheRenderedTextCarriesTheLinkStyle() {
        let text = MessageRender.attributed([plain("go to https://famkind.com now")], ink: .black, link: .green)
        let linked = text.runs.filter { $0.link != nil }
        XCTAssertEqual(linked.count, 1)
        XCTAssertEqual(linked.first?.link?.absoluteString, "https://famkind.com")
        XCTAssertEqual(linked.first?.underlineStyle, .single)
    }

    func testTheLinkCardLooksForBareAddressesInAnyCase() {
        XCTAssertEqual(LinkPreviewMaker.firstURL(in: "look HTTPS://famkind.com please")?.host, "famkind.com")
        XCTAssertEqual(LinkPreviewMaker.firstURL(in: "https://famkind.com")?.host, "famkind.com")
    }
}
