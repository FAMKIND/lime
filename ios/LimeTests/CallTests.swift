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
    var audioActive = false
    func reportIncoming(callID: String, name: String, video: Bool, completion: @escaping @MainActor (String?) -> Void) {
        incoming += 1
        completion(refuse ? "refused" : nil)
    }
    func reportOutgoing(callID: String, name: String, video: Bool) {}
    func requestAnswer(callID: String) { answerRequests += 1 }
    var answerRequests = 0
    func reportConnected(callID: String) {}
    func reportEnded(callID: String, answeredOrOutgoing: Bool) {}
}

@MainActor
private final class FakeMedia: CallMedia {
    var onCandidate: ((String, String?, Int32) -> Void)?
    var onConnection: ((Bool) -> Void)?
    var onRemoteVideo: ((Bool) -> Void)?
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
    var fallbacks = 0
    func activateAudioFallback(video: Bool) -> Bool { fallbacks += 1; return true }
    func close() { closed = true }
}

@MainActor
private final class FakeSounds: CallSounds {
    var log: [String] = []
    func startRingback(video: Bool) { log.append("ringback on") }
    func stopRingback() { log.append("ringback off") }
    func playConnect() { log.append("connect") }
    func playEnd() { log.append("end") }
}

@MainActor
private final class FakeSource: FrameSource {
    var renderers: [ObjectIdentifier] = []
    func add(renderer: AnyObject) { renderers.append(ObjectIdentifier(renderer)) }
    func remove(renderer: AnyObject) { renderers.removeAll { $0 == ObjectIdentifier(renderer) } }
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
        XCTAssertFalse(done(0.2, true, true, false), "'complete' with no relay candidate (a callee's answer once left like that): keep waiting")
        XCTAssertTrue(done(0.2, true, true, true), "complete with a relay")
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

    func testLimeActivatesTheAudioWhenCallKitStaysSilentAndNotWhenItDoesNot() async {
        for silent in [true, false] {
            system.audioActive = !silent
            media = FakeMedia()
            let m = manager()
            m.audioFallbackSeconds = 0.1
            await m.handle(event("call.offer", payload: ["sdp": "v=0"]))
            await m.accept()
            try? await Task.sleep(for: .seconds(0.4))
            XCTAssertEqual(media.fallbacks, silent ? 1 : 0, silent ? "CallKit silent: lime activates" : "CallKit activated: lime leaves it")
            await m.end()
            XCTAssertTrue(media.closed, "the media (and with it a fallback-activated session) is torn down on end")
            system = FakeSystem()
        }
    }

    private var sounds = FakeSounds()

    private func soundManager() -> CallManager {
        let m = CallManager(signalling: signalling, system: system, log: log, sounds: sounds, makeMedia: { [unowned self] in media })
        m.ringSeconds = 0.4
        return m
    }

    func testStatusSequenceCallingRingingConnectingTimer() async {
        let m = soundManager()
        _ = await m.start(peerID: "jean", name: "Jean", video: false)
        XCTAssertEqual(m.statusText(), "Calling…")
        await m.handle(event("call.ringing", id: m.currentID))
        XCTAssertEqual(m.statusText(), "Ringing…")
        await m.handle(event("call.answer", id: m.currentID, payload: ["sdp": "x"]))
        XCTAssertEqual(m.statusText(), "Connecting…")
        media.onConnection?(true)
        XCTAssertTrue(m.statusText(at: Date().addingTimeInterval(72)).hasPrefix("1:1"), "the timer counts up (0:00 at the start)")
        XCTAssertEqual(CallRecord.clock(42), "0:42")
    }

