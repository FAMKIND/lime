import XCTest
@testable import Lime

/// LIME-209b: lime's starter pack is 24 files in the app, each with words and a size within the cap, and the words find them.
final class StickerPack209bTests: XCTestCase {
    func testThePackLoadsWithTwentyFourStickersEachWithItsWordsAndAFileWithinTheCap() throws {
        let pack = StickerPack.all
        XCTAssertEqual(pack.count, 24)
        XCTAssertEqual(Set(pack.map(\.id)).count, 24, "no two share a file")
        for sticker in pack {
            XCTAssertFalse(sticker.words.isEmpty, sticker.id)
            let url = try XCTUnwrap(sticker.url, "\(sticker.id).gif is in the app")
            let data = try Data(contentsOf: url)
            XCTAssertTrue(GIF.isGIF(data), sticker.id)
            XCTAssertLessThanOrEqual(data.count, 160 * 1024, "\(sticker.id) is \(data.count) bytes")
            XCTAssertLessThanOrEqual(GIF.frameCount(data), GIF.maxFrames)
            XCTAssertEqual(sticker.label, "lime sticker: \(sticker.words)")
        }
        XCTAssertLessThanOrEqual(try pack.reduce(0) { $0 + (try Data(contentsOf: XCTUnwrap($1.url)).count) }, 4 * 1024 * 1024, "the whole pack is at most about 4 MB")
    }

    func testWordsFindStickersByTheirWordsAndTheirOtherWords() {
        XCTAssertEqual(StickerPack.matching("birthday").map(\.id), ["happy-birthday"])
        XCTAssertEqual(StickerPack.matching("BDAY").map(\.id), ["happy-birthday"])
        XCTAssertEqual(StickerPack.matching("snow").map(\.id), ["snow-day"])
        XCTAssertEqual(StickerPack.matching("you got this").map(\.id), ["you-got-this"], "every word has to match")
        XCTAssertTrue(StickerPack.matching("tgif").map(\.id).contains("friday"))
        XCTAssertEqual(StickerPack.matching("   ").count, 24, "nothing typed shows all of them")
        XCTAssertTrue(StickerPack.matching("zzzz").isEmpty)
    }

    func testHidingThePackRemovesItEverywhere() {
        XCTAssertTrue(StickerPack.matching("", shown: false).isEmpty)
        XCTAssertTrue(StickerPack.matching("birthday", shown: false).isEmpty)
    }

    func testASentStickerIsAGIFAttachmentMyGIFsDoesNotSave() throws {
        let sticker = try XCTUnwrap(StickerPack.all.first { $0.id == "thank-you" })
        let item = try XCTUnwrap(StickerPack.attachment(sticker))
        XCTAssertTrue(GIF.isGIF(mime: item.mime))
        XCTAssertTrue(item.name.hasPrefix(StickerPack.namePrefix))
    }
}
