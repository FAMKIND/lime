import XCTest
import UIKit
@testable import Lime

final class SampleDataTests: XCTestCase {
    func testConversationsAreNonEmpty() {
        XCTAssertFalse(SampleData.conversations().isEmpty)
    }

    func testEveryConversationHasNameAndMessage() {
        for c in SampleData.conversations() {
            XCTAssertFalse(c.title.isEmpty, c.id)
            XCTAssertFalse(c.messages.isEmpty, c.id)
        }
    }
}

final class ThemeTests: XCTestCase {
    private func hex(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    private func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// `--lime-primary-bg` is lime-100 in light and Seed's dark selected-subtle in dark.
    func testOwnBubbleIsThePrimaryColour() {
        XCTAssertEqual(Theme.Name.primary, "OwnBubble")
        XCTAssertEqual(hex(Theme.uiColor(Theme.Name.primary, dark: false)), "E4F9BE")
        XCTAssertEqual(hex(Theme.uiColor(Theme.Name.primary, dark: true)), "0D2016")
    }

    func testTextOnBubblesMeetsContrast() {
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let own = contrast(Theme.uiColor(Theme.Name.primaryInk, dark: dark), Theme.uiColor(Theme.Name.primary, dark: dark))
            let other = contrast(Theme.uiColor(Theme.Name.text, dark: dark), Theme.uiColor(Theme.Name.bubbleOther, dark: dark))
            XCTAssertGreaterThanOrEqual(own, 4.5, "own bubble \(mode)")
            XCTAssertGreaterThanOrEqual(other, 4.5, "other bubble \(mode)")
        }
    }
}

@MainActor
final class StoreTests: XCTestCase {
    func testSendAppendsOwnMessage() {
        let store = ConversationStore()
        let id = store.conversations[0].id
        let before = store.conversations[0].messages.count
        store.send("  hello  ", in: id)
        XCTAssertEqual(store.conversations[0].messages.count, before + 1)
        XCTAssertEqual(store.conversations[0].messages.last?.text, "hello")
        XCTAssertTrue(store.conversations[0].messages.last?.isOwn ?? false)
    }

    func testBlankSendIsIgnored() {
        let store = ConversationStore()
        let id = store.conversations[0].id
        let before = store.conversations[0].messages.count
        store.send("  \n ", in: id)
        XCTAssertEqual(store.conversations[0].messages.count, before)
    }
}
