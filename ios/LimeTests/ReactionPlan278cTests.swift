import XCTest
@testable import Lime

/// LIME-278c: where the reaction circles go.
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

    func testAShortBubbleFlowsTowardTheMiddleOnOneLineOnEveryPhone() {
        for width in [320.0, 375, 393, 430] {
            for own in [true, false] {
                let plan = ReactionPlan.layout(circles: 4, bubbleWidth: 40, own: own, screenWidth: width)
                XCTAssertEqual(plan.flow, .middle)
                XCTAssertEqual(plan.rows, 1, "4 circles fit on a \(width) pt screen (own: \(own))")
            }
        }
    }

    func testALongBubbleKeepsTheCirclesOnOneLineAlongItself() {
        let plan = ReactionPlan.layout(circles: 4, bubbleWidth: 300, own: true, screenWidth: 393)
        XCTAssertEqual(plan.flow, .along, "no room toward the middle: along the bubble")
        XCTAssertEqual(plan.rows, 1)
    }

    func testWhenNeitherSideHasRoomTheyWrapOntoMoreLinesNeverOffTheScreen() {
        let plan = ReactionPlan.layout(circles: 7, bubbleWidth: 150, own: true, screenWidth: 320)
        XCTAssertGreaterThan(plan.rows, 1)
        XCTAssertEqual(plan.rows, (7 + plan.perRow - 1) / plan.perRow)
        XCTAssertGreaterThan(ReactionPlan.hang(rows: plan.rows), ReactionPlan.hang(rows: 1), "the room under the bubble grows with the rows")
    }
}
