import XCTest
@testable import Lime

/// LIME-326: a tab's spoken name starts with its visible word (WCAG 2.5.3) and then says what it is.
final class TabNames326Tests: XCTestCase {
    func testTheVisibleWordComesFirst() {
        for visible in ["link", "call", "jam"] { XCTAssertTrue(TabNames.spoken(visible).hasPrefix(visible)) }
    }

    func testWhatEachTabIs() {
        XCTAssertEqual(TabNames.spoken("link"), "link, messages")
        XCTAssertEqual(TabNames.spoken("call"), "call, calls")
        XCTAssertEqual(TabNames.spoken("jam"), "jam")
    }

    func testTheSystemSpeaksThePositionSoTheLabelHasNone() {
        for visible in ["link", "call", "jam"] { XCTAssertFalse(TabNames.spoken(visible).contains("tab")) }
    }
}
