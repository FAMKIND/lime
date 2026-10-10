import Foundation
import Observation

/// Where a call is.
enum CallPhase: Equatable, Sendable {
    case idle
    /// I called; waiting for them to answer.
    case outgoing
    /// They are calling; waiting for me.
    case incoming
    /// Answered; the media path is coming up.
    case connecting
    case active
}

/// What the call needs from the rest of the app: Lime's encrypted channel to the other phone, and the relay's credentials.
@MainActor
protocol CallSignalling: AnyObject {
    func send(peer: String, op: String, payload: [String: Any]) async -> Bool
    func iceServers() async -> [IceServer]
}

/// What the system's call screen (CallKit) does for a call.
@MainActor
protocol CallSystem: AnyObject {
    var onAnswer: ((String) -> Void)? { get set }
    var onEnd: ((String) -> Void)? { get set }
    var onMute: ((String, Bool) -> Void)? { get set }
    /// Tells the system about an incoming call; `false` if it refuses (Do Not Disturb or a Focus).
    func reportIncoming(callID: String, name: String, video: Bool) async -> Bool
    func reportOutgoing(callID: String, name: String, video: Bool)
    func reportConnected(callID: String)
    func reportEnded(callID: String, answeredOrOutgoing: Bool)
}

/// One call at a time between two accepted contacts (LIME-111). Signalling (offer, answer, ICE, end, busy, decline) rides Lime's
/// encrypted control ops; the media is WebRTC between the phones or through the TURN relay. The offer and answer carry the DTLS
/// fingerprint of the media key inside the signed op, so the relay cannot swap it.
@MainActor
@Observable
final class CallManager {
    private(set) var phase: CallPhase = .idle
    private(set) var peerID = ""
    private(set) var peerName = ""
    private(set) var video = false
    private(set) var outgoing = false
    private(set) var muted = false
    private(set) var speaker = false
    private(set) var cameraOn = true
    private(set) var startedAt: Date?
    var media: (any CallMedia)?

    @ObservationIgnored private let signalling: CallSignalling
    @ObservationIgnored private let system: CallSystem
    @ObservationIgnored private let makeMedia: () -> any CallMedia
    @ObservationIgnored private let log: CallLog
    @ObservationIgnored private let isQuiet: () -> Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var callID = ""
    var currentID: String { callID }
    @ObservationIgnored private var pendingOffer: String?
    @ObservationIgnored private var pendingCandidates: [(String, String?, Int32)] = []
    @ObservationIgnored private var remoteReady = false
    @ObservationIgnored private var ringTimeout: Task<Void, Never>?
    /// How long a call rings before it is a missed call.
    @ObservationIgnored var ringSeconds: Double = 45

    init(signalling: CallSignalling, system: CallSystem, log: CallLog = .shared, now: @escaping () -> Date = Date.init,
         isQuiet: @escaping () -> Bool = { false }, makeMedia: @escaping () -> any CallMedia) {
        self.signalling = signalling
        self.system = system
        self.log = log
        self.now = now
        self.isQuiet = isQuiet
        self.makeMedia = makeMedia
        system.onAnswer = { [weak self] id in Task { @MainActor in if self?.callID == id { await self?.accept() } } }
        system.onEnd = { [weak self] id in Task { @MainActor in if self?.callID == id { await self?.end() } } }
        system.onMute = { [weak self] id, muted in Task { @MainActor in if self?.callID == id { self?.setMuted(muted) } } }
    }

    var inCall: Bool { phase != .idle }

    // MARK: Starting

    /// Calls a contact. `false` when another call is going.
    @discardableResult
    func start(peerID: String, name: String, video: Bool) async -> Bool {
        guard phase == .idle else { return false }
        begin(peerID: peerID, name: name, video: video, outgoing: true, id: UUID().uuidString.lowercased())
        system.reportOutgoing(callID: callID, name: name, video: video)
        let media = makeMedia()
        self.media = media
        wire(media)
        do {
            try media.start(servers: await signalling.iceServers(), video: video)
            let sdp = try await media.makeOffer()
            guard await signalling.send(peer: peerID, op: "call.offer", payload: ["call_id": callID, "video": video, "sdp": sdp, "fingerprint": Self.fingerprint(in: sdp) ?? ""]) else {
                finish(.failed, notify: false)
                return false
            }
        } catch {
            finish(.failed, notify: false)
            return false
        }
        armTimeout()
        return true
    }

