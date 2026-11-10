import XCTest
@testable import Lime

/// LIME-130-5b: onboarding fields, Emergency announcements, scan speech.
@MainActor
final class Access130hTests: XCTestCase {
    private func entry(_ id: String?, _ status: String) -> RollupEntry {
        RollupEntry(userId: id, status: status, situation: "", students: 0, place: "", note: "", at: 0, messageId: nil)
    }
    func testTheRollupSpeaksWhoNeedsHelpAndWhoIsSafeButNotYouOrNoResponse() {
        let old = [entry("a", "no_response"), entry("b", "need_help"), entry(nil, "no_response")]
        let new = [entry("a", "need_help"), entry("b", "safe"), entry(nil, "safe"), entry("c", "no_response")]
        let words = EmergencyAnnouncements.changes(old: old, new: new) { $0.userId == "a" ? "Ana" : "Ben" }
        XCTAssertEqual(words, ["Ana needs help", "Ben is safe"])
        XCTAssertEqual(EmergencyAnnouncements.changes(old: new, new: new) { _ in "x" }, [])
    }

    func testSeveralChangesBecomeACountAndOneIsSaidAsItIs() {
        XCTAssertEqual(EmergencyAnnouncements.summary(["Ana needs help"]), "Ana needs help")
        XCTAssertEqual(EmergencyAnnouncements.summary(["a", "b", "c"]), "3 people updated")
    }

    func testTheAnnouncerSpeaksOncePerTwoSecondsAndHoldsTheRest() {
        var words: [String] = []
        var time = Date(timeIntervalSince1970: 1000)
        let announcer = EmergencyAnnouncer(say: { words.append($0) }, now: { time })
        announcer.note(["Ana needs help"])
        XCTAssertEqual(words, ["Ana needs help"])
        time = time.addingTimeInterval(0.5)
        announcer.note(["Ben is safe"])
        announcer.note(["Cy is safe"])
        XCTAssertEqual(words, ["Ana needs help"], "held, not spoken inside two seconds")
        announcer.flushNow()
        XCTAssertEqual(words, ["Ana needs help", "2 people updated"])
        time = time.addingTimeInterval(5)
        announcer.note(["Di needs help"])
        XCTAssertEqual(words.last, "Di needs help")
    }

    func testAFieldReadsItsErrorElseItsExample() {
        XCTAssertEqual(OnboardingField.hint(problem: "Wrong password.", prompt: "you@example.com", isSecure: false), "Wrong password.")
        XCTAssertEqual(OnboardingField.hint(problem: "", prompt: "you@example.com", isSecure: false), "For example, you@example.com")
        XCTAssertEqual(OnboardingField.hint(problem: "", prompt: "Your password", isSecure: true), "")
    }

    func testTheScanSaysMatchesAndDoesntMatch() {
        XCTAssertEqual(ScanSpeech.matches("Ana"), "Matches. Ana is verified in person.")
        XCTAssertEqual(ScanSpeech.doesNotMatch("Ana"), "Doesn\u{2019}t match.")
    }
}
