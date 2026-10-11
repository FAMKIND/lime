import UIKit
import XCTest
@testable import Lime

@MainActor
private final class FakeBacking: CallHistoryBacking {
    var rows: [CallRecord] = []
    var seen = false
    func add(_ record: CallRecord) { rows.removeAll { $0.id == record.id }; rows.append(record) }
    func list() -> [CallRecord] { rows.sorted { $0.date > $1.date } }
    func delete(ids: [String]) { rows.removeAll { ids.contains($0.id) } }
    func clear() { rows = [] }
    func markMissedSeen() { seen = true }
    func missedUnseen() -> Int { seen ? 0 : rows.filter(\.isMissedIncoming).count }
}

@MainActor
final class CallHistoryTests: XCTestCase {
    private let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    private func call(_ id: String, _ at: Date, _ outcome: CallOutcome = .completed, peer: String = "jean", video: Bool = false, outgoing: Bool = false) -> CallRecord {
        CallRecord(id: id, peerID: peer, peerName: peer.capitalized, video: video, outgoing: outgoing, date: at, duration: 60, outcome: outcome)
    }

    func testConsecutiveCallsOfTheSamePersonKindDayAndMissedClassFormOneRow() {
        let groups = CallGrouping.groups([
            call("a", date(10, 15), .missed), call("b", date(10, 14), .missed), call("c", date(10, 13), .missed),   // 3 missed, same day
            call("d", date(10, 12)),                                                                                  // answered: a new row
            call("e", date(10, 11), .missed),                                                                          // missed again after an answered one
            call("f", date(9, 20), .missed),                                                                           // another day
            call("g", date(9, 19), .missed, peer: "sam"),                                                                    // another person
            call("h", date(9, 18), .missed, peer: "sam", video: true),                                                       // another kind
        ], calendar: calendar)
        XCTAssertEqual(groups.map(\.count), [3, 1, 1, 1, 1, 1])
        XCTAssertEqual(groups.first?.id, "a")
        XCTAssertTrue(groups[0].isMissedIncoming)
        XCTAssertFalse(groups[1].isMissedIncoming)
    }

    func testTheTimeLabelsAreTimeYesterdayWeekdayThenDate() {
        let now = date(10, 16, 30)
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(CallGrouping.timeLabel(date(10, 16, 12), now: now, calendar: calendar, locale: us).replacingOccurrences(of: "\u{202F}", with: " "), "4:12 PM")
        XCTAssertEqual(CallGrouping.timeLabel(date(9, 23), now: now, calendar: calendar, locale: us), "Yesterday")
        XCTAssertEqual(CallGrouping.timeLabel(date(7, 9), now: now, calendar: calendar, locale: us), "Wednesday", "3 days ago: a weekday (Oct 7 2026 is a Wednesday)")
        XCTAssertEqual(CallGrouping.timeLabel(date(1, 9), now: now, calendar: calendar, locale: us), "10/1/2026", "older than 7 days: a short date")
    }

    func testMissedIncomingIsWhatMissedMeans() {
        XCTAssertTrue(call("a", date(10, 1), .missed).isMissedIncoming)
        XCTAssertFalse(call("b", date(10, 1), .missed, outgoing: true).isMissedIncoming, "an outgoing call nobody answered is not a missed call")
        XCTAssertFalse(call("c", date(10, 1), .declined).isMissedIncoming)
    }

    func testOldSettingsRecordsMoveIntoTheStoreOnceAndTheKeyIsRemoved() throws {
        let suite = "lime.test.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let old = [call("o1", date(8, 9)), call("o2", date(9, 9), .missed)]
        defaults.set(try JSONEncoder().encode(old), forKey: CallLog.legacyKey)
        let log = CallLog(defaults: defaults)
        let backing = FakeBacking()
        log.attach(backing)
        XCTAssertEqual(Set(backing.rows.map(\.id)), ["o1", "o2"], "moved into the store")
        XCTAssertNil(defaults.data(forKey: CallLog.legacyKey), "and the old key is gone")
        XCTAssertEqual(log.records.map(\.id), ["o2", "o1"])
        // attaching again moves nothing twice
        log.attach(backing)
        XCTAssertEqual(backing.rows.count, 2)
        // the badge follows the store, and opening the call tab clears it
        XCTAssertEqual(log.missedUnseen, 1)
        log.markMissedSeen()
        XCTAssertEqual(log.missedUnseen, 0)
        // delete and clear go to the store
        log.delete(ids: ["o1"])
        XCTAssertEqual(backing.rows.map(\.id), ["o2"])
        log.clear()
        XCTAssertTrue(backing.rows.isEmpty)
    }

    func testTheTabBadgeAppearanceUsesLimeGreenWithDarkDigits() {
        let appearance = TabBadgeStyle.appearance()
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            for state in [layout.normal, layout.selected] {
                XCTAssertEqual(state.badgeBackgroundColor, UIColor(Theme.accent))
                XCTAssertEqual(state.badgeTextAttributes[.foregroundColor] as? UIColor, UIColor(Theme.accentInk))
            }
        }
    }

    func testThePlusSitsBesideTheBarOnlyWhere64PointsFit() {
        XCTAssertFalse(FloatingPlus.fitsBesideBar(width: 375), "13 mini / SE")
        XCTAssertFalse(FloatingPlus.fitsBesideBar(width: 402), "18 Pro")
        XCTAssertTrue(FloatingPlus.fitsBesideBar(width: 1024), "an iPad")
        XCTAssertEqual(FloatingPlus.size, 64)
    }
}
