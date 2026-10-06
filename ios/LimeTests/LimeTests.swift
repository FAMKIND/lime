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

    /// Light is the web's `--lime-primary-bg` (lime-100), unchanged. Dark is native-only (LIME-87-fix):
    /// the web's dark value (#0D2016) vanishes on the dark canvas.
    func testOwnBubbleIsThePrimaryColour() {
        XCTAssertEqual(Theme.Name.primary, "OwnBubble")
        XCTAssertEqual(hex(Theme.uiColor(Theme.Name.primary, dark: false)), "E4F9BE")
        XCTAssertEqual(hex(Theme.uiColor(Theme.Name.primary, dark: true)), "2D6A45")
    }

    func testLightValuesUnchangedFromLime87() {
        let expected = ["Canvas": "F9F8F4", "Surface": "F0EEE6", "BubbleOther": "FFFEFE", "BubbleEdge": "DDDDD9",
                        "OwnBubble": "E4F9BE", "OwnInk": "131B17", "TextPrimary": "131B17",
                        "TextSecondary": "504840", "Hairline": "DDDDD9"]
        for (name, value) in expected {
            XCTAssertEqual(hex(Theme.uiColor(name, dark: false)), value, name)
        }
    }

    private func oklab(_ c: UIColor) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        let (R, G, B) = (lin(r), lin(g), lin(b))
        let l = cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B)
        let m = cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B)
        let s = cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// Distance in OKLab, scaled by 100 (the unit the web's tone checks use).
    func testDarkPrimaryIsVisibleOnDarkCanvas() {
        let p = oklab(Theme.uiColor(Theme.Name.primary, dark: true))
        let c = oklab(Theme.uiColor(Theme.Name.canvas, dark: true))
        let d = 100 * sqrt(pow(p.0 - c.0, 2) + pow(p.1 - c.1, 2) + pow(p.2 - c.2, 2))
        XCTAssertGreaterThanOrEqual(d, 8, "OKLab distance \(d)")
    }

    func testDarkInkOnDarkPrimaryMeetsContrast() {
        let ratio = contrast(Theme.uiColor(Theme.Name.primaryInk, dark: true), Theme.uiColor(Theme.Name.primary, dark: true))
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "ratio \(ratio)")
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
