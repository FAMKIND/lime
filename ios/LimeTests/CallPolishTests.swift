import XCTest
@testable import Lime

/// LIME-150 (the call polish): the group picture includes me, and the mini player tucks into an edge tab.
@MainActor
final class CallPolishTests: XCTestCase {
    private func people(_ n: Int) -> [Person] { (0..<n).map { Person(id: "p\($0)", name: "P\($0) Q") } }
    private let me = Person(id: "me", name: "Me M")

    func testAPairIsTwoOverlappingCirclesTheOtherPersonInFrontAndMeBehind() {
        let plan = GroupAvatarPlan.make(others: people(1), me: me)
        XCTAssertEqual(plan, .pair(front: people(1)[0], back: me))
    }

    func testThreeOrFourInAllIsTheClusterOfEveryoneWithMeLast() {
        XCTAssertEqual(GroupAvatarPlan.make(others: people(2), me: me), .triangle(people(2) + [me]))
        XCTAssertEqual(GroupAvatarPlan.make(others: people(3), me: me), .ring(shown: people(3) + [me], extra: 0))
    }

    func testMoreThanFourShowsThreeAndAPlusNThatCountsMe() {
        XCTAssertEqual(GroupAvatarPlan.make(others: people(4), me: me), .ring(shown: Array(people(4).prefix(3)), extra: 2))
        XCTAssertEqual(GroupAvatarPlan.make(others: people(7), me: me), .ring(shown: Array(people(7).prefix(3)), extra: 5))
    }

    func testTheUIKitTwinDrawsThePair() {
        let pair = PiPGroupAvatarView(groupID: "grp:none", name: "G", emoji: nil, members: people(1), me: me)
        XCTAssertEqual(pair.clusterCount, 2, "two circles: the other person and me")
        let cluster = PiPGroupAvatarView(groupID: "grp:none", name: "G", emoji: nil, members: people(2), me: me)
        XCTAssertEqual(cluster.clusterCount, 3, "everyone, me last")
        let many = PiPGroupAvatarView(groupID: "grp:none", name: "G", emoji: nil, members: people(6), me: me)
        XCTAssertEqual(many.clusterCount, 4, "three others and the +N slot")
    }

    func testASwipeBeyondTheThresholdTucksToThatEdgeAndAShortOneDoesNot() {
        XCTAssertEqual(CallMiniPlayerTuck.edge(forTranslation: -80), .leading)
        XCTAssertEqual(CallMiniPlayerTuck.edge(forTranslation: 80), .trailing)
        XCTAssertNil(CallMiniPlayerTuck.edge(forTranslation: 30))
        var tuck = CallMiniPlayerTuck()
        XCTAssertFalse(tuck.isTucked)
        tuck.tuck(to: .trailing)
        XCTAssertEqual(tuck.edge, .trailing)
        tuck.show()
        XCTAssertFalse(tuck.isTucked)
    }

    func testTheMiniPlayerIsAsTallAsTheHeadersCircles() {
        XCTAssertEqual(CallMiniPlayer.height, 44)
        XCTAssertEqual(CallMiniPlayer.avatar, 32)
        XCTAssertLessThan(CallMiniPlayer.button, 44, "a 36 pt circle inside a 44 pt tap area")
    }
}
