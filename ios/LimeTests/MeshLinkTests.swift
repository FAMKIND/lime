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

    func testAHigherIdPhoneMayKeepItsLinkAfterTheGraceOnlyIfNoLinkToThatPhoneExists() {
        var registry = MeshLinkRegistry()
        XCTAssertEqual(registry.claim(remote: 3, local: 5, iAmCentral: true), .wrongDirection, "the lower id should connect to me")
        XCTAssertTrue(registry.claimFallback(remote: 3, local: 5), "it did not within the grace (it may be locked): keep mine")
        XCTAssertEqual(registry.claim(remote: 3, local: 5, iAmCentral: false), .duplicate, "if it connects after all, that link is the duplicate")
        XCTAssertFalse(registry.claimFallback(remote: 3, local: 5), "never two links to one phone")
        XCTAssertFalse(registry.claimFallback(remote: 5, local: 5), "never to myself")
        // The lower phone connected during the grace: the fallback is refused.
        var other = MeshLinkRegistry()
        XCTAssertEqual(other.claim(remote: 3, local: 5, iAmCentral: false), .keep)
        XCTAssertFalse(other.claimFallback(remote: 3, local: 5))
        other.release(remote: 3)
        XCTAssertTrue(other.claimFallback(remote: 3, local: 5), "after a drop it can be claimed again")
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
        XCTAssertTrue(MeshLinkPolicy.rssiAllowsConnecting(-96))
        XCTAssertFalse(MeshLinkPolicy.rssiAllowsConnecting(-97))
        XCTAssertTrue(MeshLinkPolicy.rssiAllowsConnecting(127), "127 is \"unavailable\", not weak")
    }

    // MARK: Running the engine's actions

    private final class FakeEngine: MeshEngineProtocol, @unchecked Sendable {
        var upActions: [UInt64: [MeshAction]] = [:]
        var frameActions: [MeshAction] = []
        var mine: UInt32 = 0
        var version: UInt64 = 0
        func summaryVersion() -> UInt64 { version }
        private(set) var calls: [String] = []
        func frame(link: UInt64, bytes: Data) -> [MeshAction] { calls.append("frame \(link) \(bytes.count)"); return frameActions }
        func linkDown(link: UInt64) { calls.append("down \(link)") }
        func linkUp(link: UInt64) -> [MeshAction] { calls.append("up \(link)"); return upActions[link] ?? [] }
        func queueForSend(toUser: String, toDevice: String, ciphertext: Data) throws -> Bool { true }
        func queueProbe(toUser: String) throws -> String? { "ab12" }
        func pumpOutbox() throws -> UInt32 { 0 }
        func takeNotes() -> [String] { [] }
        func refreshTags() throws { calls.append("tags") }
        func stats() -> MeshStats { MeshStats(carried: 0, carriedBytes: 0, received: 0, duplicates: 0, rejected: 0, rateLimited: 0, evicted: 0, expired: 0, mine: 0, probesReceived: 0) }
        func takeMine() throws -> UInt32 { calls.append("takeMine"); defer { mine = 0 }; return mine }
        func takeUploadable() -> [MeshUpload] { [] }
        func uploadAll(transport: Transport, authToken: String) throws -> UInt32 { 0 }
        func checkServerKey(transport: Transport, authToken: String) -> MeshKeyCheck? { nil }
        func onlineFrame() -> Data { Data([8, 0]) }
        func setRelayOnline(online: Bool) {}
        func fetchNeighbours() -> [UInt64] { [] }
        func fetchLinkDown(link: UInt64) {}
        func fetchFrameFor(link: UInt64) throws -> Data? { nil }
        func fetchReset() {}
        func takeFetchJobs() -> [MeshFetchJob] { [] }
        func relayFetch(transport: Transport, request: Data) -> Data { Data([7, 0]) }
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
        let driver = MeshDriver(engine: engine, scheduler: scheduler, transmit: { if $1[0] != 8 { sent.append(($0, $1[0])) } })
        driver.linkUp(5)
        XCTAssertEqual(sent.map(\.1), [1, 4], "no delay: now, in the engine's order")
        XCTAssertEqual(scheduler.pending.map(\.0), [120, 30])
        scheduler.runAll()
        XCTAssertEqual(sent.map(\.1), [1, 4, 3, 2], "the delayed ones follow by their delays")
    }

    /// LIME-155: a link that comes up is told whether this phone can fetch for it (the "online" frame, kind 8), and a change reaches every live link.
    func testALinkUpSendsTheOnlineFrameAndAChangeIsBroadcastToEveryLiveLink() {
        let engine = FakeEngine()
        var sent: [(UInt64, UInt8)] = []
        let driver = MeshDriver(engine: engine, scheduler: FakeScheduler(), transmit: { if $1[0] == 8 { sent.append(($0, $1[0])) } })
        driver.linkUp(5)
        driver.linkUp(6)
        XCTAssertEqual(sent.map(\.0), [5, 6], "each link hears it when it comes up")
        sent = []
        driver.broadcastOnline()
        XCTAssertEqual(sent.map(\.0), [5, 6], "a change reaches every live link")
        driver.linkDown(6)
        sent = []
        driver.broadcastOnline()
        XCTAssertEqual(sent.map(\.0), [5], "not a link that went down")
        XCTAssertTrue(engine.calls.contains("down 6"))
    }

    func testADelayedFrameForALinkThatWentDownIsDropped() {
        let engine = FakeEngine()
        engine.upActions[5] = [action(5, 1, delay: 50)]
        let scheduler = FakeScheduler()
        var sent: [UInt8] = []
        let driver = MeshDriver(engine: engine, scheduler: scheduler, transmit: { if $1[0] != 8 { sent.append($1[0]) } })
        driver.linkUp(5)
        driver.linkDown(5)
        scheduler.runAll()
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(engine.calls, ["up 5", "down 5"])
    }

    private final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }

    func testAFrameInIsNotAWakeItGoesToTheEngineAndTheMailIsTaken() {
        let engine = FakeEngine()
        engine.upActions[5] = [action(5, 1)]
        engine.frameActions = [action(5, 9)]
        engine.mine = 2
        var sent: [UInt8] = []
        var messages = 0
        let driver = MeshDriver(engine: engine, scheduler: FakeScheduler(), transmit: { if $1[0] != 8 { sent.append($1[0]) } })
        driver.onMessages = { messages += $0 }
        driver.linkUp(5)
        sent = []
        driver.receive(Data(repeating: 0, count: 40), on: 5)
        XCTAssertEqual(engine.calls, ["up 5", "frame 5 40", "takeMine"], "the frame and the mail, and no Hello: a data frame is not a wake")
        XCTAssertEqual(sent, [9], "only the engine's own answer went out")
        XCTAssertEqual(messages, 2)
        // Many more frames: still no re-announcement.
        for _ in 0..<100 { driver.receive(Data([0]), on: 5) }
        XCTAssertEqual(engine.calls.filter { $0 == "up 5" }.count, 1, "one Hello for the link, however many frames arrive")
    }

    func testANewLinkGetsOneHelloAndTwoWakesWithinThirtySecondsGiveOnePerLink() {
        let engine = FakeEngine()
        engine.upActions[5] = [action(5, 1)]
        engine.upActions[8] = [action(8, 2)]
        let clock = Clock()
        var sent: [(UInt64, UInt8)] = []
        let driver = MeshDriver(engine: engine, scheduler: FakeScheduler(), now: { clock.now }, transmit: { if $1[0] != 8 { sent.append(($0, $1[0])) } })
        driver.linkUp(8)
        driver.linkUp(5)
        XCTAssertEqual(sent.map(\.1), [2, 1], "a new link: a Hello at once")
        sent = []
        clock.now.addTimeInterval(5)
        driver.wake(reason: "discover-new")
        clock.now.addTimeInterval(10)
        driver.wake(reason: "app-active")
        XCTAssertTrue(sent.isEmpty, "wakes within 30 s of the last Hello and with nothing changed send nothing: \(sent)")
        XCTAssertEqual(engine.calls.filter { $0 == "tags" }.count, 2, "the tags are still made current on every wake")
        clock.now.addTimeInterval(20) // 35 s after the Hellos
        driver.wake(reason: "restore")
        XCTAssertEqual(sent.map(\.0).sorted(), [5, 8], "after 30 s a wake announces each live link once")
        sent = []
        driver.wake(reason: "restore-again")
        XCTAssertTrue(sent.isEmpty, "and not again at once")
        driver.linkDown(8)
        clock.now.addTimeInterval(40)
        driver.wake(reason: "app-foreground")
        XCTAssertEqual(sent.map(\.0), [5], "only the live link")
    }

    func testAChangedSummaryAnnouncesAtOnceAndAQueuedPacketAnnouncesOncePerLink() {
        let engine = FakeEngine()
        engine.upActions[5] = [action(5, 1)]
        engine.upActions[8] = [action(8, 2)]
        let clock = Clock()
        var sent: [(UInt64, UInt8)] = []
        let driver = MeshDriver(engine: engine, scheduler: FakeScheduler(), now: { clock.now }, transmit: { if $1[0] != 8 { sent.append(($0, $1[0])) } })
        driver.linkUp(5)
        driver.linkUp(8)
        sent = []
        clock.now.addTimeInterval(2)
        engine.version += 1 // this phone queued a packet
        driver.packetQueued()
        XCTAssertEqual(sent.map(\.0).sorted(), [5, 8], "within the 30 s, because the summary moved: one Hello per link")
        sent = []
        driver.packetQueued()
        driver.wake(reason: "app-active")
        XCTAssertTrue(sent.isEmpty, "the same version again: nothing")
        // A frame that changes what this phone holds tells the OTHER links once, not the one it came from.
        engine.frameActions = []
        engine.version += 1
        driver.receive(Data([1]), on: 5)
        XCTAssertEqual(sent.map(\.0), [8], "link 8 hears about the change; link 5 (the source) does not")
        sent = []
        driver.receive(Data([1]), on: 5)
        XCTAssertTrue(sent.isEmpty, "and once only")
    }

    func testAFrameStormIsLoggedOncePerMinuteWhileNothingChanges() {
        let engine = FakeEngine()
        let clock = Clock()
        var warnings = 0
        let driver = MeshDriver(engine: engine, scheduler: FakeScheduler(), now: { clock.now }, transmit: { _, _ in }, log: { kind, _ in if kind.hasPrefix("WARNING") { warnings += 1 } })
        driver.linkUp(5)
        for _ in 0..<49 { driver.receive(Data([1]), on: 5) }
        XCTAssertEqual(warnings, 0)
        for _ in 0..<200 { driver.receive(Data([1]), on: 5) }
        XCTAssertEqual(warnings, 1, "once, however long it goes on")
        clock.now.addTimeInterval(61)
        for _ in 0..<60 { driver.receive(Data([1]), on: 5) }
        XCTAssertEqual(warnings, 2, "and again in the next minute")
        // Frames that change what the phone holds are real work, not a storm.
        let busy = FakeEngine()
        var busyWarnings = 0
        let busyDriver = MeshDriver(engine: busy, scheduler: FakeScheduler(), now: { clock.now }, transmit: { _, _ in }, log: { kind, _ in if kind.hasPrefix("WARNING") { busyWarnings += 1 } })
        busyDriver.linkUp(5)
        for _ in 0..<500 { busy.version += 1; busyDriver.receive(Data([1]), on: 5) }
        XCTAssertEqual(busyWarnings, 0)
    }

    // MARK: A simulated loop

    /// A tiny stand-in for the engine's meeting protocol (Hello with a summary, Want, Packet, Ack): enough to see whether the driver lets three
    /// phones go quiet.
    private final class LoopEngine: MeshEngineProtocol, @unchecked Sendable {
        var have: Set<UInt8> = []
        var version: UInt64 = 0
        func summaryVersion() -> UInt64 { version }
        private func a(_ link: UInt64, _ bytes: [UInt8]) -> MeshAction { MeshAction(link: link, bytes: Data(bytes), delayMs: 0) }
        func linkUp(link: UInt64) -> [MeshAction] { [a(link, [1] + have.sorted())] }
        func frame(link: UInt64, bytes: Data) -> [MeshAction] {
            let b = [UInt8](bytes)
            guard let kind = b.first else { return [] }
            let ids = Array(b.dropFirst())
            switch kind {
            case 1: let want = ids.filter { !have.contains($0) }; return want.isEmpty ? [] : [a(link, [2] + want)]
            case 2: return ids.filter { have.contains($0) }.map { a(link, [3, $0]) }
            case 3:
                if let id = ids.first, !have.contains(id) { have.insert(id); version += 1 }
                return [a(link, [4] + ids)]
            default: return []
            }
        }
        func linkDown(link: UInt64) {}
        func queueForSend(toUser: String, toDevice: String, ciphertext: Data) throws -> Bool { true }
        func queueProbe(toUser: String) throws -> String? { "ab12" }
        func pumpOutbox() throws -> UInt32 { 0 }
        func takeNotes() -> [String] { [] }
        func refreshTags() throws {}
        func stats() -> MeshStats { MeshStats(carried: UInt32(have.count), carriedBytes: 0, received: 0, duplicates: 0, rejected: 0, rateLimited: 0, evicted: 0, expired: 0, mine: 0, probesReceived: 0) }
        func takeMine() throws -> UInt32 { 0 }
        func takeUploadable() -> [MeshUpload] { [] }
        func uploadAll(transport: Transport, authToken: String) throws -> UInt32 { 0 }
        func checkServerKey(transport: Transport, authToken: String) -> MeshKeyCheck? { nil }
        func onlineFrame() -> Data { Data([8, 0]) }
        func setRelayOnline(online: Bool) {}
        func fetchNeighbours() -> [UInt64] { [] }
        func fetchLinkDown(link: UInt64) {}
        func fetchFrameFor(link: UInt64) throws -> Data? { nil }
        func fetchReset() {}
        func takeFetchJobs() -> [MeshFetchJob] { [] }
        func relayFetch(transport: Transport, request: Data) -> Data { Data([7, 0]) }
        func uploadDone(id: Data) {}
        func uploadFailed(id: Data) {}
    }

    func testThreePhonesExchangeWhatIsNeededThenGoQuietAndEveryPacketArrivesOnce() {
        let clock = Clock()
        let engines = [LoopEngine(), LoopEngine(), LoopEngine()]
        var bus: [(to: Int, link: UInt64, bytes: Data)] = []
        var framesSent = 0
        var drivers: [MeshDriver] = []
        // Link ids are the other phone's index + 1, on each side.
        for index in 0..<3 {
            drivers.append(MeshDriver(engine: engines[index], scheduler: FakeScheduler(), now: { clock.now }, transmit: { link, bytes in
                framesSent += 1
                bus.append((to: Int(link) - 1, link: UInt64(index + 1), bytes: bytes))
            }))
        }
        func settle(_ limit: Int = 5_000) {
            var steps = 0
            while !bus.isEmpty {
                steps += 1
                XCTAssertLessThan(steps, limit, "the phones must go quiet: this is a storm")
                if steps >= limit { bus = []; return }
                let next = bus.removeFirst()
                drivers[next.to].receive(next.bytes, on: next.link)
            }
        }
        // Everyone is in range of everyone (a triangle).
        engines[0].have = [1, 2]
        engines[0].version = 1
        for (a, b) in [(0, 1), (1, 2), (0, 2)] {
            drivers[a].linkUp(UInt64(b + 1))
            drivers[b].linkUp(UInt64(a + 1))
        }
        settle()
        XCTAssertEqual(engines.map(\.have), [[1, 2], [1, 2], [1, 2]], "every packet reached every phone")
        framesSent = 0
        // A minute passes with nothing happening except the app's own wakes (the ones that re-announce, debounced).
        for second in 1...60 {
            clock.now.addTimeInterval(1)
            if second % 15 == 0 { for driver in drivers { driver.wake(reason: "app-active") } }
            settle()
        }
        XCTAssertLessThanOrEqual(framesSent, 6 * 2, "after the exchange the system is quiet: at most the occasional Hello per link after 30 s (and nobody answers it), not thousands: \(framesSent)")
        // A packet queued on the third phone reaches the others, once each, and then quiet again.
        engines[2].have.insert(9)
        engines[2].version += 1
        drivers[2].packetQueued()
        settle()
        XCTAssertEqual(engines.map(\.have), [[1, 2, 9], [1, 2, 9], [1, 2, 9]])
        framesSent = 0
        for _ in 1...60 { clock.now.addTimeInterval(1); settle() }
        XCTAssertEqual(framesSent, 0, "idle: no frames at all")
    }

    func testAShortLinkIdIsFourCharactersAndRevealsLittle() {
        XCTAssertEqual(MeshDriver.short(0xABCDEF0123456789), "6789")
        XCTAssertEqual(MeshDriver.short(0x5).count, 1)
    }
}
