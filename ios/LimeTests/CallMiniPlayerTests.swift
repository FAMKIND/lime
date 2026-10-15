import XCTest
@testable import Lime

final class CallMiniPlayerTests: XCTestCase {
    private func subject(_ groupIn: Bool, _ groupMin: Bool, _ callIn: Bool, _ callMin: Bool) -> CallMiniPlayerRule.Subject? {
        CallMiniPlayerRule.subject(groupInCall: groupIn, groupMinimized: groupMin, callInCall: callIn, callMinimized: callMin)
    }

    func testItShowsForAnyMinimisedCallAndNeverOnTheCallScreen() {
        XCTAssertEqual(subject(true, true, false, false), .group)
        XCTAssertEqual(subject(false, false, true, true), .oneToOne)
        XCTAssertNil(subject(true, false, false, false), "the full group call screen is up")
        XCTAssertNil(subject(false, false, true, false), "the full call screen is up")
        XCTAssertNil(subject(false, true, false, true), "no call going: a stale minimised flag shows nothing")
        XCTAssertNil(subject(false, false, false, false))
    }

    func testTheSubtitleNamesTheKindTheCountAndTheTimer() {
        XCTAssertEqual(CallMiniPlayerRule.subtitle(video: true, count: 3, clock: "1:01"), "Video call \u{00B7} 3 in call \u{00B7} 1:01")
        XCTAssertEqual(CallMiniPlayerRule.subtitle(video: false, count: 2, clock: "0:07"), "Voice call \u{00B7} 2 in call \u{00B7} 0:07")
        XCTAssertEqual(CallMiniPlayerRule.subtitle(video: true, count: 3, clock: "1:01", short: true), "Video call \u{00B7} 1:01", "the count drops first when tight")
    }

    func testTheSpokenDurationIsInWords() {
        XCTAssertEqual(CallMiniPlayerRule.spokenDuration("1:01"), "1 minute 1 second")
        XCTAssertEqual(CallMiniPlayerRule.spokenDuration("0:07"), "7 seconds")
        XCTAssertEqual(CallMiniPlayerRule.spokenDuration("2:00"), "2 minutes")
        XCTAssertEqual(CallMiniPlayerRule.spokenDuration("1:00:05"), "60 minutes 5 seconds")
    }
}
