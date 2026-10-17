import XCTest
@testable import Lime

/// LIME-142: real messages over the mesh, on the app's side: the statuses, the offline words, the outbox runner (what goes on the mesh, what is
/// logged, when it uploads). The core's own tests cover the outbox, parking, never re-encrypting and the duplicate.
@MainActor
final class MeshMessagesTests: XCTestCase {
    // MARK: The status machine

    func testEveryLocalStateMapsToAStatusAndOnlyTheMeshOnesHaveWordsAndIcons() {
        XCTAssertEqual(DeliveryState(localState: "sending"), .sending)
        XCTAssertEqual(DeliveryState(localState: "waiting"), .waiting)
        XCTAssertEqual(DeliveryState(localState: "passed"), .passed)
        XCTAssertEqual(DeliveryState(localState: "offline"), .offline)
        XCTAssertEqual(DeliveryState(localState: "sent"), .sent)
        XCTAssertEqual(DeliveryState(localState: "failed"), .failed)
        XCTAssertEqual(DeliveryState(localState: "undelivered"), .undelivered)
        XCTAssertEqual(DeliveryState(localState: "sent_local"), .sent, "older local-only states still count as sent")
        XCTAssertEqual(DeliveryState.waiting.statusWords, "Waiting for a phone nearby")
        XCTAssertEqual(DeliveryState.passed.statusWords, "Passed to a nearby phone")
        XCTAssertEqual(DeliveryState.offline.statusWords, "Waiting for internet")
        for state in [DeliveryState.waiting, .passed, .offline] {
            XCTAssertNotNil(state.statusSymbol, "words and an icon, never colour alone: \(state)")
        }
        for state in [DeliveryState.sending, .sent, .failed, .undelivered, .received, .system] {
            XCTAssertNil(state.statusWords)
        }
    }

    func testAMessageOnItsWayIsInFlightNotFailedAndOnlyARealFailureIsNotSent() {
        for state in [DeliveryState.sending, .waiting, .passed, .offline] { XCTAssertTrue(state.isInFlight, "\(state)") }
        for state in [DeliveryState.sent, .failed, .undelivered, .received, .system] { XCTAssertFalse(state.isInFlight, "\(state)") }
        // The offline states are not red and not tappable-to-retry: they resume by themselves (the core retries on any delivery).
        XCTAssertNotEqual(DeliveryState.waiting, .failed)
        XCTAssertNotEqual(DeliveryState.offline, .failed)
    }

    // MARK: The words

    func testTheOfflineBannerSaysHowMessagesWillGoAndTheSheetMakesTheHonestPromise() {
        XCTAssertEqual(OfflineCopy.banner(meshOn: true), "Offline \u{00B7} sending through nearby phones")
        XCTAssertEqual(OfflineCopy.banner(meshOn: false), "Offline \u{00B7} will send when you\u{2019}re online")
        XCTAssertEqual(OfflineCopy.sheetTitle, "No internet")
        XCTAssertEqual(OfflineCopy.sheetBody, "Messages hop phone to phone, sealed. They go when phones meet or anyone gets online. Photos wait for internet.")
        XCTAssertLessThanOrEqual(OfflineCopy.sheetBody.split(separator: " ").count, 22, "short enough to read in an emergency")
        let promise = OfflineCopy.promise.joined(separator: " ")
        XCTAssertTrue(promise.contains("at least one of them is awake"))
        XCTAssertTrue(promise.contains("swiped away"), "the limit is said plainly")
        XCTAssertTrue(promise.contains("can\u{2019}t read them"))
        XCTAssertTrue(promise.contains("Pictures, files"), "what cannot travel is said")
        // The older words for other problems are unchanged.
        XCTAssertEqual(ConnectionProblem.offline.message, "You're offline. Check your connection and try again.")
    }

    func testTheReasonForWaitingForInternetIsOneTrueLine() {
        let plain = Message(id: "1", senderID: nil, text: "hi", date: Date(), state: .offline, attachments: [])
        let me = Person(id: "me", name: "Me")
        let friend = Person(id: "lee", name: "Lee")
        let chat = Conversation(id: "dm:lee", title: "Lee", members: [friend], messages: [plain])
        XCTAssertTrue(OfflineReason.text(for: plain, in: chat).contains("No nearby phones"), "the general case")
        var stranger = chat
        stranger.isRequest = true
        XCTAssertTrue(OfflineReason.text(for: plain, in: stranger).contains("haven\u{2019}t accepted"), "someone who has not accepted you")
        _ = me
    }

    // MARK: The outbox runner

    private final class FakeEngine: MeshEngineProtocol, @unchecked Sendable {
        var queuedByPump: UInt32 = 0
        var notes: [String] = []
        private(set) var pumped = 0
        var version: UInt64 = 0
        func summaryVersion() -> UInt64 { version }
        func pumpOutbox() throws -> UInt32 { pumped += 1; defer { queuedByPump = 0 }; return queuedByPump }
        func takeNotes() -> [String] { defer { notes = [] }; return notes }
        func linkUp(link: UInt64) -> [MeshAction] { [MeshAction(link: link, bytes: Data([1]), delayMs: 0)] }
        func frame(link: UInt64, bytes: Data) -> [MeshAction] { [] }
        func linkDown(link: UInt64) {}
        func queueForSend(toUser: String, toDevice: String, ciphertext: Data) throws -> Bool { true }
        func queueProbe(toUser: String) throws -> String? { "ab12" }
        func refreshTags() throws {}
        func stats() -> MeshStats { MeshStats(carried: 0, carriedBytes: 0, received: 0, duplicates: 0, rejected: 0, rateLimited: 0, evicted: 0, expired: 0, mine: 0, probesReceived: 0) }
        func takeMine() throws -> UInt32 { 0 }
        func takeUploadable() -> [MeshUpload] { [] }
        func uploadAll(transport: Transport, authToken: String) throws -> UInt32 { 0 }
        func checkServerKey(transport: Transport, authToken: String) -> MeshKeyCheck? { nil }
        func uploadDone(id: Data) {}
        func uploadFailed(id: Data) {}
    }

