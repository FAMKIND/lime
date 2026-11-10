import XCTest
@testable import Lime

/// LIME-130-4b: what a group call says as people come and go.
final class Access130fTests: XCTestCase {
    private func tile(_ id: String, _ name: String, me: Bool = false, speaking: Bool = false) -> GroupCallManager.Tile {
        var t = GroupCallManager.Tile(id: id, userID: id, name: name, isMe: me)
        t.speaking = speaking
        return t
    }
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testNothingIsSaidWhileTheCallIsComingUpOrForMe() {
        var a = GroupCallAnnouncer()
        XCTAssertEqual(a.update([tile("me", "Me", me: true)], active: false, now: t0, voiceOver: true), [])
        XCTAssertEqual(a.update([tile("me", "Me", me: true), tile("a", "Ana")], active: false, now: t0, voiceOver: true), [], "people already there")
        XCTAssertEqual(a.update([tile("me", "Me", me: true), tile("a", "Ana")], active: true, now: t0, voiceOver: true), [])
    }

    func testJoinsAndLeavesAreSaidByName() {
        var a = GroupCallAnnouncer()
        _ = a.update([tile("me", "Me", me: true)], active: true, now: t0, voiceOver: false)
        XCTAssertEqual(a.update([tile("me", "Me", me: true), tile("a", "Ana")], active: true, now: t0, voiceOver: false), ["Ana joined"])
        XCTAssertEqual(a.update([tile("me", "Me", me: true)], active: true, now: t0, voiceOver: false), ["Ana left"])
    }

    func testTheSpeakerIsSaidAtMostOnceEveryThreeSecondsAndOnlyForVoiceOver() {
        let me = tile("me", "Me", me: true)
        var a = GroupCallAnnouncer()
        _ = a.update([me, tile("a", "Ana"), tile("b", "Ben")], active: true, now: t0, voiceOver: true)
        XCTAssertEqual(a.update([me, tile("a", "Ana", speaking: true), tile("b", "Ben")], active: true, now: t0, voiceOver: true), ["Ana is speaking"])
        XCTAssertEqual(a.update([me, tile("a", "Ana"), tile("b", "Ben", speaking: true)], active: true, now: t0.addingTimeInterval(1), voiceOver: true), [], "too soon")
        XCTAssertEqual(a.update([me, tile("a", "Ana"), tile("b", "Ben", speaking: true)], active: true, now: t0.addingTimeInterval(3.1), voiceOver: true), ["Ben is speaking"])
        XCTAssertEqual(a.update([me, tile("a", "Ana"), tile("b", "Ben", speaking: true)], active: true, now: t0.addingTimeInterval(9), voiceOver: true), [], "the same speaker is not news")

        var quiet = GroupCallAnnouncer()
        _ = quiet.update([me, tile("a", "Ana")], active: true, now: t0, voiceOver: false)
        XCTAssertEqual(quiet.update([me, tile("a", "Ana", speaking: true)], active: true, now: t0, voiceOver: false), [], "no VoiceOver, no speaker")
        XCTAssertEqual(a.update([tile("me", "Me", me: true, speaking: true), tile("a", "Ana"), tile("b", "Ben")], active: true, now: t0.addingTimeInterval(30), voiceOver: true), [], "I never announce myself")
    }
}
