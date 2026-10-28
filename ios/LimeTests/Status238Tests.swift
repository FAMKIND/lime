import XCTest
import SwiftUI
@testable import Lime

/// LIME-238: a status badge sits in a round notch cut out of the avatar; Offline is an empty ring.
@MainActor
final class Status238Tests: XCTestCase {
    private func pixels<V: View>(_ view: V, side: Int) -> (CGImage, (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = renderer.cgImage!
        let data = image.dataProvider!.data!
        let bytes = CFDataGetBytePtr(data)!
        let bpp = image.bitsPerPixel / 8, stride = image.bytesPerRow
        return (image, { x, y in let o = y * stride + x * bpp; return (bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]) })
    }

    func testTheAvatarIsCutAwayAtTheBadgeAndWholeElsewhere() {
        // A 60 pt red disc with a 20 pt notch whose centre is 8 pt in from the bottom-right corner.
        let (_, pixel) = pixels(Rectangle().fill(.red).frame(width: 60, height: 60).statusNotch(true, box: 20, inset: 8), side: 60)
        XCTAssertEqual(pixel(52, 52).a, 0, "the notch's centre is empty: the background shows")
        XCTAssertEqual(pixel(20, 20).a, 255, "the rest of the avatar is whole")
        XCTAssertEqual(pixel(30, 50).a, 255)
        let (_, whole) = pixels(Rectangle().fill(.red).frame(width: 60, height: 60).statusNotch(false, box: 20, inset: 8), side: 60)
        XCTAssertEqual(whole(52, 52).a, 255, "no status, no notch")
    }

    func testTheOfflineBadgeIsAnEmptyRingWithNothingInside() {
        let size: CGFloat = 40
        let (image, pixel) = pixels(StatusBadge(state: .offline, size: size, onPhoto: true), side: Int(size) + 4)
        let c = image.width / 2
        XCTAssertEqual(pixel(c, c).a, 0, "the middle is empty: no fill, no avatar")
        // Somewhere on the ring (radius about (size - 1) / 2 - stroke / 2) there is white ink.
        let ringX = c + Int((size - 1) / 2 - size * 0.08)
        let ring = pixel(ringX, c)
        XCTAssertGreaterThan(ring.a, 200, "the ring is drawn")
        XCTAssertGreaterThan(Int(ring.r) + Int(ring.g) + Int(ring.b), 600, "white on a photo, no grey")
    }
}
