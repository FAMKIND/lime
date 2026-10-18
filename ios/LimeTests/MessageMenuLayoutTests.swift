import XCTest
@testable import Lime

/// LIME-152d: where the long-press menu's pieces go around the lifted message.
final class MessageMenuLayoutTests: XCTestCase {
    private let area = CGRect(x: 0, y: 0, width: 375, height: 700)
    private let bar = CGSize(width: 300, height: 56)
    private let menu = CGSize(width: 270, height: 336)

    func testAMessageInTheMiddleStaysWhereItWasWithTheBarAboveAndTheMenuBelow() {
        let bubble = CGRect(x: 20, y: 280, width: 200, height: 60)
        let p = MessageMenuLayout.place(bubble: bubble, nameHeight: 0, bar: bar, menu: menu, in: area)
        XCTAssertEqual(p.bubble, bubble, "not moved")
        XCTAssertFalse(p.isCapped)
        XCTAssertEqual(p.bar.maxY, bubble.minY - MessageMenuLayout.gap, accuracy: 0.01, "the reactions just above")
        XCTAssertEqual(p.menu.minY, bubble.maxY + MessageMenuLayout.gap, accuracy: 0.01, "the actions just below")
    }

    func testAMessageNearTheTopMovesDownJustEnoughForTheBar() {
        let bubble = CGRect(x: 20, y: 10, width: 200, height: 60)
        let p = MessageMenuLayout.place(bubble: bubble, nameHeight: 0, bar: bar, menu: menu, in: area)
        XCTAssertEqual(p.bar.minY, 0, accuracy: 0.01, "the bar is at the top edge")
        XCTAssertEqual(p.bubble.minY, bar.height + MessageMenuLayout.gap, accuracy: 0.01)
        XCTAssertEqual(p.bubble.size, bubble.size)
        XCTAssertLessThanOrEqual(p.menu.maxY, area.maxY)
    }

    func testAMessageNearTheBottomMovesUpSoTheMenuFits() {
        let bubble = CGRect(x: 20, y: 620, width: 200, height: 60)
        let p = MessageMenuLayout.place(bubble: bubble, nameHeight: 0, bar: bar, menu: menu, in: area)
        XCTAssertEqual(p.menu.maxY, area.maxY, accuracy: 0.01, "the menu ends at the bottom edge")
        XCTAssertEqual(p.bubble.maxY + MessageMenuLayout.gap, p.menu.minY, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(p.bar.minY, 0)
    }

    func testATallMessageIsCappedToTheRoomThatIsLeftAndFades() {
        let bubble = CGRect(x: 20, y: 100, width: 300, height: 900)
        let p = MessageMenuLayout.place(bubble: bubble, nameHeight: 0, bar: bar, menu: menu, in: area)
        XCTAssertTrue(p.isCapped)
        XCTAssertEqual(p.bar.minY, 0, accuracy: 0.01)
        XCTAssertEqual(p.menu.maxY, area.maxY, accuracy: 0.01)
        XCTAssertEqual(p.bubble.height, area.height - bar.height - menu.height - 2 * MessageMenuLayout.gap, accuracy: 0.01)
    }

    func testThePiecesLineUpWithTheSideTheMessageIsOnAndStayOnTheScreen() {
        let mine = CGRect(x: 150, y: 300, width: 205, height: 50)
        let p = MessageMenuLayout.place(bubble: mine, nameHeight: 0, bar: bar, menu: menu, in: area)
        XCTAssertEqual(p.menu.maxX, mine.maxX, accuracy: 0.01, "my own message: lined up on the right")
        XCTAssertLessThanOrEqual(p.bar.maxX, area.maxX)
        XCTAssertGreaterThanOrEqual(p.bar.minX, area.minX)
        let theirs = CGRect(x: 52, y: 300, width: 205, height: 50)
        let q = MessageMenuLayout.place(bubble: theirs, nameHeight: 0, bar: bar, menu: menu, in: area)
        XCTAssertEqual(q.menu.minX, theirs.minX, accuracy: 0.01, "someone else's: lined up on the left")
    }

    func testASendersNameStaysVisibleBetweenTheBarAndTheMessage() {
        let bubble = CGRect(x: 52, y: 300, width: 200, height: 60)
        let p = MessageMenuLayout.place(bubble: bubble, nameHeight: 18, bar: bar, menu: menu, in: area)
        XCTAssertEqual(p.bar.maxY, p.bubble.minY - 18 - MessageMenuLayout.gap, accuracy: 0.01, "room for the name above the message")
    }
}
