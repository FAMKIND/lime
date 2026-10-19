import XCTest
@testable import Lime

/// LIME-170: what tapping a call in the Calls list does.
final class CallBackActionTests: XCTestCase {
    func testAPersonIsCalledAgainWhateverTheGroupLogicSays() {
        XCTAssertEqual(CallBackAction.decide(isGroup: false, liveCallID: nil), .callPerson)
        XCTAssertEqual(CallBackAction.decide(isGroup: false, liveCallID: "abc"), .callPerson)
    }

    func testAGroupWithACallOnIsJoined() {
        XCTAssertEqual(CallBackAction.decide(isGroup: true, liveCallID: "abc"), .joinGroup(callID: "abc"))
    }

    func testAGroupWithNoCallOnStartsANewOne() {
        XCTAssertEqual(CallBackAction.decide(isGroup: true, liveCallID: nil), .startGroup)
    }
}
