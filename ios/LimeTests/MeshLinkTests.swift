import XCTest
@testable import Lime

/// LIME-141: the Bluetooth link's pure logic (framing, fragments and their caps, who connects to whom, running the engine's actions), without a
/// radio. The real proof is the device test.
@MainActor
final class MeshLinkTests: XCTestCase {
    // MARK: Framing

    func testAStreamFrameCarriesItsLengthAndSplitsBackIntoFramesHoweverTheBytesArrive() {
        let frames = [Data(repeating: 1, count: 300), Data(), Data(repeating: 2, count: 9000), Data([7])]
        let stream = frames.map(MeshStreamFramer.encode).reduce(Data(), +)
        var reader = MeshStreamReader()
        var got: [Data] = []
        // Arrives in odd little pieces.
        var offset = 0
        for size in [1, 3, 5, 100, 4096, 7, 8000, 3, 1] where offset < stream.count {
            let end = min(offset + size, stream.count)
            got += reader.append(stream.subdata(in: offset..<end))
            offset = end
        }
        got += reader.append(stream.subdata(in: offset..<stream.count))
        XCTAssertEqual(got, frames)
        XCTAssertFalse(reader.overflowed)
    }

    func testAnAnnouncedFrameBeyondTheCapPoisonsTheStream() {
        var reader = MeshStreamReader()
        var length = UInt32(MeshFraming.maxFrameBytes + 1).bigEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }
        XCTAssertEqual(reader.append(header + Data(repeating: 0, count: 10)), [])
        XCTAssertTrue(reader.overflowed, "the link is to be closed")
        XCTAssertEqual(reader.append(MeshStreamFramer.encode(Data([1]))), [], "nothing more is read from a poisoned stream")
    }

    // MARK: Fragments

    func testAFrameIsCutIntoFragmentsOfAboutFourHundredSeventyBytesAndPutBackTogetherInAnyOrder() {
        let frame = Data((0..<5_000).map { UInt8($0 % 251) })
        let fragments = MeshFragmenter.split(frame, id: 7)
        XCTAssertTrue(fragments.allSatisfy { $0.count <= MeshFraming.fragmentBytes }, "each fits one GATT message")
        XCTAssertEqual(fragments.count, (5_000 + 463) / 464)
        var reassembler = MeshReassembler()
        let now = Date()
        var out: Data?
        for fragment in fragments.shuffled() { if let whole = reassembler.accept(fragment, now: now) { out = whole } }
        XCTAssertEqual(out, frame)
        XCTAssertEqual(reassembler.unfinished, 0)
        // A frame that fits one fragment is one fragment.
        XCTAssertEqual(MeshFragmenter.split(Data([1, 2, 3]), id: 1).count, 1)
        var single = MeshReassembler()
        XCTAssertEqual(single.accept(MeshFragmenter.split(Data([1, 2, 3]), id: 1)[0], now: now), Data([1, 2, 3]))
    }

    func testTheReassemblerHoldsLittleAndForgetsAFrameThatDoesNotFinishInThirtySeconds() {
        var reassembler = MeshReassembler()
        let start = Date()
        let big = MeshFragmenter.split(Data(repeating: 9, count: 4_000), id: 1)
        _ = reassembler.accept(big[0], now: start)
        XCTAssertEqual(reassembler.unfinished, 1)
        // The rest arrives after the timeout: the first fragment was forgotten, so the frame does not complete.
        var finished: Data?
        for fragment in big.dropFirst() { if let whole = reassembler.accept(fragment, now: start.addingTimeInterval(31)) { finished = whole } }
        XCTAssertNil(finished)
        // Within the timeout it does.
        var again = MeshReassembler()
        for fragment in big { if let whole = again.accept(fragment, now: start.addingTimeInterval(29)) { finished = whole } }
        XCTAssertEqual(finished?.count, 4_000)
    }

    func testTheReassemblerRefusesWhatBreaksItsCaps() {
        var limits = MeshReassembler.Limits()
        limits.maxPartials = 3
        limits.maxTotalBytes = 3_000
        var reassembler = MeshReassembler(limits: limits)
        let now = Date()
        // Four unfinished frames: the fourth is refused.
        for id in 1...4 { _ = reassembler.accept(MeshFragmenter.split(Data(repeating: 1, count: 2_000), id: UInt16(id))[0], now: now) }
        XCTAssertEqual(reassembler.unfinished, 3, "at most 3 frames in progress")
        XCTAssertGreaterThan(reassembler.refused, 0)
        XCTAssertLessThanOrEqual(reassembler.heldBytes, 3_000, "the total cap holds")
        // Nonsense headers are refused.
        var plain = MeshReassembler()
        XCTAssertNil(plain.accept(Data([0, 1, 0, 5, 0, 2, 9]), now: now), "index beyond total")
        XCTAssertNil(plain.accept(Data([1, 2, 3]), now: now), "too short")
        XCTAssertNil(plain.accept(Data([0, 1, 0, 0, 0xFF, 0xFF, 9]), now: now), "an absurd number of fragments")
        XCTAssertGreaterThanOrEqual(plain.refused, 3)
        // A frame whose fragments would add up past the frame cap is dropped, and holds nothing.
        var capped = MeshReassembler(limits: { var l = MeshReassembler.Limits(); l.maxFrameBytes = 1_000; return l }())
        for fragment in MeshFragmenter.split(Data(repeating: 1, count: 2_000), id: 9) { _ = capped.accept(fragment, now: now) }
        XCTAssertEqual(capped.heldBytes, 0)
    }

    // MARK: Who connects to whom

    func testTheLowerIdInitiatesAndOnlyTheLowerIdsCentralLinkIsKept() {
        XCTAssertTrue(MeshLinkPolicy.iShouldInitiate(local: 5, remote: 9))
        XCTAssertFalse(MeshLinkPolicy.iShouldInitiate(local: 9, remote: 5))
        // The two phones agree: of the two links two phones make, exactly one survives.
        for (a, b) in [(1, 2), (2, 1), (100, 7)] as [(UInt64, UInt64)] {
            let aKeepsItsCentral = MeshLinkPolicy.keep(local: a, remote: b, iAmCentral: true)
            let bKeepsItsPeripheral = MeshLinkPolicy.keep(local: b, remote: a, iAmCentral: false)
            XCTAssertEqual(aKeepsItsCentral, bKeepsItsPeripheral, "both sides decide the same about A's central link")
            let bKeepsItsCentral = MeshLinkPolicy.keep(local: b, remote: a, iAmCentral: true)
            XCTAssertNotEqual(aKeepsItsCentral, bKeepsItsCentral, "exactly one of the two links is kept")
        }
    }

    func testTheRegistryKeepsOneLinkPerPhoneAndRefusesDuplicatesAndItself() {
        var registry = MeshLinkRegistry()
        XCTAssertEqual(registry.claim(remote: 9, local: 5, iAmCentral: true), .keep)
        XCTAssertEqual(registry.claim(remote: 9, local: 5, iAmCentral: true), .duplicate, "a second link to the same phone")
        XCTAssertEqual(registry.claim(remote: 9, local: 5, iAmCentral: false), .wrongDirection, "the lower id is me: I must be the central")
        XCTAssertEqual(registry.claim(remote: 3, local: 5, iAmCentral: true), .wrongDirection, "the other phone has the lower id: it connects to me")
        XCTAssertEqual(registry.claim(remote: 3, local: 5, iAmCentral: false), .keep)
        XCTAssertEqual(registry.claim(remote: 5, local: 5, iAmCentral: true), .myself)
        XCTAssertEqual(registry.live, [9, 3])
        registry.release(remote: 9)
        XCTAssertEqual(registry.claim(remote: 9, local: 5, iAmCentral: true), .keep, "after a drop the link can come back")
    }

    func testTheLinkIdRotatesEveryFifteenMinutesAndTheWeakestRSSIIsSkipped() {
        let start = Date()
        var next: UInt64 = 10
        let random = { () -> UInt64 in next += 1; return next }
        var identity = MeshLinkIdentity(now: start, random: random)
        let first = identity.id
        XCTAssertFalse(identity.rotateIfDue(now: start.addingTimeInterval(899), random: random))
        XCTAssertEqual(identity.id, first)
        XCTAssertTrue(identity.rotateIfDue(now: start.addingTimeInterval(900), random: random))
        XCTAssertNotEqual(identity.id, first)
        XCTAssertTrue(MeshLinkPolicy.rssiAllowsConnecting(-60))
        XCTAssertTrue(MeshLinkPolicy.rssiAllowsConnecting(-92))
        XCTAssertFalse(MeshLinkPolicy.rssiAllowsConnecting(-93))
        XCTAssertFalse(MeshLinkPolicy.rssiAllowsConnecting(127), "unknown")
    }

    // MARK: Running the engine's actions

    private final class FakeEngine: MeshEngineProtocol, @unchecked Sendable {
        var upActions: [UInt64: [MeshAction]] = [:]
        var frameActions: [MeshAction] = []
        var mine: UInt32 = 0
        private(set) var calls: [String] = []
        func frame(link: UInt64, bytes: Data) -> [MeshAction] { calls.append("frame \(link) \(bytes.count)"); return frameActions }
        func linkDown(link: UInt64) { calls.append("down \(link)") }
        func linkUp(link: UInt64) -> [MeshAction] { calls.append("up \(link)"); return upActions[link] ?? [] }
        func queueForSend(toUser: String, toDevice: String, ciphertext: Data) throws -> Bool { true }
        func queueProbe(toUser: String) throws -> Bool { true }
        func refreshTags() throws { calls.append("tags") }
        func stats() -> MeshStats { MeshStats(carried: 0, carriedBytes: 0, received: 0, duplicates: 0, rejected: 0, rateLimited: 0, evicted: 0, expired: 0, mine: 0, probesReceived: 0) }
        func takeMine() throws -> UInt32 { calls.append("takeMine"); defer { mine = 0 }; return mine }
        func takeUploadable() -> [MeshUpload] { [] }
        func uploadAll(transport: Transport, authToken: String) throws -> UInt32 { 0 }
        func uploadDone(id: Data) {}
        func uploadFailed(id: Data) {}
    }

    private final class FakeScheduler: MeshScheduler {
        private(set) var pending: [(Int, @MainActor () -> Void)] = []
        func after(milliseconds: Int, _ work: @escaping @MainActor () -> Void) { pending.append((milliseconds, work)) }
        func runAll() { let list = pending; pending = []; for (_, work) in list.sorted(by: { $0.0 < $1.0 }) { work() } }
    }

    private func action(_ link: UInt64, _ byte: UInt8, delay: UInt32 = 0) -> MeshAction { MeshAction(link: link, bytes: Data([byte]), delayMs: delay) }

    func testTheDriverSendsAtOnceWhatHasNoDelayAndSchedulesTheRestInOrderOfTheirDelays() {
        let engine = FakeEngine()
        engine.upActions[5] = [action(5, 1), action(5, 2, delay: 120), action(5, 3, delay: 30), action(5, 4)]
        let scheduler = FakeScheduler()
        var sent: [(UInt64, UInt8)] = []
        let driver = MeshDriver(engine: engine, scheduler: scheduler, transmit: { sent.append(($0, $1[0])) })
        driver.linkUp(5)
        XCTAssertEqual(sent.map(\.1), [1, 4], "no delay: now, in the engine's order")
        XCTAssertEqual(scheduler.pending.map(\.0), [120, 30])
        scheduler.runAll()
        XCTAssertEqual(sent.map(\.1), [1, 4, 3, 2], "the delayed ones follow by their delays")
    }

    func testADelayedFrameForALinkThatWentDownIsDropped() {
        let engine = FakeEngine()
        engine.upActions[5] = [action(5, 1, delay: 50)]
        let scheduler = FakeScheduler()
        var sent: [UInt8] = []
        let driver = MeshDriver(engine: engine, scheduler: scheduler, transmit: { sent.append($1[0]) })
        driver.linkUp(5)
        driver.linkDown(5)
        scheduler.runAll()
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(engine.calls, ["up 5", "down 5"])
    }

    func testFramesGoToTheEngineThenTheMailIsTaken() {
        let engine = FakeEngine()
        engine.frameActions = [action(5, 9)]
        engine.mine = 2
        var sent: [UInt8] = []
        var messages = 0
        let driver = MeshDriver(engine: engine, scheduler: FakeScheduler(), transmit: { sent.append($1[0]) })
        driver.onMessages = { messages += $0 }
        driver.linkUp(5)
        driver.receive(Data(repeating: 0, count: 40), on: 5)
        XCTAssertEqual(engine.calls, ["up 5", "frame 5 40", "takeMine"], "the frame, then the mail for this phone")
        XCTAssertEqual(sent, [9])
        XCTAssertEqual(messages, 2)
    }

    func testEveryWakeMakesTheTagsCurrentAndAnnouncesEveryLiveLinkAgain() {
        let engine = FakeEngine()
        engine.upActions[5] = [action(5, 1)]
        engine.upActions[8] = [action(8, 2)]
        var sent: [(UInt64, UInt8)] = []
        let driver = MeshDriver(engine: engine, scheduler: FakeScheduler(), transmit: { sent.append(($0, $1[0])) })
        driver.linkUp(8)
        driver.linkUp(5)
        sent = []
        driver.wake(reason: "discover")
        XCTAssertEqual(Array(engine.calls.suffix(3)), ["tags", "up 5", "up 8"], "tags first, then each live link in a stable order")
        XCTAssertEqual(sent.map(\.1), [1, 2])
        driver.linkDown(8)
        sent = []
        driver.wake(reason: "restore")
        XCTAssertEqual(sent.map(\.0), [5], "only the links that are still live")
    }

    func testAShortLinkIdIsFourCharactersAndRevealsLittle() {
        XCTAssertEqual(MeshDriver.short(0xABCDEF0123456789), "6789")
        XCTAssertEqual(MeshDriver.short(0x5).count, 1)
    }
}
