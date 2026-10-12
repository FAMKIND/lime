import XCTest
@testable import Lime

final class ProfileTests: XCTestCase {
    private let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 11, _ minute: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testTheShortCallDateIsOneLineTodayYesterdayThisYearAndOtherYears() {
        let now = date(2026, 10, 11, 15, 0)
        let us = Locale(identifier: "en_US")
        func short(_ d: Date) -> String { CallGrouping.shortDate(d, now: now, calendar: calendar, locale: us).replacingOccurrences(of: "\u{202F}", with: " ") }
        XCTAssertEqual(short(date(2026, 10, 11)), "11:01 AM", "today: the time only")
        XCTAssertEqual(short(date(2026, 10, 10)), "Yesterday 11:01 AM")
        XCTAssertEqual(short(date(2026, 3, 4)), "Mar 4, 11:01 AM", "this year: no year")
        XCTAssertEqual(short(date(2025, 12, 31)), "Dec 31, 2025, 11:01 AM", "another year: with the year")
    }

    func testWhereAProfileIsOpenedDecidesWhatSharedShows() {
        let dm = ProfileRoute(userID: "jean", name: "Jean", conversationID: "dm:jean")
        XCTAssertEqual(dm.sharedConversation, "dm:jean")
        XCTAssertNil(dm.sharedSender, "in a DM: what you both shared")
        XCTAssertFalse(dm.isGroupContext)
        let group = ProfileRoute(userID: "jean", name: "Jean", conversationID: "grp:team")
        XCTAssertEqual(group.sharedConversation, "grp:team")
        XCTAssertEqual(group.sharedSender, "jean", "in a group: only what she shared there")
        XCTAssertTrue(group.isGroupContext)
        let fromCalls = ProfileRoute(userID: "jean", name: "Jean", callIDs: ["a"])
        XCTAssertEqual(fromCalls.sharedConversation, "dm:jean", "from a call row: the DM")
        XCTAssertNil(fromCalls.sharedSender)
    }
}
