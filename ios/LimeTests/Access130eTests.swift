import XCTest
@testable import Lime

/// LIME-130-4a: what the 1:1 call screen says and how its toggles read.
final class Access130eTests: XCTestCase {
    func testEachPhaseChangeHasItsVisibleWords() {
        XCTAssertEqual(CallAnnouncements.phase(from: .idle, to: .outgoing), "Calling\u{2026}")
        XCTAssertEqual(CallAnnouncements.phase(from: .outgoing, to: .connecting), "Connecting\u{2026}")
        XCTAssertEqual(CallAnnouncements.phase(from: .connecting, to: .active), "Connected")
        XCTAssertEqual(CallAnnouncements.phase(from: .active, to: .idle), "Call ended")
        XCTAssertEqual(CallAnnouncements.phase(from: .outgoing, to: .idle), "Call ended")
        XCTAssertEqual(CallAnnouncements.ringing, "Ringing\u{2026}")
    }

    func testNothingIsSaidWhenNothingChangedOrIOSAnnouncesIt() {
        XCTAssertNil(CallAnnouncements.phase(from: .active, to: .active))
        XCTAssertNil(CallAnnouncements.phase(from: .idle, to: .idle))
        XCTAssertNil(CallAnnouncements.phase(from: .idle, to: .incoming), "iOS's own call screen announces an incoming call")
    }

    func testTheHintAndThePausedLineAreTheVisibleText() {
        XCTAssertEqual(CallAnnouncements.unreachable(name: "Jean"), "Jean\u{2019}s phone may be off or lime closed")
        XCTAssertEqual(CallAnnouncements.cameraPaused, "Your camera is paused while lime is in a window")
    }

    func testTogglesHaveAValueAndAnIconThatChangesShape() {
        XCTAssertEqual(CallAnnouncements.value(true), "On")
        XCTAssertEqual(CallAnnouncements.value(false), "Off")
        XCTAssertNotEqual(CallToggleIcon.mute(muted: true), CallToggleIcon.mute(muted: false))
        XCTAssertNotEqual(CallToggleIcon.camera(on: true), CallToggleIcon.camera(on: false))
        XCTAssertNotEqual(CallToggleIcon.speaker(on: true), CallToggleIcon.speaker(on: false))
    }
}
