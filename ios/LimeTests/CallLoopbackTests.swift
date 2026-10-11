import UIKit
import XCTest
@testable import Lime

/// Two call managers joined by an in-memory "mailbox" that, like the real one, delivers each op separately and not necessarily in
/// the order sent. The media is a fake that "connects" once both ends hold both descriptions (two real WebRTC engines cannot share
/// one simulator process: the audio unit times out).
@MainActor
private final class Wire {
    var local: [ObjectIdentifier: PairMedia] = [:]
}

@MainActor
private final class PairMedia: CallMedia {
    var onCandidate: ((String, String?, Int32) -> Void)?
    var onConnection: ((Bool) -> Void)?
    let localView = UIView(), remoteView = UIView()
    var haveLocal = false, haveRemote = false, closed = false
    var candidates: [String] = []
    var connectsWhenReady = true

    func start(servers: [IceServer], video: Bool) throws {}
    func makeOffer() async throws -> String { describe("AA:BB") }
    func accept(offer: String) async throws -> String { haveRemote = true; return describe("CC:DD") }
    func apply(answer: String) async throws { haveRemote = true; maybeConnect() }
    func add(candidate: String, mid: String?, index: Int32) async { candidates.append(candidate) }
    func setMuted(_ on: Bool) {}
    func setVideo(_ on: Bool) {}
    func flipCamera() {}
    func setSpeaker(_ on: Bool) {}
    func activateAudioFallback(video: Bool) -> Bool { false }
    func close() { closed = true }

    private func describe(_ fingerprint: String) -> String {
        haveLocal = true
        // The engine finds its candidates the moment a description is set, before the op carrying it has gone out.
        for i in 0..<30 { onCandidate?("candidate:\(i) 1 udp 1 10.0.0.\(i) 1 typ host", "0", 0) }
        return "v=0\r\na=fingerprint:sha-256 \(fingerprint)\r\n"
    }

    /// Candidates found after the description went out.
    func emitLate(_ count: Int) { for i in 0..<count { onCandidate?("candidate:L\(i) 1 udp 1 10.9.0.\(i) 1 typ relay", "0", 0) } }

    func maybeConnect() { if connectsWhenReady && haveLocal && haveRemote { onConnection?(true) } }
}

@MainActor
private final class Mailbox: CallSignalling {
    weak var other: CallManager?
    let me: String, myName: String
    var delay: (String) -> Duration = { _ in .milliseconds(5) }
    var sent: [String] = []
    var hang = false
    init(me: String, myName: String) { self.me = me; self.myName = myName }

    func send(peer: String, op: String, payload: [String: Any]) async -> Bool {
        sent.append(op)
        if hang { try? await Task.sleep(for: .seconds(60)); return false }
        let event = CallEventInfo(op: op, callID: payload["call_id"] as? String ?? "", peerID: me, peerName: myName, payload: payload)
        let target = other, wait = delay(op)
        Task { @MainActor in
            try? await Task.sleep(for: wait)
            await target?.handle(event)
        }
        return true
    }

    func iceServers() async -> [IceServer] { [] }
}

@MainActor
final class CallLoopbackTests: XCTestCase {
    private var mediaA = PairMedia(), mediaB = PairMedia()
    private var boxA = Mailbox(me: "alice", myName: "Alice"), boxB = Mailbox(me: "bob", myName: "Bob")

    private func pair() -> (CallManager, CallManager) {
        let defaults = { UserDefaults(suiteName: "lime.test.loop.\(UUID().uuidString)")! }
        let a = CallManager(signalling: boxA, system: QuietCallSystem(), log: CallLog(defaults: defaults()), makeMedia: { [unowned self] in mediaA })
        let b = CallManager(signalling: boxB, system: QuietCallSystem(), log: CallLog(defaults: defaults()), makeMedia: { [unowned self] in mediaB })
        boxA.other = b; boxB.other = a
        // Each answer's connection needs the other's description: connect both once both have them.
        return (a, b)
    }

