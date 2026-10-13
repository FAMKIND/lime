import UIKit
import XCTest
@testable import Lime

@MainActor
private final class FakeSignalling: CallSignalling {
    var sent: [(peer: String, op: String)] = []
    var servers: [IceServer] = []
    var payloads: [[String: Any]] = []
    func send(peer: String, op: String, payload: [String: Any]) async -> Bool { sent.append((peer, op)); payloads.append(payload); return true }
    func iceServers() async -> [IceServer] { servers }
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
    var onControl: ((String) -> Void)?
    var onControlOpen: (() -> Void)?
    var onCameraInterrupted: ((Bool) -> Void)?
    let localView = UIView()
    let remoteView = UIView()
    var muted = false
    var closed = false
    var hasLocalVideo = false
    var sentControl: [[String: Any]] = []
    var controlUp = true
    var videoEnabled = true
    func sendControl(_ json: String) -> Bool {
        guard controlUp, let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return false }
        sentControl.append(object)
        return true
    }
    func addLocalVideo() throws { hasLocalVideo = true }
    func renegotiationOffer() async throws -> String { "v=0\r\na=fingerprint:sha-256 AA:BB\r\n" }
    var relayOnly: Bool?
    func start(servers: [IceServer], video: Bool, relayOnly: Bool) throws { hasLocalVideo = video; self.relayOnly = relayOnly }
    func makeOffer() async throws -> String { "v=0\r\na=fingerprint:sha-256 AA:BB\r\n" }
    func accept(offer: String) async throws -> String { "v=0\r\na=fingerprint:sha-256 CC:DD\r\n" }
    func apply(answer: String) async throws {}
    func add(candidate: String, mid: String?, index: Int32) async {}
    func setMuted(_ on: Bool) { muted = on }
    func setVideo(_ on: Bool) { videoEnabled = on }
    func flipCamera() {}
    func setSpeaker(_ on: Bool) {}
    var fallbacks = 0
    func activateAudioFallback(video: Bool) -> Bool { fallbacks += 1; return true }
    func close() { closed = true }
}

@MainActor
private final class FakePiP: CallPiP {
    var isPossible = true
    var onStarted: (() -> Void)?
    var onStopped: (() -> Void)?
    var onRestore: (() -> Void)?
    var onFailed: (() -> Void)?
    var prepared = 0, started = 0, stopped = 0
    /// What the window would show: their photo (the camera is off) or the video.
    private(set) var showsAvatar = false
    private(set) var person: Person?
    func prepare(sourceView: UIView, person: Person) { prepared += 1; self.person = person }
    func setRemoteCameraOff(_ off: Bool) { showsAvatar = off }
    func start() { started += 1 }
    func stop() { stopped += 1 }
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
    private var quietWhy: CallQuietReason = .dnd
    private var relay = false
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func manager() -> CallManager {
        let m = CallManager(signalling: signalling, system: system, log: log, now: { [unowned self] in clock },
                            quietReason: { [unowned self] in quiet ? quietWhy : nil }, makeMedia: { [unowned self] in media })
        m.ringSeconds = 0.2
        m.unavailableSeconds = 0.05
        m.alwaysRelay = { [unowned self] in relay }
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
        XCTAssertEqual(log.records.first?.outcome, .missedDnd)
    }

    // MARK: LIME-128: Do Not Disturb and work hours, openly

    func testASilencedOfferTellsTheCallerWhyAndIsLabelled() async {
        quiet = true
        let m = manager()
        await m.handle(event("call.offer", payload: ["sdp": "v=0"]))
        XCTAssertEqual(signalling.sent.map(\.op), ["call.unavailable"])
        XCTAssertEqual(signalling.sent.first?.peer, "jean")
        XCTAssertEqual(signalling.payloads.first?["reason"] as? String, "dnd")
        XCTAssertEqual(signalling.payloads.first?["call_id"] as? String, "c1")
        XCTAssertEqual(log.records.first?.outcome.silencedNote, "Silenced \u{00B7} Do Not Disturb")
        XCTAssertTrue(log.records.first?.isMissedIncoming ?? false, "still a missed incoming call: red, in the Missed filter")
        XCTAssertEqual(log.missedUnseen, 1, "and the badge counts it")

        quietWhy = .workHours
        clock = clock.addingTimeInterval(600)
        await m.handle(event("call.offer", id: "c2", payload: ["sdp": "v=0"]))
        XCTAssertEqual(signalling.payloads.last?["reason"] as? String, "work_hours")
        XCTAssertEqual(log.records.first?.outcome, .missedHours)
        XCTAssertEqual(log.records.first?.outcome.silencedNote, "Silenced \u{00B7} Work hours")
    }

