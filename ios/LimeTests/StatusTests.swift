import XCTest
@testable import Lime

@MainActor
final class StatusPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-10-07 is a Wednesday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private let hours = WorkHours(enabled: true)   // Monday to Friday, 7:00 to 15:30

    func testInsideWorkHoursIsAvailableUntilTheyEndThenQuietUntilTheNextMorning() {
        let plan = StatusPlan.make(manual: nil, hours: hours, now: date(7, 10), calendar: calendar)
        XCTAssertEqual(plan.state, .available)
        XCTAssertEqual(plan.until, date(7, 15, 30))
        XCTAssertEqual(plan.thenState, .dnd)
        XCTAssertEqual(plan.thenUntil, date(8, 7))
        XCTAssertFalse(plan.isQuiet)
    }

    func testOutsideWorkHoursIsDoNotDisturbUntilTheNextStartAcrossAWeekend() {
        let evening = StatusPlan.make(manual: nil, hours: hours, now: date(7, 16), calendar: calendar)
        XCTAssertEqual([evening.state, evening.until == date(8, 7) ? .dnd : .away], [.dnd, .dnd])
        XCTAssertTrue(evening.isQuiet)
        let friday = StatusPlan.make(manual: nil, hours: hours, now: date(9, 16), calendar: calendar)   // Friday evening
        XCTAssertEqual(friday.until, date(12, 7), "Monday morning")
        XCTAssertEqual(friday.thenState, .available)
        let early = StatusPlan.make(manual: nil, hours: hours, now: date(7, 5), calendar: calendar)
        XCTAssertEqual(early.until, date(7, 7), "before work starts today")
    }

    func testWithoutWorkHoursAnyoneIsJustAvailable() {
        let plan = StatusPlan.make(manual: nil, hours: WorkHours(), now: date(7, 3), calendar: calendar)
        XCTAssertEqual(plan, StatusPlan(state: .available))
    }

    func testAStatusSetByHandWinsUntilItEndsThenTheScheduleTakesOver() {
        let manual = ManualStatus(state: .dnd, until: date(7, 11))
        let during = StatusPlan.make(manual: manual, hours: hours, now: date(7, 10), calendar: calendar)
        XCTAssertEqual(during.state, .dnd)
        XCTAssertEqual(during.until, date(7, 11))
        XCTAssertEqual(during.thenState, .available, "work hours resume")
        let after = StatusPlan.make(manual: manual, hours: hours, now: date(7, 12), calendar: calendar)
        XCTAssertEqual(after.state, .available, "an ended choice is ignored")
        let away = StatusPlan.make(manual: ManualStatus(state: .away, until: nil), hours: hours, now: date(7, 3), calendar: calendar)
        XCTAssertEqual(away, StatusPlan(state: .away), "until changed")
    }

    func testCaptionsUnderAContactsName() {
        let now = date(7, 20)
        XCTAssertNil(StatusPlan.caption(state: .available, until: nil, now: now, calendar: calendar))
        XCTAssertEqual(StatusPlan.caption(state: .dnd, until: nil, now: now, calendar: calendar), "Do not disturb")
        XCTAssertTrue(StatusPlan.caption(state: .dnd, until: date(8, 7), now: now, calendar: calendar)!.hasPrefix("Quiet hours until "))
        XCTAssertEqual(StatusPlan.caption(state: .away, until: nil, now: now, calendar: calendar), "Away")
    }

    func testTomorrowAtSeven() {
        XCTAssertEqual(StatusSheet.tomorrowSeven(now: date(7, 22), calendar: calendar), date(8, 7))
    }
}

@MainActor
final class QuietNotificationTests: XCTestCase {
    private func coordinator() -> (NotificationCoordinator, FakeCenter) {
        let name = "lime.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let center = FakeCenter()
        return (NotificationCoordinator(settings: NotificationSettings(defaults: defaults), center: center, feedback: center), center)
    }

    private func message(_ id: String) -> IncomingMessage {
        IncomingMessage(id: id, conversationID: "dm:lee", conversationTitle: "Lee Wong", senderID: "lee", senderName: "Lee Wong", text: "hi",
                        threadRoot: nil, isGroup: false, isRequest: false, date: Date())
    }

    func testWhileQuietMessagesArriveSilentlyThenOneSummaryWhenItEnds() async {
        let (notifications, center) = coordinator()
        await notifications.refreshAuthorization()
        var quiet = true
        notifications.isQuiet = { _ in quiet }
        await notifications.announce([message("a"), message("b")])
        XCTAssertNil(notifications.banner, "no banner")
        XCTAssertEqual(center.sounds, 0, "no sound")
        XCTAssertTrue(center.scheduled.isEmpty)
        XCTAssertEqual(notifications.held.count, 2)
        await notifications.releaseHeld()
        XCTAssertEqual(notifications.held.count, 2, "still quiet: still held")
        quiet = false
        await notifications.releaseHeld()
        XCTAssertTrue(notifications.held.isEmpty)
        XCTAssertEqual(notifications.banner?.content.title, "While you were away")
        XCTAssertEqual(notifications.banner?.content.body, "2 new messages from Lee Wong")
    }

    func testTheChatOnScreenStillTicksAndARequestIsNeverSummarised() async {
        let (notifications, center) = coordinator()
        notifications.isQuiet = { _ in true }
        notifications.viewing = ViewingTarget(conversationID: "dm:lee")
        await notifications.announce([message("a")])
        XCTAssertEqual(center.ticks, 1)
        XCTAssertTrue(notifications.held.isEmpty)
        notifications.viewing = nil
        var request = message("r")
        request = IncomingMessage(id: "r", conversationID: "dm:new", conversationTitle: "New", senderID: "x", senderName: "X", text: "hi", threadRoot: nil, isGroup: false, isRequest: true, date: Date())
        await notifications.announce([request])
        XCTAssertTrue(notifications.held.isEmpty, "a stranger's request is not summarised")
    }
}