    private func wait(_ seconds: Double = 5, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func connect(_ a: CallManager, _ b: CallManager) async {
        _ = await a.start(peerID: "bob", name: "Bob", video: false)
        await wait { b.phase == .incoming }
        await b.accept()
        await wait { a.phase != .outgoing }
        mediaB.maybeConnect()
        await wait { a.phase == .active && b.phase == .active }
    }

    func testCallConnectsAndEitherSideEndsCleanly() async {
        for callerEnds in [true, false] {
            mediaA = PairMedia(); mediaB = PairMedia(); boxA = Mailbox(me: "alice", myName: "Alice"); boxB = Mailbox(me: "bob", myName: "Bob")
            let (a, b) = pair()
            await connect(a, b)
            XCTAssertEqual(a.phase, .active)
            XCTAssertEqual(b.phase, .active)
            if callerEnds { await a.end() } else { await b.end() }
            await wait { a.phase == .idle && b.phase == .idle }
            XCTAssertEqual(a.phase, .idle)
            XCTAssertEqual(b.phase, .idle)
            XCTAssertTrue(mediaA.closed && mediaB.closed)
        }
    }

    func testAThirtyCandidateCallIsOnlyAFewOps() async {
        let (a, b) = pair()
        await connect(a, b)
        // The candidates were gathered before the description went out, so they travel inside it: one op each way.
        XCTAssertEqual(boxA.sent, ["call.offer"])
        XCTAssertEqual(boxB.sent, ["call.answer"])
        // Ones found later go together, in one op, at most once a second.
        mediaA.emitLate(12)
        await wait(3) { self.boxA.sent.count == 2 }
        XCTAssertEqual(boxA.sent, ["call.offer", "call.ice"])
        await a.end()
    }

    func testBatchedLateCandidatesReachTheOtherSide() async {
        let (a, b) = pair()
        await connect(a, b)
        mediaA.emitLate(5)
        await wait(4) { self.mediaB.candidates.count >= 5 }
        XCTAssertEqual(mediaB.candidates.count, 5)
        await b.end()
    }

    func testCandidatesThatArriveBeforeTheirOfferAreKept() async {
        boxA.delay = { $0 == "call.offer" ? .milliseconds(200) : .milliseconds(1) } // the offer is slow; anything else is fast
        let (a, b) = pair()
        // The caller holds its candidates back, so deliver two early ones by hand, as a reordering mailbox could.
        let early = CallEventInfo(op: "call.ice", callID: "c9", peerID: "alice", peerName: "Alice", payload: ["call_id": "c9", "candidate": "candidate:7 1 udp 1 10.0.0.9 9 typ host"])
        await b.handle(early)
        XCTAssertEqual(b.phase, .idle)
        await b.handle(CallEventInfo(op: "call.offer", callID: "c9", peerID: "alice", peerName: "Alice", payload: ["sdp": "v=0\r\na=fingerprint:sha-256 AA:BB\r\n"]))
        await b.accept()
        XCTAssertTrue(mediaB.candidates.contains { $0.contains("10.0.0.9") }, "an early candidate was dropped")
        _ = a
    }

    func testRingingEndedByEitherSide() async {
        for callerEnds in [true, false] {
            mediaA = PairMedia(); mediaB = PairMedia(); boxA = Mailbox(me: "alice", myName: "Alice"); boxB = Mailbox(me: "bob", myName: "Bob")
            let (a, b) = pair()
            _ = await a.start(peerID: "bob", name: "Bob", video: false)
            await wait { b.phase == .incoming }
            if callerEnds { await a.end(); await a.end() } else { await b.end(); await b.decline() }
            await wait { a.phase == .idle && b.phase == .idle }
            XCTAssertEqual(a.phase, .idle)
            XCTAssertEqual(b.phase, .idle)
        }
    }

    func testEndWhileConnectingFromEitherSide() async {
        for callerEnds in [true, false] {
            mediaA = PairMedia(); mediaB = PairMedia(); mediaA.connectsWhenReady = false; mediaB.connectsWhenReady = false
            boxA = Mailbox(me: "alice", myName: "Alice"); boxB = Mailbox(me: "bob", myName: "Bob")
            let (a, b) = pair()
            _ = await a.start(peerID: "bob", name: "Bob", video: false)
            await wait { b.phase == .incoming }
            await b.accept()
            await wait { a.phase != .outgoing }
            if callerEnds { await a.end() } else { await b.end() }
            await wait { a.phase == .idle && b.phase == .idle }
            XCTAssertEqual(a.phase, .idle)
            XCTAssertEqual(b.phase, .idle)
        }
    }

    func testConnectTimeoutFailsTheCallAndTearsDown() async {
        mediaA.connectsWhenReady = false; mediaB.connectsWhenReady = false
        let (a, b) = pair()
        a.connectSeconds = 0.3; b.connectSeconds = 0.3
        _ = await a.start(peerID: "bob", name: "Bob", video: false)
        await wait { b.phase == .incoming }
        await b.accept()
        await wait { a.phase == .idle && b.phase == .idle }
        XCTAssertEqual(a.phase, .idle)
        XCTAssertEqual(b.phase, .idle)
        XCTAssertEqual(b.phase == .idle ? "ok" : "no", "ok")
        XCTAssertTrue(mediaA.closed && mediaB.closed)
    }

    func testRingingPollsTheMailboxOnceASecond() async {
        let (a, _) = pair()
        var fetches = 0
        a.fetchNow = { fetches += 1 }
        _ = await a.start(peerID: "bob", name: "Bob", video: false)
        try? await Task.sleep(for: .seconds(2.3))
        XCTAssertGreaterThanOrEqual(fetches, 2)
        await a.end()
        let after = fetches
        try? await Task.sleep(for: .seconds(1.2))
        XCTAssertEqual(fetches, after, "polling should stop with the call")
    }

    // MARK: A system report that never returns must not jam the queue (LIME-111-fix3b)

    private final class StuckSystem: CallSystem {
        var onAnswer: ((String) -> Void)?
        var onEnd: ((String) -> Void)?
        var onMute: ((String, Bool) -> Void)?
        var delay: Duration? // nil = never completes
        var audioActive: Bool { true }
        func reportIncoming(callID: String, name: String, video: Bool, completion: @escaping @MainActor (String?) -> Void) {
            guard let delay else { return }
            Task { @MainActor in try? await Task.sleep(for: delay); completion(nil) }
        }
        func reportOutgoing(callID: String, name: String, video: Bool) {}
        func reportConnected(callID: String) {}
        func reportEnded(callID: String, answeredOrOutgoing: Bool) {}
    }

    private func stuckPair(delay: Duration?) -> (CallManager, CallManager) {
        let defaults = { UserDefaults(suiteName: "lime.test.loop.\(UUID().uuidString)")! }
        let sysA = StuckSystem(), sysB = StuckSystem()
        sysA.delay = delay; sysB.delay = delay
        let a = CallManager(signalling: boxA, system: sysA, log: CallLog(defaults: defaults()), makeMedia: { [unowned self] in mediaA })
        let b = CallManager(signalling: boxB, system: sysB, log: CallLog(defaults: defaults()), makeMedia: { [unowned self] in mediaB })
        boxA.other = b; boxB.other = a
        return (a, b)
    }

    func testThreeCallsInOneSessionWhenTheSystemNeverAnswersTheReport() async {
        for delay in [nil, Duration.seconds(5)] {
            mediaA = PairMedia(); mediaB = PairMedia(); boxA = Mailbox(me: "alice", myName: "Alice"); boxB = Mailbox(me: "bob", myName: "Bob")
            let (a, b) = stuckPair(delay: delay)
            // Shem → Jean, Jean → Shem, Shem → Jean, in one session: no restarts, every op handled.
            for (caller, callee, to) in [(a, b, "bob"), (b, a, "alice"), (a, b, "bob")] {
                mediaA = PairMedia(); mediaB = PairMedia()
                _ = await caller.start(peerID: to, name: "Peer", video: false)
                await wait { callee.phase == .incoming }
                XCTAssertEqual(callee.phase, .incoming, "the offer was handled")
                await callee.accept()
                await wait { caller.phase != .outgoing }
                XCTAssertNotEqual(caller.phase, .outgoing, "the answer was handled")
                (caller === a ? mediaA : mediaB).maybeConnect()
                (callee === a ? mediaA : mediaB).maybeConnect()
                await wait { caller.phase == .active && callee.phase == .active }
                await callee.end()
                await wait { caller.phase == .idle && callee.phase == .idle }
                XCTAssertEqual(caller.phase, .idle, "the end was handled")
                XCTAssertEqual(callee.phase, .idle)
            }
        }
    }

    func testAHandlerThatNeverReturnsIsSkippedAfterTheWatchdog() async {
        let (a, b) = pair()
        a.handlerSeconds = 0.2; b.handlerSeconds = 0.2
        // B is on a call; A's second offer makes B send "busy"; that send never returns.
        await connect(a, b)
        boxB.hang = true
        await b.handle([CallEventInfo(op: "call.offer", callID: "other", peerID: "carol", peerName: "Carol", payload: ["sdp": "v=0"]),
                        CallEventInfo(op: "call.end", callID: a.currentID, peerID: "alice", peerName: "Alice", payload: [:])])
        XCTAssertEqual(b.phase, .idle, "the end behind the stuck handler was still handled")
    }
}