    func testTheCallerSeesWhyForAMomentThenTheCallEndsAsUnavailable() async {
        let m = manager()
        _ = await m.start(peerID: "jean", name: "Jean", video: false)
        await m.handle(event("call.unavailable", id: m.currentID, payload: ["reason": "dnd"]))
        XCTAssertEqual(m.phase, .outgoing, "the call screen stays for a moment")
        XCTAssertEqual(m.statusText(), "Jean has Do Not Disturb on")
        try? await Task.sleep(for: .seconds(0.3))
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(log.records.first?.outcome, .unavailable)
        XCTAssertEqual(log.records.first?.line, "Unavailable")
        XCTAssertFalse(log.records.first?.isMissedIncoming ?? true, "my own call: not a missed call")
        XCTAssertEqual(log.missedUnseen, 0)

        _ = await m.start(peerID: "jean", name: "Jean", video: false)
        await m.handle(event("call.unavailable", id: m.currentID, payload: ["reason": "work_hours"]))
        XCTAssertEqual(m.statusText(), "Jean is outside work hours")
        await m.end()
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(log.records.first?.outcome, .unavailable, "hanging up during the message is still unavailable")
    }

    func testAnUnavailableForAnotherCallIsIgnored() async {
        let m = manager()
        _ = await m.start(peerID: "jean", name: "Jean", video: false)
        await m.handle(event("call.unavailable", id: "someone-elses", payload: ["reason": "dnd"]))
        XCTAssertEqual(m.statusText(), "Calling…")
    }

    func testASecondCallWithinThreeMinutesRingsDespiteDoNotDisturb() async {
        quiet = true
        let m = manager()
        await m.handle(event("call.offer", id: "c1", payload: ["sdp": "v=0"]))
        XCTAssertEqual(m.phase, .idle)
        // A different caller is still silenced.
        await m.handle(CallEventInfo(op: "call.offer", callID: "x1", peerID: "sam", peerName: "Sam", payload: ["sdp": "v=0"]))
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(system.incoming, 0)
        // Jean again, two minutes later: it rings.
        clock = clock.addingTimeInterval(120)
        await m.handle(event("call.offer", id: "c2", payload: ["sdp": "v=0"]))
        XCTAssertEqual(m.phase, .incoming)
        XCTAssertEqual(system.incoming, 1)
        XCTAssertEqual(signalling.sent.filter { $0.op == "call.unavailable" }.count, 2, "the repeated call was not turned away")
    }

    func testACallAfterThreeMinutesIsSilencedAgain() async {
        quiet = true
        let m = manager()
        await m.handle(event("call.offer", id: "c1", payload: ["sdp": "v=0"]))
        clock = clock.addingTimeInterval(181)
        await m.handle(event("call.offer", id: "c2", payload: ["sdp": "v=0"]))
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(system.incoming, 0)
        XCTAssertEqual(log.records.count, 2)
    }

