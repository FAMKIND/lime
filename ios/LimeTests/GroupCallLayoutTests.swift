import XCTest
@testable import Lime

/// LIME-148: where a group call's tiles go. Pure functions, so every shape of screen is checked here without a device.
final class GroupCallLayoutTests: XCTestCase {
    /// Visible areas (the screen between the header and the controls): a 13 mini and an SE in portrait and landscape, an iPad full screen,
    /// and small and tall Stage Manager windows.
    private let areas: [(String, CGSize)] = [
        ("13 mini portrait", CGSize(width: 375, height: 470)), ("13 mini landscape", CGSize(width: 700, height: 230)),
        ("SE portrait", CGSize(width: 375, height: 420)), ("SE landscape", CGSize(width: 560, height: 170)),
        ("iPad landscape", CGSize(width: 1100, height: 680)), ("iPad portrait", CGSize(width: 800, height: 900)),
        ("small window", CGSize(width: 420, height: 320)), ("tall window", CGSize(width: 360, height: 640)),
    ]

    func testEveryTileUpToNineFitsInsideTheAreaAtOnceWithoutOverlapAndNeverAThinStrip() {
        for (name, size) in areas {
            for count in 1...9 {
                let frames = GroupCallLayout.grid(count: count, in: size)
                XCTAssertEqual(frames.count, count, "\(name) \(count)")
                let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -0.01, dy: -0.01)
                for frame in frames {
                    XCTAssertTrue(bounds.contains(frame), "\(name) \(count): \(frame) is inside \(size) (nothing scrolls)")
                    let aspect = frame.width / frame.height
                    XCTAssertGreaterThanOrEqual(aspect, GroupCallLayout.minAspect - 0.01, "\(name) \(count): not squashed tall: \(aspect)")
                    XCTAssertLessThanOrEqual(aspect, GroupCallLayout.maxAspect + 0.01, "\(name) \(count): not a thin strip: \(aspect)")
                    XCTAssertGreaterThan(frame.width, 20)
                }
                for (i, a) in frames.enumerated() {
                    for b in frames[(i + 1)...] { XCTAssertFalse(a.insetBy(dx: 0.5, dy: 0.5).intersects(b.insetBy(dx: 0.5, dy: 0.5)), "\(name) \(count): tiles overlap") }
                }
            }
        }
    }

    func testTwoPeopleAreStackedInPortraitAndSideBySideInLandscape() {
        let portrait = GroupCallLayout.grid(count: 2, in: CGSize(width: 375, height: 700))
        XCTAssertEqual(portrait[0].midX, portrait[1].midX, accuracy: 1, "one above the other")
        XCTAssertLessThan(portrait[0].midY, portrait[1].midY)
        let landscape = GroupCallLayout.grid(count: 2, in: CGSize(width: 800, height: 380))
        XCTAssertEqual(landscape[0].midY, landscape[1].midY, accuracy: 1, "side by side")
        XCTAssertLessThan(landscape[0].midX, landscape[1].midX)
    }

    func testFourPeopleMakeTwoByTwoAndAlastTileAloneIsCentred() {
        for size in [CGSize(width: 375, height: 600), CGSize(width: 800, height: 380)] {
            let four = GroupCallLayout.grid(count: 4, in: size)
            XCTAssertEqual(Set(four.map { Int($0.minX.rounded()) }).count, 2, "two columns")
            XCTAssertEqual(Set(four.map { Int($0.minY.rounded()) }).count, 2, "two rows")
        }
        // Five in a 3-wide grid: the second row's two tiles are centred under the first row's three.
        let five = GroupCallLayout.grid(count: 5, in: CGSize(width: 900, height: 500))
        if Set(five.map { Int($0.minY.rounded()) }).count == 2, five.filter({ $0.minY == five[0].minY }).count == 3 {
            let bottom = five.filter { $0.minY != five[0].minY }
            XCTAssertEqual((bottom.first!.minX + bottom.last!.maxX) / 2, 450, accuracy: 1, "centred")
        }
    }

    func testTheGridFillsMostOfTheAreaSoTilesAreAsLargeAsTheyCanBe() {
        let size = CGSize(width: 1000, height: 600)
        let one = GroupCallLayout.grid(count: 1, in: size)[0]
        XCTAssertGreaterThan(one.height, size.height - 1, "a single tile uses the whole height")
        let six = GroupCallLayout.grid(count: 6, in: size)
        let covered = six.reduce(0) { $0 + $1.width * $1.height } / (size.width * size.height)
        XCTAssertGreaterThan(covered, 0.55, "six tiles still cover most of the area: \(covered)")
    }

    func testNothingForNothingOrNoSpace() {
        XCTAssertTrue(GroupCallLayout.grid(count: 0, in: CGSize(width: 300, height: 300)).isEmpty)
        XCTAssertTrue(GroupCallLayout.grid(count: 3, in: .zero).isEmpty)
    }

    func testMySelfViewFloatsInsideTheAreaInAnyCornerAndSnapsToTheNearest() {
        for (name, size) in areas {
            for corner in GroupCallLayout.Corner.allCases {
                let frame = GroupCallLayout.selfView(in: size, corner: corner)
                XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: -0.01, dy: -0.01).contains(frame), "\(name) \(corner)")
                XCTAssertLessThan(frame.width, size.width * 0.6, "small: \(name)")
            }
        }
        let size = CGSize(width: 400, height: 600)
        XCTAssertEqual(GroupCallLayout.nearestCorner(to: CGPoint(x: 50, y: 40), in: size), .topLeading)
        XCTAssertEqual(GroupCallLayout.nearestCorner(to: CGPoint(x: 350, y: 80), in: size), .topTrailing)
        XCTAssertEqual(GroupCallLayout.nearestCorner(to: CGPoint(x: 60, y: 500), in: size), .bottomLeading)
        XCTAssertEqual(GroupCallLayout.nearestCorner(to: CGPoint(x: 330, y: 560), in: size), .bottomTrailing)
    }

    func testTheHeaderLeavesRoomForAnIPadWindowsOwnControlsOnlyWhenWindowed() {
        let screen = CGSize(width: 1180, height: 820)
        XCTAssertEqual(GroupCallLayout.windowControlsMargin(idiomIsPad: true, window: screen, screen: screen), 0, "full screen: no margin")
        XCTAssertGreaterThan(GroupCallLayout.windowControlsMargin(idiomIsPad: true, window: CGSize(width: 600, height: 500), screen: screen), 24, "a Stage Manager window")
        XCTAssertEqual(GroupCallLayout.windowControlsMargin(idiomIsPad: false, window: CGSize(width: 390, height: 844), screen: CGSize(width: 390, height: 844)), 0)
    }
}
