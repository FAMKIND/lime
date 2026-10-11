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
    /// Starts the system's incoming-call report and returns at once; `completion` says whether the system will ring (`nil` error) or refused.
    func reportIncoming(callID: String, name: String, video: Bool, completion: @escaping @MainActor (_ refusal: String?) -> Void)
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
    @ObservationIgnored private let myID: () -> String?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var callID = ""
    var currentID: String { callID }
    @ObservationIgnored private var pendingOffer: String?
    @ObservationIgnored private var pendingCandidates: [(String, String?, Int32)] = []
    @ObservationIgnored private var remoteReady = false
    @ObservationIgnored private var ringTimeout: Task<Void, Never>?
    @ObservationIgnored private var connectTimeout: Task<Void, Never>?
    @ObservationIgnored private var poller: Task<Void, Never>?
    /// Candidates that arrived before their offer (the mailbox does not keep the order), by call id.
    @ObservationIgnored private var earlyCandidates: [String: [(String, String?, Int32)]] = [:]
    /// Ops waiting to be handled, one at a time and in order, away from the sync that fetched them.
    @ObservationIgnored private var inbox: [CallEventInfo] = []
    @ObservationIgnored private var draining = false
    /// Fetches the mailbox now (set by the app); used once a second while a call is ringing or connecting, in case a nudge is missed.
    @ObservationIgnored var fetchNow: (() async -> Void)?
    /// How long the media path may take to come up after an answer before the call fails.
    @ObservationIgnored var connectSeconds: Double = 30
    /// How long one op may take to handle before the queue moves on.
    @ObservationIgnored var handlerSeconds: Double = 3
    @ObservationIgnored private let diag = CallDiagnostics.shared
    /// My own candidates wait until my offer/answer has gone out, so the other phone never sees one before the description it belongs to.
    @ObservationIgnored private var outbound: [(String, String?, Int32)] = []
    @ObservationIgnored private var descriptionSent = false
    @ObservationIgnored private var batcher: Task<Void, Never>?
    /// How long a call rings before it is a missed call.
    @ObservationIgnored var ringSeconds: Double = 45

    init(signalling: CallSignalling, system: CallSystem, log: CallLog = .shared, now: @escaping () -> Date = Date.init,
         isQuiet: @escaping () -> Bool = { false }, myID: @escaping () -> String? = { nil }, makeMedia: @escaping () -> any CallMedia) {
        self.signalling = signalling
        self.system = system
        self.log = log
        self.now = now
        self.isQuiet = isQuiet
        self.myID = myID
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
        let id = callID
        diag.log("start video=\(video)")
        do {
            let servers = await signalling.iceServers()
            guard callID == id else { return false }
            diag.log("ice servers: \(servers.count) (relay credentials \(servers.contains { $0.username != nil } ? "present" : "missing"))")
            try media.start(servers: servers, video: video)
            let sdp = try await media.makeOffer()
            guard callID == id else { return false }
            descriptionSent = true // from here on a candidate is late: it is not in this SDP
            let began = Date()
            let sent = await signalling.send(peer: peerID, op: "call.offer", payload: ["call_id": callID, "video": video, "sdp": sdp, "fingerprint": Self.fingerprint(in: sdp) ?? ""])
            diag.log("sent call.offer ok=\(sent) \(Int(Date().timeIntervalSince(began) * 1000)) ms")
            guard sent, callID == id else {
                if callID == id { finish(.failed, notify: true) }
                return false
            }
        } catch {
            diag.log("start failed: \(error)")
            if callID == id { finish(.failed, notify: true) }
            return false
        }
        armTimeout()
        startPolling()
        return true
    }

    private func begin(peerID: String, name: String, video: Bool, outgoing: Bool, id: String) {
        phase = outgoing ? .outgoing : .incoming
        self.peerID = peerID; peerName = name; self.video = video; self.outgoing = outgoing
        callID = id; muted = false; speaker = video; cameraOn = true; startedAt = nil
        pendingOffer = nil; pendingCandidates = []; remoteReady = false; outbound = []; descriptionSent = false
    }

    private func wire(_ media: any CallMedia) {
        media.onCandidate = { [weak self] candidate, mid, index in
            guard let self, !self.callID.isEmpty else { return }
            // Before my description has gone out, candidates are inside it. Later ones are sent together, at most once a second.
            guard self.descriptionSent else { return }
            self.diag.log("late candidate \(CallDiagnostics.candidateKind(candidate))")
            self.outbound.append((candidate, mid, index))
            self.scheduleBatch()
        }
        media.onConnection = { [weak self] up in
            guard let self, self.inCall else { return }
            self.diag.log("media connection \(up ? "up" : "failed")")
            if up {
                if self.phase != .active {
                    self.phase = .active
                    self.startedAt = self.now()
                    self.ringTimeout?.cancel()
                    self.connectTimeout?.cancel()
                    self.stopPolling()
                    self.system.reportConnected(callID: self.callID)
                }
            } else {
                Task { await self.end(reason: .failed) }
            }
        }
    }

    /// Candidates found after the description went out: one `call.ice` op with all of them, at most once a second.
    private func scheduleBatch() {
        guard batcher == nil else { return }
        let id = callID
        batcher = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.callID == id, !Task.isCancelled else { return }
            self.batcher = nil
            let items = self.outbound
            self.outbound = []
            guard !items.isEmpty else { return }
            let list: [[String: Any]] = items.map { item in
                var entry: [String: Any] = ["candidate": item.0, "sdpMLineIndex": Int(item.2)]
                if let mid = item.1 { entry["sdpMid"] = mid }
                return entry
            }
            let started = Date()
            let ok = await self.signalling.send(peer: self.peerID, op: "call.ice", payload: ["call_id": id, "candidates": list])
            self.diag.log("sent call.ice x\(items.count) ok=\(ok) \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        }
    }

    /// While ringing or connecting, ask the mailbox once a second (a missed nudge must not strand a call).
    private func startPolling() {
        guard poller == nil, let fetchNow else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.inCall, self.phase != .active else { break }
                await fetchNow()
            }
            self?.poller = nil
        }
    }

    private func stopPolling() {
        poller?.cancel()
        poller = nil
    }

    /// The media path must come up within `connectSeconds` of the answer, or the call fails and everything is torn down.
    private func armConnectTimeout() {
        connectTimeout?.cancel()
        let id = callID, seconds = connectSeconds
        connectTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.callID == id, self.phase == .connecting else { return }
            self.diag.log("connect timeout")
            await self.end(reason: .failed)
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
        inbox.append(contentsOf: events)
        guard !draining else { return }
        draining = true
        defer { draining = false }
        if inbox.count > 0 { diag.log("drain starts with \(inbox.count) queued") }
        while !inbox.isEmpty { await handleWithWatchdog(inbox.removeFirst()) }
    }

    /// One event must never hold up the next: after `handlerSeconds` the drain moves on (the handler keeps running on its own).
    private func handleWithWatchdog(_ event: CallEventInfo) async {
        let finished = Once()
        let work = Task { @MainActor in
            await self.handle(event)
            finished.fire()
        }
        _ = work
        let limit = handlerSeconds
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finished.onFire = { continuation.resume() }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(limit))
                if finished.fireIfWaiting() { self.diag.log("handler stuck: \(event.op)") }
            }
        }
    }

    func handle(_ event: CallEventInfo) async {
        diag.log("recv \(event.op) phase=\(phase) mine=\(event.callID == callID)\(event.op == "call.ice" ? " kind=\(CallDiagnostics.candidateKind(event.payload["candidate"] as? String ?? ""))" : "")")
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
        if phase != .idle {
            // Crossed calls: both phones offered at once. The lower user id's offer wins; the other side drops its own, silently.
            if phase == .outgoing, event.peerID == peerID, event.callID != callID, let me = myID() {
                diag.log("glare: \(me < peerID ? "mine wins" : "theirs wins")")
                if me < peerID { return }
                finish(.missed, notify: true)
                // falls through: theirs is handled as an ordinary incoming call
            } else {
                // Already on a call: the second caller hears "busy" and sees a missed call here.
                if event.callID != callID { _ = await signalling.send(peer: event.peerID, op: "call.busy", payload: ["call_id": event.callID]) }
                return
            }
        }
        guard let sdp = event.payload["sdp"] as? String else { return }
        // Do Not Disturb or outside work hours: no ring; it is a missed call.
        if isQuiet() {
            log.add(CallRecord(id: event.callID, peerID: event.peerID, peerName: event.peerName, video: video, outgoing: false, date: now(), duration: 0, outcome: .missed))
            return
        }
        begin(peerID: event.peerID, name: event.peerName, video: video, outgoing: false, id: event.callID)
        pendingOffer = sdp
        pendingCandidates = earlyCandidates.removeValue(forKey: event.callID) ?? []
        startPolling()
        armTimeout()
        // The system's report is never awaited here: on a device it can take long (or never answer) and the queue must not wait for it.
        let id = callID, began = Date()
        system.reportIncoming(callID: id, name: peerName, video: video) { [weak self] refusal in
            guard let self else { return }
            if let refusal {
                self.diag.log("incoming refused: \(refusal)")
                // The system refused to ring (a Focus): a missed call.
                if self.callID == id, self.phase == .incoming { self.finish(.missed, notify: false) }
            } else {
                self.diag.log("incoming reported in \(Int(Date().timeIntervalSince(began) * 1000)) ms")
            }
        }
    }

    private func receivedAnswer(_ event: CallEventInfo) async {
        guard phase == .outgoing, event.callID == callID, event.peerID == peerID, let sdp = event.payload["sdp"] as? String, let media else { return }
        do {
            phase = .connecting
            ringTimeout?.cancel()
            armConnectTimeout()
            try await media.apply(answer: sdp)
            diag.log("answer applied")
            remoteReady = true
            await flushCandidates()
        } catch {
            diag.log("apply answer failed: \(error)")
            await end(reason: .failed)
        }
    }

    private func receivedCandidate(_ event: CallEventInfo) async {
        var items: [(String, String?, Int32)] = []
        if let list = event.payload["candidates"] as? [[String: Any]] {
            items = list.compactMap { entry in (entry["candidate"] as? String).map { ($0, entry["sdpMid"] as? String, Int32((entry["sdpMLineIndex"] as? Int) ?? 0)) } }
        } else if let candidate = event.payload["candidate"] as? String {
            items = [(candidate, event.payload["sdpMid"] as? String, Int32((event.payload["sdpMLineIndex"] as? Int) ?? 0))]
        }
        for item in items { await receivedCandidate(item, of: event) }
    }

    private func receivedCandidate(_ item: (String, String?, Int32), of event: CallEventInfo) async {
        // Before its offer has been handled (or while this phone is on another call) a candidate is kept, not dropped.
        guard inCall, event.callID == callID, event.peerID == peerID else {
            if event.callID != callID || !inCall { earlyCandidates[event.callID, default: []].append(item) }
            if earlyCandidates.count > 4, let oldest = earlyCandidates.keys.first(where: { $0 != event.callID }) { earlyCandidates[oldest] = nil }
            return
        }
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
        armConnectTimeout()
        let id = callID
        diag.log("accept")
        let media = makeMedia()
        self.media = media
        wire(media)
        do {
            let servers = await signalling.iceServers()
            guard callID == id else { return }
            diag.log("ice servers: \(servers.count) (relay credentials \(servers.contains { $0.username != nil } ? "present" : "missing"))")
            try media.start(servers: servers, video: video)
            let answer = try await media.accept(offer: offer)
            guard callID == id else { return }
            descriptionSent = true
            remoteReady = true
            pendingOffer = nil
            let began = Date()
            let sent = await signalling.send(peer: peerID, op: "call.answer", payload: ["call_id": callID, "sdp": answer, "fingerprint": Self.fingerprint(in: answer) ?? ""])
            diag.log("sent call.answer ok=\(sent) \(Int(Date().timeIntervalSince(began) * 1000)) ms")
            guard sent, callID == id else {
                if callID == id { await end(reason: .failed) }
                return
            }
            await flushCandidates()
        } catch {
            diag.log("accept failed: \(error)")
            if callID == id { await end(reason: .failed) }
        }
    }

    /// Declines the ringing call.
    func decline() async {
        guard phase == .incoming else { return }
        let id = callID, peer = peerID
        finish(.declined, notify: true)
        _ = await signalling.send(peer: peer, op: "call.decline", payload: ["call_id": id])
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
        diag.log("end reason=\(reason) phase=\(phase)")
        if phase == .incoming && reason == .hungUp { await decline(); return }
        // Tear down first and tell the other phone afterwards: a second end (the call screen and the system's End button) then finds nothing to end.
        let id = callID, peer = peerID
        let outcome = reason.outcome(wasActive: phase == .active)
        finish(outcome, notify: true)
        if reason != .missed { _ = await signalling.send(peer: peer, op: "call.end", payload: ["call_id": id]) }
    }

    func setMuted(_ on: Bool) { muted = on; media?.setMuted(on) }
    func toggleSpeaker() { speaker.toggle(); media?.setSpeaker(speaker) }
    func toggleCamera() { cameraOn.toggle(); media?.setVideo(cameraOn) }
    func flipCamera() { media?.flipCamera() }

    private func finish(_ outcome: CallOutcome, notify: Bool) {
        guard inCall else { return }
        diag.log("finish \(outcome.rawValue)")
        ringTimeout?.cancel()
        connectTimeout?.cancel()
        batcher?.cancel(); batcher = nil
        stopPolling()
        let duration = startedAt.map { now().timeIntervalSince($0) } ?? 0
        log.add(CallRecord(id: callID, peerID: peerID, peerName: peerName, video: video, outgoing: outgoing, date: startedAt ?? now(), duration: duration, outcome: outcome))
        if notify { system.reportEnded(callID: callID, answeredOrOutgoing: phase != .incoming) }
        media?.close()
        media = nil
        phase = .idle
        callID = ""; peerID = ""; startedAt = nil; pendingOffer = nil; pendingCandidates = []; remoteReady = false
        outbound = []; descriptionSent = false
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

/// Resumes one waiter, once, from whichever of two sources comes first.
@MainActor
final class Once {
    var onFire: (() -> Void)?
    private var fired = false
    func fire() {
        guard !fired else { return }
        fired = true
        onFire?()
    }
    /// For the watchdog: fires, and says whether it was the first.
    func fireIfWaiting() -> Bool {
        guard !fired else { return false }
        fire()
        return true
    }
}
