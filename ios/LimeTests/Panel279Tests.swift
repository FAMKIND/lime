import XCTest
@testable import Lime

/// LIME-279: the panel remembers its tab, a sticker picture keeps its transparency, and text with no Genmoji is left alone.
@MainActor
final class Panel279Tests: XCTestCase {
    func testTheLastTabIsRememberedAndAnUnknownOneMeansEmoji() {
        let key = ComposerPanelTab.rememberedKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.set("Stickers", forKey: key)
        XCTAssertEqual(ComposerPanelTab.remembered, .stickers)
        UserDefaults.standard.set("nonsense", forKey: key)
        XCTAssertEqual(ComposerPanelTab.remembered, .emoji)
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(ComposerPanelTab.remembered, .emoji)
        XCTAssertEqual(ComposerPanelTab.allCases.map(\.rawValue), ["Emoji", "GIFs", "Stickers"])
    }

    func testAStickerPictureIsAPNGWithinTheEdgeAndKeepsItsTransparency() throws {
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 600), format: format).image { c in
            UIColor.red.setFill(); c.cgContext.fillEllipse(in: CGRect(x: 300, y: 100, width: 600, height: 400))
        }
        let item = try XCTUnwrap(AttachmentProcessing.sticker(image))
        XCTAssertEqual(item.mime, "image/png")
        XCTAssertLessThanOrEqual(max(item.width ?? 0, item.height ?? 0), 512)
        let back = try XCTUnwrap(UIImage(data: item.bytes)?.cgImage)
        XCTAssertNotEqual(back.alphaInfo, .none)
        let corner = try XCTUnwrap(back.dataProvider?.data as Data?)
        XCTAssertEqual(corner[3], 0, "the corner is still clear")
    }

    func testTextWithoutGenmojiIsLeftAlone() {
        let storage = NSTextStorage(string: "Hello 😊 there")
        XCTAssertTrue(AdaptiveGlyphs.take(from: storage).isEmpty)
        XCTAssertEqual(storage.string, "Hello 😊 there")
    }

    func testWithoutAPanelEmojiIsJustTheKeyboard() {
        let model = RichComposerModel()
        XCTAssertFalse(model.hasPanel)
        model.makePanelView = { _, _ in UIView() }
        XCTAssertTrue(model.hasPanel)
    }
}
