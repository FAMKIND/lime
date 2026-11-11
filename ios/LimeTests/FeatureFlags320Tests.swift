import XCTest
@testable import Lime

/// LIME-320: co-editing is on unless a local off switch says otherwise; the old `coedit` default no longer decides.
final class FeatureFlags320Tests: XCTestCase {
    func testCoEditingIsOnUnlessASwitchIsOff() {
        XCTAssertTrue(FeatureFlags.coeditEnabled(launchOff: false, userOff: false))
        XCTAssertFalse(FeatureFlags.coeditEnabled(launchOff: true, userOff: false))
        XCTAssertFalse(FeatureFlags.coeditEnabled(launchOff: false, userOff: true))
        XCTAssertFalse(FeatureFlags.coeditEnabled(launchOff: true, userOff: true))
    }

    func testTheOldCoeditDefaultIsIgnoredAndCoeditOffTurnsItOff() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "coedit"); defaults.removeObject(forKey: "coedit_off")
        defer { defaults.removeObject(forKey: "coedit"); defaults.removeObject(forKey: "coedit_off") }
        defaults.set(false, forKey: "coedit")   // the old key that used to mean "off" in Release
        XCTAssertTrue(FeatureFlags.coedit, "the old key is ignored")
        defaults.set(true, forKey: "coedit_off")
        XCTAssertFalse(FeatureFlags.coedit, "the local off switch")
    }
}
