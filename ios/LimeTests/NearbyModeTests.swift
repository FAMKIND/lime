import XCTest
@testable import Lime

/// LIME-143: Nearby mode's rules and words.
final class NearbyModeTests: XCTestCase {
    func testItLastsTwoHoursAndThenIsOff() {
        let now = Date()
        XCTAssertTrue(NearbyMode.isOn(until: now.addingTimeInterval(NearbyMode.limit), now: now))
        XCTAssertFalse(NearbyMode.isOn(until: now.addingTimeInterval(-1), now: now))
        XCTAssertFalse(NearbyMode.isOn(until: nil, now: now))
        XCTAssertEqual(NearbyMode.limit, 7200)
    }

    func testTheOfferComesOnceWhenAMessageWaitsAndNobodyIsInRange() {
        XCTAssertTrue(NearbyMode.shouldOffer(waitingInChat: true, meshOn: true, phonesInRange: 0, nearbyOn: false, offeredBefore: false))
        XCTAssertFalse(NearbyMode.shouldOffer(waitingInChat: false, meshOn: true, phonesInRange: 0, nearbyOn: false, offeredBefore: false), "nothing waiting")
        XCTAssertFalse(NearbyMode.shouldOffer(waitingInChat: true, meshOn: false, phonesInRange: 0, nearbyOn: false, offeredBefore: false), "mesh off")
        XCTAssertFalse(NearbyMode.shouldOffer(waitingInChat: true, meshOn: true, phonesInRange: 2, nearbyOn: false, offeredBefore: false), "a phone is in range")
        XCTAssertFalse(NearbyMode.shouldOffer(waitingInChat: true, meshOn: true, phonesInRange: 0, nearbyOn: true, offeredBefore: false), "already on")
        XCTAssertFalse(NearbyMode.shouldOffer(waitingInChat: true, meshOn: true, phonesInRange: 0, nearbyOn: false, offeredBefore: true), "offered once already")
    }

    func testTheScreenStaysAwakeOnlyWhileLimeIsInFront() {
        XCTAssertTrue(NearbyMode.keepsScreenAwake(nearbyOn: true, appActive: true))
        XCTAssertFalse(NearbyMode.keepsScreenAwake(nearbyOn: true, appActive: false))
        XCTAssertFalse(NearbyMode.keepsScreenAwake(nearbyOn: false, appActive: true))
    }

    func testTheWordsAreHonest() {
        XCTAssertEqual(NearbyMode.statusLine, "Nearby mode on \u{00B7} keeps lime awake \u{00B7} uses more battery")
        XCTAssertTrue(NearbyMode.settingFootnote.contains("Off after 2 hours"))
        XCTAssertTrue(OfflineCopy.promise.joined().contains("swiped away"), "the honest limit lives behind Learn more")
        XCTAssertTrue(NearbyMode.plugInHint.contains("plugged in"))
    }
}
