import XCTest
@testable import Lime

/// LIME-235c: the marquee's motion and the player's tint.
final class Player235cTests: XCTestCase {
    func testAMarqueeOnlyMovesWhenTheTextOverflowsAndAtASlowSpeed() {
        XCTAssertEqual(MarqueeMotion.overflow(text: 200, box: 300), 0)
        XCTAssertEqual(MarqueeMotion.overflow(text: 450, box: 300), 150)
        XCTAssertEqual(MarqueeMotion.duration(overflow: 150), 5, accuracy: 0.01, "30 points a second")
        XCTAssertGreaterThanOrEqual(MarqueeMotion.duration(overflow: 1), 0.5)
        XCTAssertEqual(MarqueeMotion.startPause, 2)
    }

    func testTheTintKeepsWhiteTextAtFourAndAHalfToOneAtTopAndBottomForAnyCover() {
        let covers: [UIColor] = [.white, .yellow, .red, .cyan, .black, .orange, UIColor(red: 0.9, green: 0.8, blue: 0.5, alpha: 1)] + (0..<8).map { Theme.avatarUIColor($0, dark: false) }
        for deeper in [false, true] {
            for cover in covers {
                let tint = PlayerTint.colors(sampled: cover, fallbackTone: 0, deeper: deeper)
                XCTAssertGreaterThanOrEqual(PlayerTint.contrastWithWhite(tint.top), 4.5, "top, deeper \(deeper)")
                XCTAssertGreaterThanOrEqual(PlayerTint.contrastWithWhite(tint.bottom), 4.5, "bottom, deeper \(deeper)")
                XCTAssertGreaterThanOrEqual(PlayerTint.contrastWithWhite(tint.bottom), PlayerTint.contrastWithWhite(tint.top) - 0.01, "the bottom is the deeper one")
            }
        }
        // No cover: the default cover's tone, still readable.
        for tone in 0..<8 { XCTAssertGreaterThanOrEqual(PlayerTint.contrastWithWhite(PlayerTint.colors(sampled: nil, fallbackTone: tone, deeper: false).top), 4.5) }
    }
}
