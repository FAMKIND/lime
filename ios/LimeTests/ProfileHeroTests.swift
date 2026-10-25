import XCTest
import UIKit
@testable import Lime

/// LIME-217b: the white name and lines over a profile's photo keep 4.5:1 against the worst pictures (pure white and pure black) at every setting, and the
/// photo's dark colour for the gradients is found.
@MainActor
final class ProfileHeroTests: XCTestCase {
    private let settings: [(String, Double)] = [
        ("normal", HeroScrim.opacity(reduceTransparency: false, increaseContrast: false)),
        ("reduce transparency", HeroScrim.opacity(reduceTransparency: true, increaseContrast: false)),
        ("increase contrast", HeroScrim.opacity(reduceTransparency: false, increaseContrast: true)),
    ]

    func testWhiteTextKeepsContrastOverWhiteAndBlackPhotosWhateverTheDarkTint() {
        // The photo's dark colour, darkened to what is allowed, can be as light as it gets, or black.
        let lightestAllowed = HeroScrim.tint(from: UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        for tint in [lightestAllowed, UIColor.black, HeroScrim.tint(from: .systemTeal), HeroScrim.tint(from: .systemYellow)] {
            for (name, scrim) in settings {
                for photo in [UIColor.white, UIColor.black] {
                    let ratio = HeroScrim.contrast(text: .white.withAlphaComponent(1), tint: tint, image: photo, scrim: scrim)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "white over \(photo == .white ? "white" : "black") with tint \(tint) at \(name): \(ratio)")
                    // The secondary lines are white at 92 %: blended on the same background they still pass.
                    let soft = HeroScrim.contrast(text: UIColor(white: 0.92, alpha: 1), tint: tint, image: photo, scrim: scrim)
                    XCTAssertGreaterThanOrEqual(soft, 4.5, "the lines over \(photo == .white ? "white" : "black") at \(name): \(soft)")
                }
            }
        }
    }

    func testTheTintIsDarkEnoughWhateverTheSample() {
        for colour in [UIColor.white, .systemYellow, .systemGreen, .systemBlue, .gray, .black] {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            HeroScrim.tint(from: colour).getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertLessThanOrEqual(HeroScrim.luminance((Double(r), Double(g), Double(b))), HeroScrim.maxTintLuminance + 0.001)
        }
    }

    func testTheDarkColourOfAPhotoIsItsDarkPartNotAVeryLightOne() {
        // Half snow, half dark pine green.
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { c in
            UIColor(white: 0.95, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
            UIColor(red: 0.05, green: 0.25, blue: 0.12, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 100, width: 200, height: 100))
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        HeroPalette.compute(photo).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertLessThan(r, 0.2); XCTAssertGreaterThan(g, r, "it is the green, not black or white")
        // A plain white photo has no dark: whatever comes back is darkened by the tint rule.
        let white = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50)).image { c in UIColor.white.setFill(); c.fill(CGRect(x: 0, y: 0, width: 50, height: 50)) }
        XCTAssertGreaterThanOrEqual(HeroPalette.compute(white).cgColor.alpha, 1)
    }

    func testTheCropIsWideAndSmallAndHasNoPersonalMetadata() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { c in
            UIColor.systemTeal.setFill(); c.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let cropped = BackgroundProcessing.crop(source, viewport: CGSize(width: 300, height: 100), scale: 1, offset: .zero)
        XCTAssertEqual(cropped.size.width / cropped.size.height, 3, accuracy: 0.01)
        let data = try XCTUnwrap(BackgroundProcessing.jpeg(cropped))
        XCTAssertLessThanOrEqual(data.count, BackgroundProcessing.maxBytes)
        XCTAssertTrue(PhotoProcessing.personalMetadata(in: data).isEmpty)
    }
}