    private func begin(peerID: String, name: String, video: Bool, outgoing: Bool, id: String) {
        phase = outgoing ? .outgoing : .incoming
        self.peerID = peerID; peerName = name; self.video = video; self.outgoing = outgoing
        callID = id; muted = false; speaker = video; cameraOn = true; startedAt = nil
        pendingOffer = nil; pendingCandidates = []; remoteReady = false
    }

    private func wire(_ media: any CallMedia) {
        media.onCandidate = { [weak self] candidate, mid, index in
            guard let self, !self.callID.isEmpty else { return }
            let id = self.callID, peer = self.peerID
            var payload: [String: Any] = ["call_id": id, "candidate": candidate, "sdpMLineIndex": Int(index)]
            if let mid { payload["sdpMid"] = mid }
            Task { _ = await self.signalling.send(peer: peer, op: "call.ice", payload: payload) }
        }
        media.onConnection = { [weak self] up in
            guard let self, self.inCall else { return }
            if up {
                if self.phase != .active {
                    self.phase = .active
                    self.startedAt = self.now()
                    self.ringTimeout?.cancel()
                    self.system.reportConnected(callID: self.callID)
                }
            } else {
                Task { await self.end(reason: .failed) }
            }
        }
    }

    private func armTimeout() {
        ringTimeout?.cancel()
        let id = callID, seconds = ringSeconds
        ringTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.callID == id, self.phase == .outgoing || self.phase == .incoming else { return }
            await self.end(reason: self.outgoing ? .noAnswer : .missed)
        }
    }

    // MARK: What arrives

    /// Handles what the other phone sent (called after each sync).
    func handle(_ events: [CallEventInfo]) async {
        for event in events { await handle(event) }
    }

    func handle(_ event: CallEventInfo) async {
        switch event.op {
        case "call.offer": await receivedOffer(event)
        case "call.answer": await receivedAnswer(event)
        case "call.ice": await receivedCandidate(event)
        case "call.end", "call.decline", "call.busy":
            guard event.callID == callID, event.peerID == peerID, inCall else { return }
            let reason: Reason = event.op == "call.busy" ? .busy : (event.op == "call.decline" ? .declined : (phase == .incoming ? .missed : .remoteEnded))
            finish(reason.outcome(wasActive: phase == .active), notify: true)
        default: break
        }
    }

    private func receivedOffer(_ event: CallEventInfo) async {
        let video = (event.payload["video"] as? Bool) ?? false
        guard phase == .idle else {
            // Already on a call: the second caller hears "busy" and sees a missed call here.
            if event.callID != callID { _ = await signalling.send(peer: event.peerID, op: "call.busy", payload: ["call_id": event.callID]) }
            return
        }
        guard let sdp = event.payload["sdp"] as? String else { return }
        // Do Not Disturb or outside work hours: no ring; it is a missed call.
        if isQuiet() {
            log.add(CallRecord(id: event.callID, peerID: event.peerID, peerName: event.peerName, video: video, outgoing: false, date: now(), duration: 0, outcome: .missed))
            return
        }
        begin(peerID: event.peerID, name: event.peerName, video: video, outgoing: false, id: event.callID)
        pendingOffer = sdp
        guard await system.reportIncoming(callID: callID, name: peerName, video: video) else {
            // The system refused to ring (a Focus): a missed call.
            finish(.missed, notify: false)
            return
        }
        armTimeout()
    }

    private func receivedAnswer(_ event: CallEventInfo) async {
        guard phase == .outgoing, event.callID == callID, event.peerID == peerID, let sdp = event.payload["sdp"] as? String, let media else { return }
        do {
            try await media.apply(answer: sdp)
            remoteReady = true
            phase = .connecting
            ringTimeout?.cancel()
            await flushCandidates()
        } catch {
            await end(reason: .failed)
        }
    }

    private func receivedCandidate(_ event: CallEventInfo) async {
        guard inCall, event.callID == callID, event.peerID == peerID, let candidate = event.payload["candidate"] as? String else { return }
        let item = (candidate, event.payload["sdpMid"] as? String, Int32((event.payload["sdpMLineIndex"] as? Int) ?? 0))
        if remoteReady, let media { await media.add(candidate: item.0, mid: item.1, index: item.2) } else { pendingCandidates.append(item) }
    }

    private func flushCandidates() async {
        guard let media else { return }
        let waiting = pendingCandidates
        pendingCandidates = []
        for item in waiting { await media.add(candidate: item.0, mid: item.1, index: item.2) }
    }

    // MARK: What the person does

    /// Answers the ringing call.
    func accept() async {
        guard phase == .incoming, let offer = pendingOffer else { return }
        phase = .connecting
        ringTimeout?.cancel()
        let media = makeMedia()
        self.media = media
        wire(media)
        do {
            try media.start(servers: await signalling.iceServers(), video: video)
            let answer = try await media.accept(offer: offer)
            remoteReady = true
            pendingOffer = nil
            _ = await signalling.send(peer: peerID, op: "call.answer", payload: ["call_id": callID, "sdp": answer, "fingerprint": Self.fingerprint(in: answer) ?? ""])
            await flushCandidates()
        } catch {
            await end(reason: .failed)
        }
    }

    /// Declines the ringing call.
    func decline() async {
        guard phase == .incoming else { return }
        _ = await signalling.send(peer: peerID, op: "call.decline", payload: ["call_id": callID])
        finish(.declined, notify: true)
    }

    enum Reason { case hungUp, noAnswer, missed, declined, busy, failed, remoteEnded
        func outcome(wasActive: Bool) -> CallOutcome {
            switch self {
            case .hungUp, .remoteEnded: wasActive ? .completed : .missed
            case .noAnswer: .noAnswer
            case .missed: .missed
            case .declined: .declined
            case .busy: .busy
            case .failed: .failed
            }
        }
    }

    /// Ends the call (hang up, cancel before an answer, or a failure).
    func end(reason: Reason = .hungUp) async {
        guard inCall else { return }
        if phase == .incoming && reason == .hungUp { await decline(); return }
        if reason != .missed { _ = await signalling.send(peer: peerID, op: "call.end", payload: ["call_id": callID]) }
        finish(reason.outcome(wasActive: phase == .active), notify: true)
    }

    func setMuted(_ on: Bool) { muted = on; media?.setMuted(on) }
    func toggleSpeaker() { speaker.toggle(); media?.setSpeaker(speaker) }
    func toggleCamera() { cameraOn.toggle(); media?.setVideo(cameraOn) }
    func flipCamera() { media?.flipCamera() }

    private func finish(_ outcome: CallOutcome, notify: Bool) {
        ringTimeout?.cancel()
        let duration = startedAt.map { now().timeIntervalSince($0) } ?? 0
        log.add(CallRecord(id: callID, peerID: peerID, peerName: peerName, video: video, outgoing: outgoing, date: startedAt ?? now(), duration: duration, outcome: outcome))
        if notify { system.reportEnded(callID: callID, answeredOrOutgoing: phase != .incoming) }
        media?.close()
        media = nil
        phase = .idle
        callID = ""; peerID = ""; startedAt = nil; pendingOffer = nil; pendingCandidates = []; remoteReady = false
    }

    /// The `a=fingerprint:` value of an SDP, the DTLS key that protects the media.
    nonisolated static func fingerprint(in sdp: String) -> String? {
        for line in sdp.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("a=fingerprint:"), let space = text.firstIndex(of: " ") { return String(text[text.index(after: space)...]).uppercased() }
        }
        return nil
    }
}

/// One incoming call op, in Swift's shape.
struct CallEventInfo: Equatable {
    let op: String
    let callID: String
    let peerID: String
    let peerName: String
    let payload: [String: Any]

    init(op: String, callID: String, peerID: String, peerName: String, payload: [String: Any]) {
        self.op = op; self.callID = callID; self.peerID = peerID; self.peerName = peerName; self.payload = payload
    }

    static func == (lhs: CallEventInfo, rhs: CallEventInfo) -> Bool {
        lhs.op == rhs.op && lhs.callID == rhs.callID && lhs.peerID == rhs.peerID
    }
}