    func testPumpingPutsWhatWaitedOnTheMeshAnnouncesItAndLogsTheNotes() {
        let engine = FakeEngine()
        var sent: [UInt64] = []
        var logged: [(String, [String: String])] = []
        let driver = MeshDriver(engine: engine, scheduler: ImmediateScheduler(), transmit: { link, _ in sent.append(link) })
        let runner = MeshOutboxRunner(engine: engine, driver: driver, log: { logged.append(($0, $1)) })
        driver.linkUp(7)
        sent = []
        // Nothing waiting: nothing happens.
        XCTAssertEqual(runner.pump(), 0)
        XCTAssertTrue(sent.isEmpty)
        // A message was kept for the mesh: it is queued, the summary moved, and the live link hears about it.
        engine.queuedByPump = 2
        engine.version += 1
        engine.notes = ["mesh_queued kind=message id=ab12 op=9f3c", "mesh_passed id=ab12"]
        XCTAssertEqual(runner.pump(), 2)
        XCTAssertEqual(sent, [7], "a Hello on the live link")
        XCTAssertEqual(logged.map(\.0), ["mesh_queued", "mesh_passed"])
        XCTAssertEqual(logged[0].1["kind"], "message")
        XCTAssertEqual(logged[0].1["id"], "ab12", "four characters, not a full id")
    }

    func testADeliveryNoteBecomesALogLineWithTheDelayAndHops() {
        let engine = FakeEngine()
        var logged: [(String, [String: String])] = []
        let runner = MeshOutboxRunner(engine: engine, driver: nil, log: { logged.append(($0, $1)) })
        engine.notes = ["mesh_delivered kind=probe id=cd34 after=9s hops=2"]
        runner.drainNotes()
        XCTAssertEqual(logged.first?.0, "mesh_delivered")
        XCTAssertEqual(logged.first?.1, ["kind": "probe", "id": "cd34", "after": "9s", "hops": "2"])
    }

    func testUploadsRunOnlyWithInternetAndOneAtATime() async {
        let engine = FakeEngine()
        var logged: [String] = []
        let runner = MeshOutboxRunner(engine: engine, driver: nil, log: { kind, _ in logged.append(kind) })
        var calls = 0
        let stored = await runner.uploadIfOnline(online: false) { calls += 1; return 3 }
        XCTAssertEqual(stored, 0, "offline: nothing to upload to")
        XCTAssertEqual(calls, 0)
        let again = await runner.uploadIfOnline(online: true) { calls += 1; return 3 }
        XCTAssertEqual(again, 3)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(logged, ["upload_skip", "mesh_uploaded"], "the skip while offline is logged, then the upload")
        // A second trigger while one is running is ignored.
        var inner: UInt32 = 99
        let outer = await runner.uploadIfOnline(online: true) {
            inner = await runner.uploadIfOnline(online: true) { calls += 1; return 5 }
            return 1
        }
        XCTAssertEqual(outer, 1)
        XCTAssertEqual(inner, 0, "one upload at a time")
        XCTAssertEqual(calls, 1)
        // A failed upload is tried again next time, and says so in the log.
        struct Boom: Error {}
        logged = []
        let failed = await runner.uploadIfOnline(online: true, trigger: "tick") { throw Boom() }
        XCTAssertEqual(failed, 0)
        XCTAssertFalse(runner.uploading)
        XCTAssertEqual(logged, ["upload_error"])
    }

    /// LIME-142-fix: a carrier that was online first and is handed a packet later uploads on the next tick; one that comes online later
    /// uploads on the connectivity change. The trigger is in the log either way.
    func testACarrierUploadsOnTheTickAfterItWasHandedSomethingAndOnTheConnectivityFlip() async {
        let engine = FakeEngine()
        var logged: [(String, [String: String])] = []
        let runner = MeshOutboxRunner(engine: engine, driver: nil, log: { logged.append(($0, $1)) })
        var calls = 0
        // Offline: the connectivity trigger is skipped and says why.
        _ = await runner.uploadIfOnline(online: false, trigger: "connectivity") { calls += 1; return 1 }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(logged.last?.0, "upload_skip")
        XCTAssertEqual(logged.last?.1["why"], "offline")
        // The network comes back: the flip uploads at once.
        _ = await runner.uploadIfOnline(online: true, trigger: "connectivity") { calls += 1; return 1 }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(logged.last?.1["trigger"], "connectivity")
        // Online already, handed something later: the next tick uploads it (a quiet tick is not logged when offline).
        logged = []
        _ = await runner.uploadIfOnline(online: false, trigger: "tick") { calls += 1; return 1 }
        XCTAssertTrue(logged.isEmpty, "a quiet tick offline stays quiet")
        _ = await runner.uploadIfOnline(online: true, trigger: "tick") { calls += 1; return 2 }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(logged.last?.1["trigger"], "tick")
    }

    private final class ImmediateScheduler: MeshScheduler {
        func after(milliseconds: Int, _ work: @escaping @MainActor () -> Void) { work() }
    }
}
