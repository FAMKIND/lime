import XCTest
@testable import Lime

final class GroupNameTests: XCTestCase {
    func testTheDefaultNameIsBuiltFromFirstNames() {
        XCTAssertEqual(GroupNames.defaultName(firstNames: ["Jean"]), "Jean")
        XCTAssertEqual(GroupNames.defaultName(firstNames: ["Jean", "Lee"]), "Jean & Lee")
        XCTAssertEqual(GroupNames.defaultName(firstNames: ["Jean", "Lee", "Sam"]), "Jean, Lee & Sam")
        XCTAssertEqual(GroupNames.defaultName(firstNames: ["Jean", "Lee", "Sam", "Pat", "Rae"]), "Jean, Lee, Sam +2")
        XCTAssertEqual(GroupNames.defaultName(firstNames: []), "New group")
        XCTAssertLessThanOrEqual(GroupNames.defaultName(firstNames: ["Bartholomew-Maximilian", "Wolfeschlegelstein", "Montgomery-Fitzgerald", "x"]).count, 50)
    }

    func testTheUnreadBadgeTextCapsAtNinetyNinePlus() {
        XCTAssertEqual(CountBadge.text(1), "1")
        XCTAssertEqual(CountBadge.text(99), "99")
        XCTAssertEqual(CountBadge.text(100), "99+")
        XCTAssertEqual(CountBadge.text(2_000), "99+")
    }
}