    func testTheMissedFilterCountsSilencedCallsAndNotUnavailable() {
        let silenced = CallRecord(id: "a", peerID: "jean", peerName: "Jean", video: false, outgoing: false, date: clock, duration: 0, outcome: .missedDnd)
        let hours = CallRecord(id: "b", peerID: "jean", peerName: "Jean", video: false, outgoing: false, date: clock, duration: 0, outcome: .missedHours)
        let unavailable = CallRecord(id: "c", peerID: "jean", peerName: "Jean", video: false, outgoing: true, date: clock, duration: 0, outcome: .unavailable)
        XCTAssertTrue(silenced.isMissedIncoming && hours.isMissedIncoming)
        XCTAssertFalse(unavailable.isMissedIncoming)
        XCTAssertEqual(CallOutcome(rawValue: "missed_dnd"), .missedDnd, "stored as missed_dnd, and older records stay missed")
        XCTAssertEqual(CallOutcome(rawValue: "missed"), .missed)
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

    // MARK: LIME-118b: the control channel

    /// A call that is up: I called, they answered with a media key (`CC:DD`), the path came up.
    private func connectedCall(video: Bool = false) async -> CallManager {
        let m = manager()
        _ = await m.start(peerID: "jean", name: "Jean", video: video)
        await m.handle(event("call.answer", id: m.currentID, payload: ["sdp": "v=0\r\na=fingerprint:sha-256 CC:DD\r\n"]))
        media.onConnection?(true)
        XCTAssertEqual(m.phase, .active)
        return m
    }

    private func state(_ muted: Bool, _ camera: Bool) -> String { "{\"t\":\"state\",\"muted\":\(muted),\"camera\":\(camera)}" }

    func testTheOtherSidesMuteAndCameraStateArrivesOverTheControlChannel() async {
        let m = await connectedCall(video: true)
        XCTAssertFalse(m.remoteMuted)
        XCTAssertTrue(m.remoteCameraOn)
        await m.handleControl(state(true, false))
        XCTAssertTrue(m.remoteMuted)
        XCTAssertFalse(m.remoteCameraOn)
        XCTAssertFalse(m.remoteVideoShowing, "their camera is off: show their avatar, not a frozen or black picture")
        await m.handleControl(state(false, true))
        XCTAssertFalse(m.remoteMuted)
        XCTAssertTrue(m.remoteCameraOn)
    }

    func testUnknownOversizedAndMalformedControlMessagesAreIgnored() async {
        let m = await connectedCall()
        await m.handleControl("{\"t\":\"wave\",\"x\":1}")
        await m.handleControl("not json")
        await m.handleControl("{\"muted\":true}")
        await m.handleControl("{\"t\":\"state\",\"muted\":true,\"pad\":\"" + String(repeating: "x", count: 70_000) + "\"}")
        XCTAssertFalse(m.remoteMuted)
        XCTAssertEqual(m.phase, .active)
    }

    func testMyStateIsSentWhenTheChannelOpensAndOnEveryChange() async {
        let m = await connectedCall(video: true)
        media.onControlOpen?()
        XCTAssertEqual(media.sentControl.last?["t"] as? String, "state")
        XCTAssertEqual(media.sentControl.last?["muted"] as? Bool, false)
        XCTAssertEqual(media.sentControl.last?["camera"] as? Bool, true)
        m.setMuted(true)
        XCTAssertEqual(media.sentControl.last?["muted"] as? Bool, true)
        m.toggleCamera()
        XCTAssertEqual(media.sentControl.last?["camera"] as? Bool, false)
        XCTAssertFalse(media.videoEnabled)
    }

    func testAVoiceCallTurnsIntoVideoOverTheControlChannelAndStaysOneCall() async {
        let m = await connectedCall()
        XCTAssertFalse(m.video)
        await m.startVideo()
        XCTAssertTrue(m.video)
        XCTAssertTrue(media.hasLocalVideo)
        let offer = media.sentControl.first { $0["t"] as? String == "offer" }
        XCTAssertNotNil(offer)
        XCTAssertTrue((offer?["sdp"] as? String ?? "").contains("AA:BB"))
        // Their answer carries the same media key: applied. The call is still one call, recorded as a video call.
        await m.handleControl("{\"t\":\"answer\",\"sdp\":\"v=0\\r\\na=fingerprint:sha-256 CC:DD\\r\\n\"}")
        XCTAssertEqual(m.phase, .active)
        await m.end()
        XCTAssertEqual(log.records.count, 1)
        XCTAssertTrue(log.records.first?.video ?? false, "the kind when it ended")
        XCTAssertEqual(log.records.first?.outcome, .completed)
    }

    func testTheOtherSideAddingVideoIsAnsweredAndMyCameraStaysOff() async {
        let m = await connectedCall()
        await m.handleControl("{\"t\":\"offer\",\"sdp\":\"v=0\\r\\na=fingerprint:sha-256 CC:DD\\r\\n\"}")
        XCTAssertTrue(m.video, "the screen turns to video")
        XCTAssertFalse(m.cameraOn, "they see no picture of me until I choose to")
        XCTAssertFalse(media.hasLocalVideo)
        XCTAssertEqual(media.sentControl.first { $0["t"] as? String == "answer" } != nil, true)
        // "Turn on camera" adds mine and renegotiates.
        m.toggleCamera()
        try? await Task.sleep(for: .seconds(0.1))
        XCTAssertTrue(media.hasLocalVideo)
        XCTAssertTrue(media.sentControl.contains { $0["t"] as? String == "offer" })
    }

    func testAMidCallDescriptionWithAnotherMediaKeyEndsTheCall() async {
        let m = await connectedCall()
        await m.handleControl("{\"t\":\"offer\",\"sdp\":\"v=0\\r\\na=fingerprint:sha-256 EE:FF\\r\\n\"}")
        XCTAssertEqual(m.phase, .idle, "a swapped key tears the call down")
        XCTAssertEqual(log.records.first?.outcome, .failed)
        XCTAssertFalse(media.sentControl.contains { $0["t"] as? String == "answer" })

        let again = await connectedCall()
        await again.startVideo()
        await again.handleControl("{\"t\":\"answer\",\"sdp\":\"v=0\\r\\na=fingerprint:sha-256 99:99\\r\\n\"}")
        XCTAssertEqual(again.phase, .idle)
    }

    func testAnInterruptedCameraPausesMyPictureAndTellsTheOtherSide() async {
        let m = await connectedCall(video: true)
        media.onCameraInterrupted?(true)
        XCTAssertTrue(m.cameraPaused)
        XCTAssertFalse(media.videoEnabled)
        XCTAssertEqual(media.sentControl.last?["camera"] as? Bool, false)
        media.onCameraInterrupted?(false)
        XCTAssertFalse(m.cameraPaused)
        XCTAssertTrue(media.videoEnabled)
        XCTAssertEqual(media.sentControl.last?["camera"] as? Bool, true)
    }

    // MARK: LIME-118c: minimising

    private func videoCallWithPiP(_ pip: FakePiP) async -> CallManager {
        let m = await connectedCall(video: true)
        m.makePictureInPicture = { _ in pip }
        m.preparePictureInPicture(sourceView: UIView())
        return m
    }

    func testAVoiceCallMinimisesToTheSlimBarWithNoFloatingWindow() async {
        let m = await connectedCall()
        let pip = FakePiP()
        m.makePictureInPicture = { _ in pip }
        m.preparePictureInPicture(sourceView: UIView())
        XCTAssertEqual(pip.prepared, 0, "no Picture in Picture for a voice call")
        m.minimize()
        XCTAssertTrue(m.minimized)
        XCTAssertFalse(m.pictureInPictureActive)
        XCTAssertEqual(pip.started, 0)
    }

    func testAVideoCallMinimisesToSystemPictureInPictureAndTappingTheWindowRestoresIt() async {
        let pip = FakePiP()
        let m = await videoCallWithPiP(pip)
        XCTAssertEqual(pip.prepared, 1)
        m.minimize()
        XCTAssertEqual(pip.started, 1)
        XCTAssertFalse(m.minimized, "the full screen stays until the window is really up")
        pip.onStarted?()
        XCTAssertTrue(m.pictureInPictureActive && m.minimized, "the full screen goes, the window floats over lime")
        pip.onRestore?()
        XCTAssertFalse(m.minimized, "tapping the window brings the full call screen back")
        XCTAssertFalse(m.pictureInPictureActive)
    }

    func testClosingTheWindowLeavesTheCallGoingWithTheReturnBar() async {
        let pip = FakePiP()
        let m = await videoCallWithPiP(pip)
        m.minimize(); pip.onStarted?()
        pip.onStopped?()
        XCTAssertFalse(m.pictureInPictureActive)
        XCTAssertTrue(m.minimized, "the call goes on; the slim bar returns to it")
        XCTAssertEqual(m.phase, .active)
    }

    func testWhenThePictureInPictureWindowCannotStartTheCallMinimisesToTheBar() async {
        let pip = FakePiP()
        pip.isPossible = false
        let m = await videoCallWithPiP(pip)
        m.minimize()
        XCTAssertTrue(m.minimized)
        XCTAssertEqual(pip.started, 0)
        let failing = FakePiP()
        let again = await videoCallWithPiP(failing)
        again.minimize(); failing.onFailed?()
        XCTAssertTrue(again.minimized)
    }

    func testEndingTheCallClosesTheWindow() async {
        let pip = FakePiP()
        let m = await videoCallWithPiP(pip)
        m.minimize(); pip.onStarted?()
        await m.end()
        XCTAssertEqual(pip.stopped, 1)
        XCTAssertFalse(m.pictureInPictureActive)
    }

    func testMyCameraPausesWhenLimeLeavesTheFrontAndTheOtherSideIsToldThenItResumes() async {
        let m = await connectedCall(video: true)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(media.videoEnabled, "without the multitasking-camera entitlement the camera cannot run in the background")
        XCTAssertEqual(media.sentControl.last?["camera"] as? Bool, false)
        XCTAssertFalse(m.cameraPaused, "that is not the window notice")
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertTrue(media.videoEnabled)
        XCTAssertEqual(media.sentControl.last?["camera"] as? Bool, true)
    }

    // MARK: LIME-119: Always relay calls and the verification emoji

    private let relayServer = IceServer(urls: ["turn:turn.example.org:3478"], username: "u", credential: "c")

    func testAlwaysRelayMakesTheCallRelayOnlyAndOffLeavesItDirect() async {
        signalling.servers = [relayServer]
        relay = true
        let m = manager()
        _ = await m.start(peerID: "jean", name: "Jean", video: false)
        XCTAssertEqual(media.relayOnly, true, "only relay candidates are gathered and sent")
        XCTAssertEqual(signalling.sent.map(\.op), ["call.offer"])
        await m.end()

        relay = false
        media.relayOnly = nil
        _ = await m.start(peerID: "jean", name: "Jean", video: false)
        XCTAssertEqual(media.relayOnly, false)
    }

    func testTheCalleeAppliesItsOwnRelaySettingNotTheCallers() async {
        signalling.servers = [relayServer]
        relay = true   // mine; the caller's setting is its own
        let m = manager()
        await m.handle(event("call.offer", payload: ["sdp": "v=0\r\na=fingerprint:sha-256 AA:BB\r\n"]))
        await m.accept()
        XCTAssertEqual(media.relayOnly, true)
    }

    func testAlwaysRelayWithNoRelayCredentialsFailsClearlyAndNeverCallsDirectly() async {
        signalling.servers = [IceServer(urls: ["stun:turn.example.org:3478"], username: nil, credential: nil)]   // what the app falls back to
        relay = true
        let m = manager()
        let started = await m.start(peerID: "jean", name: "Jean", video: false)
        XCTAssertFalse(started)
        XCTAssertEqual(m.phase, .idle)
        XCTAssertEqual(m.notice, "Can\u{2019}t reach lime\u{2019}s relay. Turn off Always relay calls to call directly.")
        XCTAssertTrue(signalling.sent.isEmpty, "no offer, so no address is revealed")
        XCTAssertNil(media.relayOnly, "no direct attempt either")
        XCTAssertEqual(log.records.first?.outcome, .failed)
    }

    func testTheEmojiAppearOnceConnectedAndAreTheSameForBothSidesInputs() async {
        let m = await connectedCall()
        XCTAssertEqual(m.verificationEmoji.count, 4)
        // The caller's key (AA:BB, in the offer) and the callee's (CC:DD, in the answer): the same four the core gives for them.
        let expected = callEmoji(callId: m.currentID, fpCaller: "AA:BB", fpCallee: "CC:DD")
        XCTAssertEqual(m.verificationEmoji, expected)
        XCTAssertNotEqual(m.verificationEmoji, callEmoji(callId: m.currentID, fpCaller: "AA:BB", fpCallee: "EE:FF"), "another key, other emoji")
        // A voice -> video renegotiation keeps the same key, so the emoji do not change.
        let before = m.verificationEmoji
        await m.startVideo()
        XCTAssertEqual(m.verificationEmoji, before)
    }

    func testTheMinimisedWindowShowsTheirPhotoWhenTheirCameraIsOffAndTheVideoWhenItIsOn() async {
        let pip = FakePiP()
        let m = await videoCallWithPiP(pip)
        XCTAssertEqual(pip.person?.name, "Jean", "the photo is theirs")
        XCTAssertFalse(pip.showsAvatar, "their camera is on: the video")
        await m.handleControl(state(false, false))
        XCTAssertTrue(pip.showsAvatar, "their camera is off: their photo, never a black window")
        await m.handleControl(state(false, true))
        XCTAssertFalse(pip.showsAvatar, "and back to the video")
        // A window made while their camera is off starts on the photo.
        await m.handleControl(state(false, false))
        let late = FakePiP()
        m.makePictureInPicture = { _ in late }
        m.preparePictureInPicture(sourceView: UIView())
        XCTAssertTrue(late.showsAvatar || late.prepared == 0, "a new window starts on the photo")
    }

    /// The window's photo is plain UIKit: the system moves it into its own window, where a SwiftUI avatar that needs the app's
    /// environment (the status badge wants the `ConversationStore`) has none and traps (the crash minimising a video call).
    func testThePictureInPicturePhotoIsPlainUIKitThatDrawsWithoutTheAppEnvironment() {
        let view = PiPAvatarView(person: Person(id: "jean", name: "Jean Park"))
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 213)
        view.layoutIfNeeded()
        XCTAssertEqual(view.accessibilityLabel, "Jean Park, camera off")
        XCTAssertTrue(view.isAccessibilityElement)
        let circle = view.subviews.first
        XCTAssertEqual(circle?.frame.width ?? 0, 80, accuracy: 0.5, "half the window, centred")
        XCTAssertEqual(circle?.frame.midX ?? 0, 80, accuracy: 0.5)
        XCTAssertTrue(view.subviews.first?.subviews.contains { ($0 as? UILabel)?.text == "JP" } ?? false, "their initials when there is no photo")
    }
}
