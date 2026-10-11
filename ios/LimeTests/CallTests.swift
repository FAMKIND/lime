import UIKit
import XCTest
@testable import Lime

@MainActor
private final class FakeSignalling: CallSignalling {
    var sent: [(peer: String, op: String)] = []
    func send(peer: String, op: String, payload: [String: Any]) async -> Bool { sent.append((peer, op)); return true }
    func iceServers() async -> [IceServer] { [] }
}

@MainActor
private final class FakeSystem: CallSystem {
    var onAnswer: ((String) -> Void)?
    var onEnd: ((String) -> Void)?
    var onMute: ((String, Bool) -> Void)?
    var refuse = false
    var incoming = 0
    func reportIncoming(callID: String, name: String, video: Bool, completion: @escaping @MainActor (String?) -> Void) {
        incoming += 1
        completion(refuse ? "refused" : nil)
    }
    func reportOutgoing(callID: String, name: String, video: Bool) {}
    func reportConnected(callID: String) {}
    func reportEnded(callID: String, answeredOrOutgoing: Bool) {}
}

@MainActor
private final class FakeMedia: CallMedia {
    var onCandidate: ((String, String?, Int32) -> Void)?
    var onConnection: ((Bool) -> Void)?
    let localView = UIView()
    let remoteView = UIView()
    var muted = false
    var closed = false
    func start(servers: [IceServer], video: Bool) throws {}
    func makeOffer() async throws -> String { "v=0\r\na=fingerprint:sha-256 AA:BB\r\n" }
    func accept(offer: String) async throws -> String { "v=0\r\na=fingerprint:sha-256 CC:DD\r\n" }
    func apply(answer: String) async throws {}
    func add(candidate: String, mid: String?, index: Int32) async {}
    func setMuted(_ on: Bool) { muted = on }
    func setVideo(_ on: Bool) {}
    func flipCamera() {}
    func setSpeaker(_ on: Bool) {}
    func close() { closed = true }
}

@MainActor
final class CallTests: XCTestCase {
    private var signalling = FakeSignalling()
    private var system = FakeSystem()
    private var media = FakeMedia()
    private var log = CallLog(defaults: UserDefaults(suiteName: "lime.test.calls.\(UUID().uuidString)")!)
    private var quiet = false

    private func manager() -> CallManager {
        let m = CallManager(signalling: signalling, system: system, log: log, isQuiet: { [unowned self] in quiet }, makeMedia: { [unowned self] in media })
        m.ringSeconds = 0.2
        return m
    }

    private func event(_ op: String, id: String = "c1", payload: [String: Any] = [:]) -> CallEventInfo {
        CallEventInfo(op: op, callID: id, peerID: "jean", peerName: "Jean", payload: payload)
    }

    func testOutgoingCallRingsThenConnectsAndLogsDuration() async {
        let m = manager()
        let started = await m.start(peerID: "jean", name: "Jean", video: false)
        XCTAssertTrue(started)
        XCTAssertEqual(m.phase, .outgoing)
        XCTAssertEqual(signalling.sent.map(\.op), ["call.offer"])
        await m.handle(event("call.answer", id: m.currentID, payload: ["sdp": "x"]))
        XCTAssertEqual(m.phase, .connecting)
        media.onConnection?(true)
        XCTAssertEqual(m.phase, .active)
        await m.end()
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(log.records.first?.outcome, .completed)
        XCTAssertTrue(signalling.sent.map(\.op).contains("call.end"))
        XCTAssertTrue(media.closed)
    }

    func testUnansweredOutgoingCallIsNoAnswer() async {
        let m = manager()
        _ = await m.start(peerID: "jean", name: "Jean", video: true)
        try? await Task.sleep(for: .seconds(0.5))
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(log.records.first?.outcome, .noAnswer)
        XCTAssertEqual(log.records.first?.line, "No answer")
    }

    func testIncomingCallAcceptedSendsAnswer() async {
        let m = manager()
        await m.handle(event("call.offer", payload: ["sdp": "v=0", "video": false]))
        XCTAssertEqual(m.phase, .incoming)
        XCTAssertEqual(system.incoming, 1)
        await m.accept()
        XCTAssertEqual(signalling.sent.map(\.op), ["call.answer"])
        XCTAssertEqual(m.phase, .connecting)
    }

    func testIncomingDeclinedAndMissed() async {
        let m = manager()
        await m.handle(event("call.offer", payload: ["sdp": "v=0"]))
        await m.decline()
        XCTAssertEqual(log.records.first?.outcome, .declined)
        XCTAssertEqual(signalling.sent.map(\.op), ["call.decline"])
        await m.handle(event("call.offer", id: "c2", payload: ["sdp": "v=0", "video": true]))
        try? await Task.sleep(for: .seconds(0.5))
        XCTAssertEqual(log.records.first?.outcome, .missed)
        XCTAssertEqual(log.records.first?.line, "Missed video call")
    }

