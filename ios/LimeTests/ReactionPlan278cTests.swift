import XCTest
@testable import Lime

/// LIME-278c and LIME-278d: where the reaction circles go.
final class ReactionPlan278cTests: XCTestCase {
    func testChipsPerRowFollowTheRoomAndNeverDropBelowOne() {
        XCTAssertEqual(ReactionPlan.perRow(room: 0), 1)
        XCTAssertEqual(ReactionPlan.perRow(room: 30), 1)
        XCTAssertEqual(ReactionPlan.perRow(room: 53), 2, "30 + 23")
        XCTAssertEqual(ReactionPlan.perRow(room: 30 + 23 * 5), 6)
    }

    func testMoreThanSixKindsShowSixAndAPlusN() {
        XCTAssertEqual(ReactionPlan.circles(kinds: 4), 4)
        XCTAssertEqual(ReactionPlan.circles(kinds: 6), 6)
        XCTAssertEqual(ReactionPlan.circles(kinds: 9), 7, "six circles and one +3")
    }

    func testTheFirstCircleIsAtTheInnerCornerAndTheRestGrowTowardTheSendersSide() {
        let width: CGFloat = 200
        let mine = (0..<4).map { ReactionPlan.x(index: $0, bubbleWidth: width, own: true, perRow: 4) }
        XCTAssertEqual(mine[0], ReactionPlan.inset, "mine start at the left (inner) corner")
        XCTAssertTrue(zip(mine, mine.dropFirst()).allSatisfy { $0 < $1 }, "and go right, toward my side: \(mine)")
        let theirs = (0..<4).map { ReactionPlan.x(index: $0, bubbleWidth: width, own: false, perRow: 4) }
        XCTAssertEqual(theirs[0] + ReactionPlan.chip, width - ReactionPlan.inset, "theirs start at the right (inner) corner")
        XCTAssertTrue(zip(theirs, theirs.dropFirst()).allSatisfy { $0 > $1 }, "and go left, toward their avatar: \(theirs)")
        XCTAssertGreaterThanOrEqual(theirs.min()!, 0, "never off the bubble's outer end for a wide enough bubble")
    }

    func testAnyCountStartsAtTheCornerAndNeverPassesTheInnerEdge() {
        for width in [44.0, 90, 200, 300] {
            for count in [1, 2, 3, 5, 7] {
                let plan = ReactionPlan.layout(circles: count, bubbleWidth: width)
                for index in 0..<count {
                    let mine = ReactionPlan.x(index: index, bubbleWidth: width, own: true, perRow: plan.perRow)
                    XCTAssertGreaterThanOrEqual(mine, 0, "mine never go left of the bubble (width \(width), \(count) circles)")
                    let theirs = ReactionPlan.x(index: index, bubbleWidth: width, own: false, perRow: plan.perRow)
                    XCTAssertLessThanOrEqual(theirs + ReactionPlan.chip, width, "theirs never go right of the bubble")
                }
            }
        }
    }

    func testTheyWrapAtTheBubblesOuterEdgeAndTheRoomUnderItGrows() {
        let small = ReactionPlan.layout(circles: 4, bubbleWidth: 44)
        XCTAssertEqual(small.perRow, 2, "a small bubble holds two, with the little overhang")
        XCTAssertEqual(small.rows, 2)
        let wide = ReactionPlan.layout(circles: 4, bubbleWidth: 300)
        XCTAssertEqual(wide.rows, 1, "a wide one keeps them on one line")
        XCTAssertGreaterThan(ReactionPlan.hang(rows: small.rows), ReactionPlan.hang(rows: wide.rows))
    }
}
