import XCTest
@testable import Lime

/// LIME-233d: authors' colours read against the page; the draft's blocks map onto the editor's text and back.
final class CoEdit233dTests: XCTestCase {
    func testEveryAuthorColourReadsAtThreeToOneAgainstThePageInLightAndDark() {
        for tone in 0..<8 {
            XCTAssertGreaterThanOrEqual(PeerColor.contrast(PeerColor.color(tone: tone, dark: false), page: 1.0), 3.0, "tone \(tone) light")
            XCTAssertGreaterThanOrEqual(PeerColor.contrast(PeerColor.color(tone: tone, dark: true), page: 0.0), 3.0, "tone \(tone) dark")
        }
    }

    private func block(_ id: String, _ kind: String, _ words: String) -> DraftBlock {
        DraftBlock(id: id, kind: kind, level: 0, ordered: false, number: 0, attachment: 0, caption: "", url: "", colour: "",
                   spans: [Span(text: words, bold: false, italic: false, underline: false, strike: false, code: false, link: nil, mention: nil)])
    }

    func testBlocksMapToTheEditorAndBack() {
        let text = ComposerDocument.attributed(fromMarkdown: "# Plan\n\nFirst words here\n\n- one\n- two\n\nLast one", post: true)
        let blocks = [block("a", "h1", "Plan"), block("b", "paragraph", "First words here"), block("c", "item", "one"), block("d", "item", "two"), block("e", "paragraph", "Last one")]
        let slots = CoEditMap.slots(blocks: blocks, in: text)
        XCTAssertEqual(slots.map(\.id), ["a", "b", "c", "d", "e"])
        let ns = text.string as NSString
        let at = CoEditMap.position(blockID: "b", offset: 6, in: slots)!
        XCTAssertEqual(ns.substring(from: at).prefix(5), "words")
        let list = CoEditMap.position(blockID: "d", offset: 1, in: slots)!
        XCTAssertEqual(ns.substring(from: list).prefix(2), "wo")
        let back = CoEditMap.place(at, in: slots)!
        XCTAssertEqual(back.blockID, "b"); XCTAssertEqual(back.offset, 6)
        XCTAssertEqual(slots[1].ordinal, 2)
        XCTAssertEqual(CoEditMap.ordinalWords(3), "the third paragraph")
    }

    @MainActor func testPeersAreLiveForAWhileAndEditingForAShorterOne() {
        let peers = CoEditPeers()
        let jean = Person(id: "j", name: "Jean Park", tone: 2)
        peers.setAuthors([jean])
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(peers.isLive(peers.peers[0], now: now))
        peers.receive(from: "j", presence: DraftPresence(field: "body", blockId: "a", offset: 1, endBlockId: "", endOffset: 0, typing: true, away: false), now: now)
        XCTAssertTrue(peers.isLive(peers.peers[0], now: now.addingTimeInterval(20)))
        XCTAssertFalse(peers.isLive(peers.peers[0], now: now.addingTimeInterval(30)))
        XCTAssertTrue(peers.isEditing(peers.peers[0], now: now.addingTimeInterval(4)))
        XCTAssertFalse(peers.isEditing(peers.peers[0], now: now.addingTimeInterval(6)))
        peers.receive(from: "j", presence: DraftPresence(field: "body", blockId: "", offset: 0, endBlockId: "", endOffset: 0, typing: false, away: true), now: now.addingTimeInterval(7))
        XCTAssertFalse(peers.isLive(peers.peers[0], now: now.addingTimeInterval(8)), "leaving the editor takes the dot away")
    }
}
