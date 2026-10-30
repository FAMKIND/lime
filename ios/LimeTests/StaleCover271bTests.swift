import XCTest
import UIKit
@testable import Lime

/// LIME-271b: when the core drops a contact's picture and cover (their keys changed), what the app remembers is cleared too.
@MainActor
final class StaleCover271bTests: XCTestCase {
    func testAChangedPictureWithNoCoverClearsTheAvatarAndTheRememberedCover() {
        let id = "stale-\(UUID().uuidString)"
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { UIColor.red.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
        AvatarCache.shared.set(png, for: id)
        Hero.noteCover(id: "hero-\(id)", has: true)
        XCTAssertNotNil(AvatarCache.shared.image(for: id))
        XCTAssertTrue(Hero.remembered(id: "hero-\(id)", chosen: nil).cover || Hero.style != .ambient)

        // The core now holds neither (the refresh reported them changed, with no photo and no cover).
        AvatarCache.shared.set(nil, for: id)
        Hero.noteCover(id: "hero-\(id)", has: false)
        XCTAssertNil(AvatarCache.shared.image(for: id), "the default initials show again")
        XCTAssertFalse(Hero.remembered(id: "hero-\(id)", chosen: nil).cover, "and the profile no longer expects a cover")
    }
}