    func testQuietHoursMakeAMissedCallWithoutRinging() async {
        quiet = true
        let m = manager()
        await m.handle(event("call.offer", payload: ["sdp": "v=0"]))
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(system.incoming, 0)
        XCTAssertEqual(log.records.first?.line, "Missed call")
    }

    func testSecondCallerHearsBusy() async {
        let m = manager()
        await m.handle(event("call.offer", payload: ["sdp": "v=0"]))
        await m.handle(event("call.offer", id: "c2", payload: ["sdp": "v=0"]))
        XCTAssertEqual(signalling.sent.last?.op, "call.busy")
        XCTAssertEqual(m.phase, .incoming)
    }

    func testRemoteEndWhileRingingIsMissed() async {
        let m = manager()
        await m.handle(event("call.offer", payload: ["sdp": "v=0"]))
        await m.handle(event("call.end"))
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(log.records.first?.outcome, .missed)
    }

    func testGatheringStopsAtOneSecondOnceARelayIsIn() {
        let done = { (elapsed: Double, complete: Bool, configured: Bool, relay: Bool) in
            WebRTCMedia.gatheringDone(elapsed: elapsed, complete: complete, relayConfigured: configured, hasRelay: relay)
        }
        XCTAssertFalse(done(0.5, false, true, true), "too early")
        XCTAssertTrue(done(1.0, false, true, true), "a relay is in: 1 s is enough")
        XCTAssertFalse(done(1.5, false, true, false), "a relay is expected but not in yet: keep waiting")
        XCTAssertFalse(done(1.5, false, false, false), "no relay configured: wait for completion")
        XCTAssertTrue(done(2.5, false, true, false), "the cap")
        XCTAssertTrue(done(0.2, true, false, false), "complete")
    }

    func testTheRelayCredentialsAreAskedTwiceThenTheCallGoesOn() async {
        struct Down: Error {}
        var tries = 0
        let value: Int? = await Retry.once(after: .milliseconds(10)) { () async throws -> Int? in tries += 1; throw Down() }
        XCTAssertNil(value)
        XCTAssertEqual(tries, 2)
        tries = 0
        let second: Int? = await Retry.once(after: .milliseconds(10)) { () async throws -> Int? in tries += 1; if tries == 1 { throw Down() }; return 7 }
        XCTAssertEqual(second, 7)
        tries = 0
        let none: Int? = await Retry.once(after: .milliseconds(10)) { () async throws -> Int? in tries += 1; return nil }
        XCTAssertNil(none)
        XCTAssertEqual(tries, 1, "'not configured' is an answer, not an error")
    }

    func testCrossedCallsTheLowerUserIdsOfferWins() async {
        for (mine, wins) in [("a-low", true), ("z-high", false)] {
            let m = CallManager(signalling: signalling, system: system, log: log, myID: { mine }, makeMedia: { [unowned self] in media })
            _ = await m.start(peerID: "m-peer", name: "Peer", video: false)
            let mineID = m.currentID
            await m.handle(CallEventInfo(op: "call.offer", callID: "theirs", peerID: "m-peer", peerName: "Peer", payload: ["sdp": "v=0"]))
            if wins {
                XCTAssertEqual(m.phase, .outgoing, "my offer wins: still calling")
                XCTAssertEqual(m.currentID, mineID)
            } else {
                XCTAssertEqual(m.phase, .incoming, "their offer wins: I answer theirs")
                XCTAssertEqual(m.currentID, "theirs")
            }
            XCTAssertFalse(signalling.sent.map(\.op).contains("call.busy"), "crossed calls are not 'busy'")
            await m.end()
            signalling.sent = []
        }
    }

    func testFingerprintAndClock() {
        XCTAssertEqual(CallManager.fingerprint(in: "v=0\r\na=fingerprint:sha-256 ab:cd\r\n"), "AB:CD")
        XCTAssertEqual(CallRecord.clock(252), "4:12")
        XCTAssertEqual(CallRecord.clock(3725), "1:02:05")
    }

    func testChatRowsInterleaveCalls() {
        let conversation = Conversation(id: "jean", title: "Jean", members: [Person(id: "jean", name: "Jean")], messages: [])
        let call = CallRecord(id: "c", peerID: "jean", peerName: "Jean", video: false, outgoing: true, date: Date(), duration: 252, outcome: .completed)
        let rows = ChatRow.rows(for: conversation, calls: [call])
        XCTAssertTrue(rows.contains { if case .call(let r) = $0.kind { return r.line == "Voice call · 4:12" } else { return false } })
    }
}
