import XCTest
import UIKit
@testable import Lime

/// LIME-217: the lines over a profile's background keep 4.5:1 against the worst pictures (pure white and pure black), light and dark,
/// at the normal scrim, with Reduce Transparency and with Increase Contrast.
@MainActor
final class ProfileHeroTests: XCTestCase {
    func testTheTextKeepsContrastOverWhiteAndBlackPicturesInLightAndDark() {
        for dark in [false, true] {
            let canvas = Theme.uiColor("Canvas", dark: dark)
            for (name, scrim) in [("normal", HeroScrim.opacity(reduceTransparency: false, increaseContrast: false)),
                                  ("reduce transparency", HeroScrim.opacity(reduceTransparency: true, increaseContrast: false)),
                                  ("increase contrast", HeroScrim.opacity(reduceTransparency: false, increaseContrast: true))] {
                for textName in [Theme.Name.text, Theme.Name.textSecondary] {
                    for image in [UIColor.white, UIColor.black] {
                        let ratio = HeroScrim.contrast(text: Theme.uiColor(textName, dark: dark), canvas: canvas, image: image, scrim: scrim)
                        XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(textName) over \(image == .white ? "white" : "black"), \(dark ? "dark" : "light"), \(name): \(ratio)")
                    }
                }
            }
        }
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