    func testTheUnreachableHintAppearsAfterTenSecondsWithoutRingingAndNotWithIt() async {
        let m = soundManager()
        m.hintSeconds = 0.15
        _ = await m.start(peerID: "jean", name: "Jean", video: false)
        try? await Task.sleep(for: .seconds(0.3))
        XCTAssertTrue(m.showUnreachableHint)
        await m.end()
        let n = soundManager()
        n.hintSeconds = 0.15
        _ = await n.start(peerID: "jean", name: "Jean", video: false)
        await n.handle(event("call.ringing", id: n.currentID))
        try? await Task.sleep(for: .seconds(0.3))
        XCTAssertFalse(n.showUnreachableHint, "ringing arrived: no hint")
        await n.end()
    }

    func testRingbackStartsWithTheOfferAndStopsOnEveryOutcome() async {
        // answered
        var m = soundManager()
        _ = await m.start(peerID: "jean", name: "Jean", video: false)
        XCTAssertEqual(sounds.log, ["ringback on"])
        await m.handle(event("call.answer", id: m.currentID, payload: ["sdp": "x"]))
        XCTAssertEqual(sounds.log, ["ringback on", "ringback off"])
        media.onConnection?(true)
        XCTAssertEqual(sounds.log.last, "connect")
        await m.end()
        XCTAssertEqual(sounds.log.last, "end")
        // declined, no answer, ended by me, busy, failed: the ringback always stops, and an end tone plays
        for outcome in ["call.decline", "call.busy", "call.end"] {
            sounds = FakeSounds(); media = FakeMedia()
            m = soundManager()
            _ = await m.start(peerID: "jean", name: "Jean", video: false)
            await m.handle(event(outcome, id: m.currentID))
            XCTAssertEqual(Array(sounds.log.prefix(2)), ["ringback on", "ringback off"], outcome)
            XCTAssertTrue(sounds.log.contains("end"), outcome)
        }
        sounds = FakeSounds(); media = FakeMedia()
        m = soundManager()
        _ = await m.start(peerID: "jean", name: "Jean", video: false)
        try? await Task.sleep(for: .seconds(0.7))
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(sounds.log.filter { $0 == "ringback off" }.count, 1, "no answer: stops")
        sounds = FakeSounds(); media = FakeMedia()
        m = soundManager()
        _ = await m.start(peerID: "jean", name: "Jean", video: false)
        await m.end()
        XCTAssertEqual(Array(sounds.log.prefix(3)), ["ringback on", "ringback off", "end"], "cancelled by me")
    }

    func testTheCalleeTellsTheCallerItIsRingingAndInAppAcceptAnswersTheSystemCall() async {
        let m = soundManager()
        await m.handle(event("call.offer", payload: ["sdp": "v=0"]))
        try? await Task.sleep(for: .seconds(0.1))
        XCTAssertEqual(signalling.sent.map(\.op), ["call.ringing"])
        await m.accept()
        XCTAssertEqual(system.answerRequests, 1, "lime's own Accept answers CallKit too, so CallKit activates the audio")
        await m.accept(fromSystem: true)
        XCTAssertEqual(system.answerRequests, 1)
    }

    func testTheRemotePictureShowsWhetherItArrivesBeforeTheViewOrAfter() {
        let rendererA = NSObject(), rendererB = NSObject()
        let source = FakeSource()
        // the track first, the view later
        var slot = RemoteVideoSlot()
        slot.setSource(source)
        XCTAssertTrue(source.renderers.isEmpty)
        slot.setRenderer(rendererA)
        XCTAssertEqual(source.renderers, [ObjectIdentifier(rendererA)])
        // the view first, the track later
        let late = FakeSource()
        slot = RemoteVideoSlot()
        slot.setRenderer(rendererB)
        slot.setSource(late)
        XCTAssertEqual(late.renderers, [ObjectIdentifier(rendererB)])
        // a new track (a renegotiation) replaces the old one on the same view
        let next = FakeSource()
        slot.setSource(next)
        XCTAssertTrue(late.renderers.isEmpty)
        XCTAssertEqual(next.renderers, [ObjectIdentifier(rendererB)])
        slot.clear()
        XCTAssertTrue(next.renderers.isEmpty)
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
