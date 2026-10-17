import XCTest
@testable import Lime

/// LIME-150: what the minimised group call shows, pure.
final class PiPGridPlanTests: XCTestCase {
    private func people(_ others: Int, speaking: Set<String> = [], pictures: Bool = true) -> [PiPGridPlan.Person] {
        [PiPGridPlan.Person(id: "me", name: "Me", isMe: true, speaking: false, hasPicture: pictures)]
            + (0..<others).map { PiPGridPlan.Person(id: "p\($0)", name: "P\($0)", isMe: false, speaking: speaking.contains("p\($0)"), hasPicture: pictures) }
    }

    func testOneTwoThreeFourAndMoreOthers() {
        func cells(_ n: Int, recent: [String] = []) -> [PiPGridPlan.Cell] { PiPGridPlan.cells(people: people(n), recent: recent, speakerID: nil, allLive: true) }
        XCTAssertEqual(cells(0).count, 0, "nobody else: the group's own picture")
        XCTAssertEqual(cells(1).map(\.id), ["p0"])
        XCTAssertEqual(cells(2).map(\.id), ["p0", "p1"])
        XCTAssertEqual(cells(3).map(\.id), ["p0", "p1", "p2", "me"], "three others: my own picture is the fourth cell")
        XCTAssertEqual(cells(4).map(\.id), ["p0", "p1", "p2", "p3"])
        let six = cells(6, recent: ["p4", "p1", "p5"])
        XCTAssertEqual(six.map(\.id), ["p4", "p1", "p5", "more"], "the three who spoke most recently and a +N cell")
        XCTAssertEqual(six.last?.kind, .more(3))
        XCTAssertEqual(six.last?.name, "+3")
        let none = cells(7)
        XCTAssertEqual(none.prefix(3).map(\.id), ["p0", "p1", "p2"], "nobody has spoken: the first three")
    }

    func testTheSpeakerIsMarkedAndAPersonWithoutAPictureIsNeverLive() {
        let cells = PiPGridPlan.cells(people: people(2, speaking: ["p1"]), recent: [], speakerID: "p1", allLive: true)
        XCTAssertEqual(cells.map(\.speaking), [false, true])
        XCTAssertEqual(cells.map(\.live), [true, true])
        let off = PiPGridPlan.cells(people: people(2, pictures: false), recent: [], speakerID: "p1", allLive: true)
        XCTAssertEqual(off.map(\.live), [false, false], "camera off or no key: the photo")
    }

    func testTheHeatGuardLightensToTheSpeakerOnly() {
        let hot = PiPGridPlan.cells(people: people(3), recent: [], speakerID: "p2", allLive: false)
        XCTAssertEqual(hot.map(\.live), [false, false, true, false], "only the speaker's picture; the others are photos in the same layout")
        XCTAssertEqual(PiPGridPlan.liveCount(hot), 1)
    }

    func testHeatGuardGoesOnAtSeriousAndOffAfterTwoCalmMinutesWithoutFlapping() {
        var guardian = PiPHeatGuard()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(guardian.update(thermal: .fair, now: t0))
        XCTAssertFalse(guardian.reduced)
        XCTAssertTrue(guardian.update(thermal: .serious, now: t0))
        XCTAssertTrue(guardian.reduced)
        XCTAssertFalse(guardian.update(thermal: .fair, now: t0.addingTimeInterval(10)))
        XCTAssertTrue(guardian.reduced, "fair is not yet calm enough")
        guardian.update(thermal: .serious, now: t0.addingTimeInterval(100))
        guardian.update(thermal: .nominal, now: t0.addingTimeInterval(110))
        XCTAssertTrue(guardian.update(thermal: .nominal, now: t0.addingTimeInterval(110 + 120)) == true, "back after 2 calm minutes")
        XCTAssertFalse(guardian.reduced)
        XCTAssertTrue(guardian.update(thermal: .critical, now: t0.addingTimeInterval(300)))
    }

    func testTheWindowsCellsFillItInsideATwoPointInsetWithAThinGap() {
        let size = CGSize(width: 480, height: 480)
        XCTAssertEqual(GroupCallLayout.pipGrid(count: 1, in: size), [CGRect(x: 2, y: 2, width: 476, height: 476)], "2 pt from every edge")
        let two = GroupCallLayout.pipGrid(count: 2, in: CGSize(width: 640, height: 480))
        XCTAssertEqual(two.map(\.minY), [2, 2], "a wide window: side by side")
        let stacked = GroupCallLayout.pipGrid(count: 2, in: CGSize(width: 300, height: 480))
        XCTAssertEqual(stacked.map(\.minX), [2, 2], "a tall window: stacked")
        let four = GroupCallLayout.pipGrid(count: 4, in: size)
        XCTAssertEqual(four.count, 4)
        XCTAssertEqual(four[0].width, 237)
        XCTAssertEqual(four[3].maxX, 478, "2 pt short of the edge")
        XCTAssertEqual(four[3].maxY, 478)
        XCTAssertEqual(four[1].minX - four[0].maxX, 2, "a 2 pt gap")
        XCTAssertTrue(GroupCallLayout.pipGrid(count: 0, in: size).isEmpty)
    }

    func testEachCellHasItsOwnCornerRadiusOfAboutEightToTenPointsScalingWithTheWindow() {
        XCTAssertEqual(GroupCallLayout.pipCornerRadius(for: CGSize(width: 120, height: 120)), 8)
        XCTAssertEqual(GroupCallLayout.pipCornerRadius(for: CGSize(width: 190, height: 190)), 9.5)
        XCTAssertEqual(GroupCallLayout.pipCornerRadius(for: CGSize(width: 400, height: 400)), 10)
    }
}
