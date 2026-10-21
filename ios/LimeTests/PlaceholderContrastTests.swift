import XCTest
@testable import Lime

/// LIME-188f: the soft grey of the article page's placeholders is readable in light and dark.
final class PlaceholderContrastTests: XCTestCase {
    private func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { Double(v) <= 0.03928 ? Double(v) / 12.92 : pow((Double(v) + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    private func ratio(_ a: UIColor, _ b: UIColor) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testThePlaceholderGreyMeetsFourPointFiveToOneOnTheCanvasInLightAndDark() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let grey = UIColor(Theme.placeholder).resolvedColor(with: traits)
            let canvas = UIColor(Theme.canvas).resolvedColor(with: traits)
            XCTAssertGreaterThanOrEqual(ratio(grey, canvas), 4.5, "\(style == .dark ? "dark" : "light"): \(ratio(grey, canvas))")
        }
    }
}
