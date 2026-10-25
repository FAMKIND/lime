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

    func testWhiteTextKeepsContrastOnEveryDefaultHeroTone() {
        for dark in [false, true] {
            for tone in 0..<8 {
                let image = HeroDefault.tone(tone, dark: dark)
                let tint = HeroScrim.tint(from: HeroPalette.compute(image))
                // The lightest pixel of the gradient (its first colour) is what the text could sit over.
                let lightest = UIColor(Theme.avatar(tone)).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
                for (name, scrim) in settings {
                    let ratio = HeroScrim.contrast(text: .white, tint: tint, image: lightest, scrim: scrim)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "tone \(tone) \(dark ? "dark" : "light") at \(name): \(ratio)")
                }
            }
        }
    }

    func testTheDefaultFromAPhotoIsBlurredAndTheSameSizeAsATone() {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512)).image { c in
            UIColor.black.setFill(); c.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            UIColor.white.setFill(); c.fill(CGRect(x: 256, y: 0, width: 256, height: 512))   // a hard edge down the middle
        }
        let blurred = HeroDefault.blurred(photo)
        XCTAssertEqual(blurred.size, HeroDefault.tone(0, dark: false).size)
        // Across the old edge the brightness changes gradually: the pixel just either side of the middle differ far less than black vs white.
        func luma(_ x: Int) -> Double {
            guard let cg = blurred.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 0 }
            let o = 160 * cg.bytesPerRow + x * (cg.bitsPerPixel / 8)
            return Double(bytes[o]) / 255
        }
        XCTAssertLessThan(abs(luma(134) - luma(136)), 0.15, "no hard edge is left")
    }

    func testWhiteTextKeepsContrastOverPureWhiteAtEveryTextPosition() {
        // The name block starts below the avatar (29 % + half of it) and ends before the blend: sample every 2 % of a 812 pt screen from 30 % down to 70 %.
        let screen: CGFloat = 812
        let tint = HeroScrim.tint(from: .white)
        for (name, strength) in settings {
            var fraction = 0.30
            while fraction <= 0.70 {
                let covered = HeroScrim.overlay(at: CGFloat(fraction) * screen, screen: screen, strength: strength)
                let ratio = HeroScrim.contrast(text: .white, tint: tint, image: .white, scrim: covered)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "at \(Int(fraction * 100)) % of the height, \(name): \(ratio)")
                fraction += 0.02
            }
        }
        // The overlay is the same everywhere below the top: no band.
        XCTAssertEqual(HeroScrim.overlay(at: 200, screen: screen, strength: 0.7), HeroScrim.overlay(at: 500, screen: screen, strength: 0.7), accuracy: 1e-9)
        XCTAssertLessThan(HeroScrim.overlay(at: 0, screen: screen, strength: 0.7), 0.7 * 0.45, "lighter only at the very top")
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

    func testTheHeroIsMoreThanHalfTheScreenOnEveryIPhoneAndTheBlendIsLongAndEased() {
        for (width, height) in [(375.0, 667.0), (375.0, 812.0), (390.0, 844.0), (430.0, 932.0)] {
            let hero = HeroShape.heroHeight(screen: height)
            XCTAssertGreaterThanOrEqual(hero / height, 0.58, "\(width) x \(height)")
            // The hero's shape always fits inside the 4:5 frame that was saved or is only trimmed a little: its ratio is about 1.0 to 1.35 tall over wide.
            let tall = hero / width
            XCTAssertTrue((0.9...1.45).contains(tall), "\(width) x \(height): \(tall)")
            XCTAssertGreaterThanOrEqual((HeroShape.blendEnd - HeroShape.blendStart) * height, 0.19 * height, "the blend is about a fifth of the screen")
        }
        XCTAssertEqual(HeroShape.smooth(0), 0); XCTAssertEqual(HeroShape.smooth(1), 1); XCTAssertEqual(HeroShape.smooth(0.5), 0.5, accuracy: 1e-9)
        XCTAssertLessThan(HeroShape.smooth(0.05), 0.01, "no kink at the start")
        XCTAssertGreaterThan(HeroShape.smooth(0.95), 0.99, "none at the end")
        // The avatar's centre at 29 % and the pills' centre at 58 % on a 812 pt screen with a 104 pt header.
        let pad = HeroShape.avatarTopPadding(screen: 812, inset: 104, avatar: 104)
        XCTAssertEqual(104 + pad + 52, 812 * 0.29, accuracy: 1)
        XCTAssertEqual(104 + HeroShape.blockHeight(screen: 812, inset: 104) - HeroShape.pillsRow / 2, 812 * 0.58, accuracy: 1)
    }

    func testTheCropIsPortraitAndSmallAndHasNoPersonalMetadata() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { c in
            UIColor.systemTeal.setFill(); c.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
        }
        let cropped = BackgroundProcessing.crop(source, viewport: CGSize(width: 300, height: 375), scale: 1, offset: .zero)
        XCTAssertEqual(cropped.size.width / cropped.size.height, 0.8, accuracy: 0.01, "a 4:5 portrait")
        XCTAssertEqual(cropped.size.width, 1080)
        let data = try XCTUnwrap(BackgroundProcessing.jpeg(cropped))
        XCTAssertLessThanOrEqual(data.count, BackgroundProcessing.maxBytes)
        XCTAssertTrue(PhotoProcessing.personalMetadata(in: data).isEmpty)
    }
}
