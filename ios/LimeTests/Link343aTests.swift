import XCTest
@testable import Lime

/// LIME-343a: the two sides of linking a device, driven over an in-memory channel with scripted engines, and the rules of the list.
@MainActor
final class Link343aTests: XCTestCase {
    private func wait(_ what: String, timeout: TimeInterval = 30, until: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !until() {
            if Date() > end { XCTFail("timed out waiting for \(what)"); throw CancellationError() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private struct Auth: Sendable { let answer: Bool }

    private func sides(newEngine: FakeLinkNew = FakeLinkNew(), oldEngine: FakeLinkOld = FakeLinkOld(), allow: @escaping @Sendable () async -> Bool = { true }) -> (LinkToThisDevice, LinkFromPhone) {
        let (newEnd, oldEnd) = LoopbackMoveChannel.pair()
        let newSide = LinkToThisDevice(engine: newEngine, accept: { newEnd })
        let phone = LinkFromPhone(engine: oldEngine, connect: { oldEnd }, authenticate: allow)
        return (newSide, phone)
    }

    func testTheTwoNewMessagesAreFramedAndReadBack() {
        for message: MoveMessage in [.registered, .done] {
            let framed = message.framed
            XCTAssertEqual(MoveMessage.decode(tag: framed[4], payload: framed.dropFirst(5)), message)
        }
    }

    func testALinkRunsFromTheCodeToTheLastFortyFiveDays() async throws {
        let newEngine = FakeLinkNew(), oldEngine = FakeLinkOld()
        let (newSide, phone) = sides(newEngine: newEngine, oldEngine: oldEngine)
        newSide.start(); phone.start()
        try await wait("both codes") { if case .compare = newSide.phase, case .compare = phone.phase { true } else { false } }
        guard case .compare(let a) = newSide.phase, case .compare(let b) = phone.phase else { return XCTFail() }
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 6)
        newSide.matches(); phone.matches()
        try await wait("the package") { if case .receiving(.package) = newSide.phase { true } else { false } }
        try await wait("done") { newSide.phase == .done && phone.phase == .done }
        XCTAssertTrue(newEngine.registered, "the new device joined the account before the history")
        XCTAssertTrue(oldEngine.refreshed, "the phone refreshed its list of devices")
        XCTAssertTrue(oldEngine.confirmed)
        XCTAssertEqual(newEngine.chunks.count, 5, "four package chunks and the history pointer")
        XCTAssertFalse(newSide.historyMissing)
        XCTAssertFalse(phone.historyMissing)
    }

    func testThePhoneDoesNotSendAnythingUntilFaceIDOrThePasscodePasses() async throws {
        let oldEngine = FakeLinkOld()
        let (newSide, phone) = sides(oldEngine: oldEngine, allow: { false })
        newSide.start(); phone.start()
        try await wait("both codes") { if case .compare = newSide.phase, case .compare = phone.phase { true } else { false } }
        newSide.matches()
        phone.matches()
        try await wait("the refusal is shown") { phone.notYou }
        XCTAssertFalse(oldEngine.confirmed, "the code was not confirmed")
        if case .compare = phone.phase {} else { XCTFail("still at the code") }
        phone.cancel(); newSide.cancel()
    }

    func testAFullAccountStopsBothSidesWithTheSameWords() async throws {
        let newEngine = FakeLinkNew()
        newEngine.failRegistration = true
        let (newSide, phone) = sides(newEngine: newEngine)
        newSide.start(); phone.start()
        try await wait("both codes") { if case .compare = newSide.phase, case .compare = phone.phase { true } else { false } }
        newSide.matches(); phone.matches()
        try await wait("failed") { newSide.phase == .failed(.tooManyDevices) && phone.phase == .failed(.tooManyDevices) }
    }

    func testTheLastFortyFiveDaysMissingStillLinksTheDevice() async throws {
        let newEngine = FakeLinkNew()
        newEngine.failHistory = true
        let (newSide, phone) = sides(newEngine: newEngine)
        newSide.start(); phone.start()
        try await wait("both codes") { if case .compare = newSide.phase, case .compare = phone.phase { true } else { false } }
        newSide.matches(); phone.matches()
        try await wait("done") { newSide.phase == .done && phone.phase == .done }
        XCTAssertTrue(newSide.historyMissing, "said once on the new device")
    }

    func testCancellingOnTheNewDeviceStopsThePhone() async throws {
        let (newSide, phone) = sides()
        newSide.start(); phone.start()
        try await wait("both codes") { if case .compare = newSide.phase, case .compare = phone.phase { true } else { false } }
        newSide.cancel()
        phone.matches()
        try await wait("the phone knows") { if case .failed = phone.phase { true } else { false } }
    }

    func testTheListRules() {
        let day: Int64 = 1
        let phone = MyDevice(deviceId: "a", name: "My iPhone", kind: "phone", addedAt: day, isThisDevice: true)
        let tablet = MyDevice(deviceId: "b", name: "", kind: "tablet", addedAt: day, isThisDevice: false)
        let mac = MyDevice(deviceId: "c", name: "Work Mac", kind: "computer", addedAt: day, isThisDevice: false)
        XCTAssertFalse(LinkedDevicesRules.canUnlink(phone), "never this device")
        XCTAssertFalse(LinkedDevicesRules.canUnlink(tablet), "phones and tablets say 'Unlink from that device'")
        XCTAssertTrue(LinkedDevicesRules.canUnlink(mac))
        XCTAssertEqual(LinkedDevicesRules.title(tablet), "Tablet (no name yet)")
        XCTAssertTrue(LinkedDevicesRules.canLinkMore(count: 4))
        XCTAssertFalse(LinkedDevicesRules.canLinkMore(count: 5), "5 of 5: unlink one first")
        XCTAssertEqual(LinkedDevicesRules.symbol("computer"), "laptopcomputer")
    }
}
