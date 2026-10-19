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

    /// LIME-152h: a two-line message, with a sender's name above it, is shown whole at the very bottom and the very top: the stack moves, the
    /// message is never cut.
    func testATwoLineMessageWithANameIsWholeAtTheVeryBottomAndTheVeryTop() {
        let name: CGFloat = 22
        for y in [area.maxY - 52, area.minY] {
            let bubble = CGRect(x: 20, y: y, width: 220, height: 52)
            let p = MessageMenuLayout.place(bubble: bubble, nameHeight: name, bar: bar, menu: menu, in: area)
            XCTAssertFalse(p.isCapped, "a two-line message is never capped (y \(y))")
            XCTAssertEqual(p.bubble.size, bubble.size, "its full size")
            XCTAssertGreaterThanOrEqual(p.bar.minY, area.minY, "the bar is on the screen")
            XCTAssertLessThanOrEqual(p.menu.maxY, area.maxY, "the menu is on the screen")
            XCTAssertEqual(p.bar.maxY + MessageMenuLayout.gap + name, p.bubble.minY, accuracy: 0.01, "the bar, then the name's room, then the message")
            XCTAssertEqual(p.menu.minY, p.bubble.maxY + MessageMenuLayout.gap, accuracy: 0.01, "the menu right below the whole message")
        }
    }

    func testOnlyAMessageTallerThanTheRoomIsCapped() {
        let room = area.height - (bar.height + MessageMenuLayout.gap) - (MessageMenuLayout.gap + menu.height)
        let fits = MessageMenuLayout.place(bubble: CGRect(x: 20, y: 300, width: 200, height: room), nameHeight: 0, bar: bar, menu: menu, in: area)
        XCTAssertFalse(fits.isCapped, "exactly the room that is left is still whole")
        let tall = MessageMenuLayout.place(bubble: CGRect(x: 20, y: 300, width: 200, height: room + 1), nameHeight: 0, bar: bar, menu: menu, in: area)
        XCTAssertTrue(tall.isCapped)
    }
}
