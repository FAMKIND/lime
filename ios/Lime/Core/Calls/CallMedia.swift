import AVFoundation
import Foundation
import UIKit
@preconcurrency import WebRTC

/// The relay and STUN addresses a call may use.
struct IceServer: Equatable, Sendable {
    var urls: [String]
    var username: String?
    var credential: String?
}

/// What a call needs from the media engine. The real one is WebRTC (below); tests use a fake, since two simulators cannot make a real call.
@MainActor
protocol CallMedia: AnyObject {
    /// A local ICE candidate was found: its text, media id and line index.
    var onCandidate: ((String, String?, Int32) -> Void)? { get set }
    /// The media path came up (`true`) or failed (`false`).
    var onConnection: ((Bool) -> Void)? { get set }
    /// The other side's picture started (`true`: a frame arrived) or is gone.
    var onRemoteVideo: ((Bool) -> Void)? { get set }
    var localView: UIView { get }
    var remoteView: UIView { get }

    func start(servers: [IceServer], video: Bool) throws
    func makeOffer() async throws -> String
    func accept(offer: String) async throws -> String
    func apply(answer: String) async throws
    func add(candidate: String, mid: String?, index: Int32) async
    func setMuted(_ muted: Bool)
    func setVideo(_ on: Bool)
    func flipCamera()
    func setSpeaker(_ on: Bool)
    /// The system (CallKit) has not activated the audio session: do it here. `false` when nothing needed doing.
    func activateAudioFallback(video: Bool) -> Bool
    func close()
}

enum CallMediaError: Error { case notStarted, failed }

/// Google's WebRTC: Opus audio, VP8/H.264 video, DTLS-SRTP end to end between the phones (a TURN relay only carries ciphertext).
@MainActor
final class WebRTCMedia: NSObject, CallMedia {
    var onCandidate: ((String, String?, Int32) -> Void)?
    var onConnection: ((Bool) -> Void)?
    var onRemoteVideo: ((Bool) -> Void)?
    private lazy var remoteSlot = RemoteVideoSlot()
    private var statsTask: Task<Void, Never>?
    let localView: UIView = RTCMTLVideoView(frame: .zero)
    let remoteView: UIView = RTCMTLVideoView(frame: .zero)

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    }()

    private var connection: RTCPeerConnection?
    private var audioTrack: RTCAudioTrack?
    private var videoTrack: RTCVideoTrack?
    private var capturer: RTCCameraVideoCapturer?
    private var front = true
    private var wantsVideo = false

    /// With CallKit the system activates the audio session; WebRTC must wait for that (manual audio), or the two fight over it.
    private let manualAudio: Bool

    init(manualAudio: Bool = false) {
        self.manualAudio = manualAudio
        super.init()
    }

    /// CallKit gave the call its audio session: let WebRTC use it.
    nonisolated static func audioSessionActivated(_ session: AVAudioSession) {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.audioSessionDidActivate(session)
        // If lime already activated the audio itself, CallKit's later "activated" only updates WebRTC's bookkeeping above: no second reconfiguration.
        if !limeHoldsAudio.value { rtc.isAudioEnabled = true }
    }

    /// Set while lime's own fallback has the audio session (so a late `didActivate` does not reconfigure it).
    nonisolated static let limeHoldsAudio = AtomicFlag()

    nonisolated static func audioSessionDeactivated(_ session: AVAudioSession) {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.isAudioEnabled = false
        rtc.audioSessionDidDeactivate(session)
    }

    func start(servers: [IceServer], video: Bool) throws {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.useManualAudio = manualAudio
        if !manualAudio { rtc.isAudioEnabled = true }
        let configuration = RTCConfiguration()
        configuration.iceServers = servers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        configuration.sdpSemantics = .unifiedPlan
        // Few candidates, all bundled on one transport: the fewer there are, the fewer there is to send (TURN over TCP/TLS stays in the servers).
        configuration.continualGatheringPolicy = .gatherContinually
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.tcpCandidatePolicy = .disabled
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        guard let connection = Self.factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else { throw CallMediaError.failed }
        self.connection = connection
        wantsVideo = video
        if let view = remoteView as? RTCMTLVideoView {
            remoteSlot.setRenderer(FrameLogger(target: view) { [weak self] size in
                CallDiagnostics.shared.log("remote video first frame \(Int(size.width))x\(Int(size.height))")
                self?.onRemoteVideo?(true)
            })
        }
        startStats()
        relayConfigured = servers.contains { $0.urls.contains { $0.hasPrefix("turn") } }

        let audioSource = Self.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let audio = Self.factory.audioTrack(with: audioSource, trackId: "lime-audio")
        audioTrack = audio
        connection.add(audio, streamIds: ["lime"])

        if video {
            let source = Self.factory.videoSource()
            let capturer = RTCCameraVideoCapturer(delegate: source)
            self.capturer = capturer
            let track = Self.factory.videoTrack(with: source, trackId: "lime-video")
            videoTrack = track
            connection.add(track, streamIds: ["lime"])
            track.add(localView as! RTCMTLVideoView)
            startCapture()
        }
    }

    private func startCapture() {
        guard let capturer else { return }
        let position: AVCaptureDevice.Position = front ? .front : .back
        guard let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == position }) ?? RTCCameraVideoCapturer.captureDevices().first else { return }
        // About 720p at 24 fps; WebRTC adapts it down on a weak network.
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let format = formats.min { abs(CMVideoFormatDescriptionGetDimensions($0.formatDescription).width - 1280) < abs(CMVideoFormatDescriptionGetDimensions($1.formatDescription).width - 1280) } ?? formats.first
        guard let format else { return }
        let fps = min(24, Int(format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 24))
        capturer.startCapture(with: device, format: format, fps: fps)
    }

    func makeOffer() async throws -> String {
        guard let connection else { throw CallMediaError.notStarted }
        let constraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": wantsVideo ? "true" : "false"], optionalConstraints: nil)
        let offer = try await connection.offer(for: constraints)
        try await connection.setLocalDescription(offer)
        return await gathered(connection, fallback: offer.sdp)
    }

    /// Waits (at most 2.5 s) for ICE gathering to finish, then returns the local description *with its candidates inside*, so the
    /// candidates travel in the signed offer/answer and need no ops of their own.
    private func gathered(_ connection: RTCPeerConnection, fallback: String) async -> String {
        let started = Date()
        while !Self.gatheringDone(elapsed: Date().timeIntervalSince(started), complete: connection.iceGatheringState == .complete,
                                  relayConfigured: relayConfigured, hasRelay: (connection.localDescription?.sdp ?? "").contains("typ relay")) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let sdp = connection.localDescription?.sdp ?? fallback
        let kinds = sdp.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("a=candidate") }.map { CallDiagnostics.candidateKind(String($0)) }
        let counts = Dictionary(grouping: kinds, by: { $0 }).map { "\($0.key)=\($0.value.count)" }.sorted().joined(separator: " ")
        CallDiagnostics.shared.log("gathering \(connection.iceGatheringState == .complete ? "complete" : "CAP HIT") in \(Int(Date().timeIntervalSince(started) * 1000)) ms: \(counts.isEmpty ? "none" : counts)")
        return sdp
    }

    nonisolated static let gatherCap: TimeInterval = 2.5
    /// With a relay configured, 1 s is enough once a relay candidate is in; otherwise wait for completion, up to the cap.
    nonisolated static let gatherQuick: TimeInterval = 1.0

    nonisolated static func gatheringDone(elapsed: TimeInterval, complete: Bool, relayConfigured: Bool, hasRelay: Bool) -> Bool {
        // "Complete" is not enough when a relay is expected but absent (an answer once left with host candidates only); keep waiting for it.
        (complete && (hasRelay || !relayConfigured)) || elapsed >= gatherCap || (relayConfigured && hasRelay && elapsed >= gatherQuick)
    }

    private var relayConfigured = false

    func accept(offer: String) async throws -> String {
        guard let connection else { throw CallMediaError.notStarted }
        try await connection.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: offer))
        attachRemoteVideo(connection)
        let answer = try await connection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        try await connection.setLocalDescription(answer)
        return await gathered(connection, fallback: answer.sdp)
    }

    func apply(answer: String) async throws {
        guard let connection else { throw CallMediaError.notStarted }
        try await connection.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer))
        attachRemoteVideo(connection)
    }

    func add(candidate: String, mid: String?, index: Int32) async {
        try? await connection?.add(RTCIceCandidate(sdp: candidate, sdpMLineIndex: index, sdpMid: mid))
    }

    private var fallbackActive = false

    /// After a remote description, look at every video transceiver: its receiver's track is the picture to show, however the
    /// delegate reported (or did not report) it.
    private func attachRemoteVideo(_ connection: RTCPeerConnection) {
        for transceiver in connection.transceivers where transceiver.mediaType == .video {
            if let track = transceiver.receiver.track as? RTCVideoTrack {
                CallDiagnostics.shared.log("remote video track found on a transceiver (enabled: \(track.isEnabled), direction \(transceiver.direction.rawValue))")
                remoteSlot.setSource(TrackSource(track))
            }
        }
    }

    // MARK: Call-quality statistics (every 5 s while a call is up)

    private func startStats() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            var lastBytes: Double = 0
            var lastAt = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, let connection = self.connection, connection.iceConnectionState == .connected || connection.iceConnectionState == .completed else { continue }
                let report = await withCheckedContinuation { (continuation: CheckedContinuation<RTCStatisticsReport, Never>) in
                    connection.statistics { continuation.resume(returning: $0) }
                }
                let line = CallStats.line(report: report, lastBytes: &lastBytes, elapsed: Date().timeIntervalSince(lastAt))
                lastAt = Date()
                CallDiagnostics.shared.log("stats \(line)")
            }
        }
    }

    /// CallKit has not called back (it is reset on some phones): configure and activate the audio session ourselves.
    func activateAudioFallback(video: Bool) -> Bool {
        guard manualAudio, !fallbackActive else { return false }
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        do {
            try rtc.setCategory(.playAndRecord, with: video ? [.allowBluetoothHFP, .defaultToSpeaker] : [.allowBluetoothHFP])
            try rtc.setMode(video ? .videoChat : .voiceChat)
            try rtc.setActive(true)
        } catch {
            CallDiagnostics.shared.log("audio fallback failed: \(error)")
            return false
        }
        rtc.isAudioEnabled = true
        fallbackActive = true
        Self.limeHoldsAudio.value = true
        return true
    }

    func setMuted(_ muted: Bool) { audioTrack?.isEnabled = !muted }

    func setVideo(_ on: Bool) { videoTrack?.isEnabled = on }

    func flipCamera() {
        front.toggle()
        capturer?.stopCapture { [weak self] in Task { @MainActor in self?.startCapture() } }
    }

    func setSpeaker(_ on: Bool) {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        try? session.overrideOutputAudioPort(on ? .speaker : .none)
        session.unlockForConfiguration()
    }

    /// Tears everything down in the order WebRTC needs: stop the camera and wait for it, take the views off the tracks, then close.
    func close() {
        statsTask?.cancel(); statsTask = nil
        remoteSlot.clear()
        let capturer = capturer, connection = connection, videoTrack = videoTrack
        audioTrack?.isEnabled = false
        self.capturer = nil; self.connection = nil; self.videoTrack = nil; audioTrack = nil
        audioTrack?.isEnabled = false
        if let view = localView as? RTCMTLVideoView { videoTrack?.remove(view) }
        for receiver in connection?.receivers ?? [] {
            if let track = receiver.track as? RTCVideoTrack, let view = remoteView as? RTCMTLVideoView { track.remove(view) }
        }
        connection?.delegate = nil
        if let capturer {
            // Closing the connection and freeing the capturer while the camera is still delivering frames can crash; wait for it to stop.
            capturer.stopCapture { connection?.close() }
        } else {
            connection?.close()
        }
        if manualAudio {
            let rtc = RTCAudioSession.sharedInstance()
            rtc.isAudioEnabled = false
            if fallbackActive {
                fallbackActive = false
                Self.limeHoldsAudio.value = false
                rtc.lockForConfiguration()
                try? rtc.setActive(false)
                rtc.unlockForConfiguration()
            }
        }
    }
}

extension WebRTCMedia: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let track = stream.videoTracks.first
        Task { @MainActor in
            CallDiagnostics.shared.log("remote stream added (video tracks: \(stream.videoTracks.count))")
            if let track { self.remoteSlot.setSource(TrackSource(track)) }
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in CallDiagnostics.shared.log("ice state \(newState.rawValue)") }
        let connected = newState == .connected || newState == .completed
        let failed = newState == .failed
        Task { @MainActor in
            if connected { onConnection?(true) } else if failed { onConnection?(false) }
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let sdp = candidate.sdp, mid = candidate.sdpMid, index = candidate.sdpMLineIndex
        Task { @MainActor in onCandidate?(sdp, mid, index) }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        let track = rtpReceiver.track as? RTCVideoTrack
        let kind = rtpReceiver.track?.kind ?? "?"
        Task { @MainActor in
            CallDiagnostics.shared.log("remote receiver added: \(kind)")
            if let track { self.remoteSlot.setSource(TrackSource(track)) }
        }
    }
}


/// A flag readable from any thread.
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return flag }
        set { lock.lock(); flag = newValue; lock.unlock() }
    }
}

/// Where frames come from (a WebRTC video track in the app, a fake in tests).
@MainActor
protocol FrameSource: AnyObject {
    func add(renderer: AnyObject)
    func remove(renderer: AnyObject)
}

@MainActor
final class TrackSource: FrameSource {
    let track: RTCVideoTrack
    init(_ track: RTCVideoTrack) { self.track = track }
    func add(renderer: AnyObject) { if let renderer = renderer as? RTCVideoRenderer { track.add(renderer) } }
    func remove(renderer: AnyObject) { if let renderer = renderer as? RTCVideoRenderer { track.remove(renderer) } }
}

/// Joins the other side's picture (a source) to what draws it (a renderer), whichever of the two arrives first, and again when the
/// source changes (a renegotiation or a camera flip on the other side).
@MainActor
final class RemoteVideoSlot {
    private var source: FrameSource?
    private var renderer: AnyObject?
    private var attachedSource: FrameSource?
    private(set) var attachments = 0

    func setSource(_ new: FrameSource?) {
        guard new !== source else { return }
        detach()
        source = new
        attach()
    }

    func setRenderer(_ new: AnyObject?) {
        detach()
        renderer = new
        attach()
    }

    func clear() {
        detach()
        source = nil
        renderer = nil
    }

    private func attach() {
        guard let source, let renderer, attachedSource == nil else { return }
        source.add(renderer: renderer)
        attachedSource = source
        attachments += 1
        CallDiagnostics.shared.log("remote video renderer attached")
    }

    private func detach() {
        if let attachedSource, let renderer { attachedSource.remove(renderer: renderer) }
        attachedSource = nil
    }
}

/// Passes frames on to the view and says when the first one arrives, with its size.
final class FrameLogger: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private nonisolated(unsafe) let target: any RTCVideoRenderer
    private let first: @MainActor (CGSize) -> Void
    private var seen = false

    @MainActor init(target: RTCMTLVideoView, first: @escaping @MainActor (CGSize) -> Void) {
        self.target = target
        self.first = first
    }

    func setSize(_ size: CGSize) { target.setSize(size) }

    func renderFrame(_ frame: RTCVideoFrame?) {
        target.renderFrame(frame)
        guard !seen, let frame else { return }
        seen = true
        let size = CGSize(width: Int(frame.width), height: Int(frame.height))
        let callback = first
        Task { @MainActor in callback(size) }
    }
}

/// One log line from a peer connection's statistics: the path, round trip, audio quality and, for video, the picture. No addresses.
enum CallStats {
    static func line(report: RTCStatisticsReport, lastBytes: inout Double, elapsed: TimeInterval) -> String {
        var parts: [String] = []
        var pairLocal = "?", pairRemote = "?"
        var kinds: [String: String] = [:]
        for (id, stat) in report.statistics where stat.type == "local-candidate" || stat.type == "remote-candidate" {
            kinds[id] = (stat.values["candidateType"] as? String) ?? "?"
        }
        for stat in report.statistics.values {
            let v = stat.values
            func number(_ key: String) -> Double? { (v[key] as? NSNumber)?.doubleValue }
            switch stat.type {
            case "candidate-pair" where (v["nominated"] as? NSNumber)?.boolValue == true && (v["state"] as? String) == "succeeded":
                pairLocal = kinds[(v["localCandidateId"] as? String) ?? ""] ?? "?"
                pairRemote = kinds[(v["remoteCandidateId"] as? String) ?? ""] ?? "?"
                if let rtt = number("currentRoundTripTime") { parts.append("rtt \(Int(rtt * 1000)) ms") }
            case "inbound-rtp" where (v["kind"] as? String) == "audio":
                parts.append("audio in: jitter \(Int((number("jitter") ?? 0) * 1000)) ms, lost \(Int(number("packetsLost") ?? 0)), concealed \(Int(number("concealedSamples") ?? 0))/\(Int(number("totalSamplesReceived") ?? 0))")
                if let delay = number("jitterBufferDelay"), let count = number("jitterBufferEmittedCount"), count > 0 { parts.append("jitter buffer \(Int(delay / count * 1000)) ms") }
            case "outbound-rtp" where (v["kind"] as? String) == "audio":
                let bytes = number("bytesSent") ?? 0
                if elapsed > 0, lastBytes > 0 { parts.append("audio out \(Int((bytes - lastBytes) * 8 / elapsed / 1000)) kbps") }
                lastBytes = bytes
            case "inbound-rtp" where (v["kind"] as? String) == "video":
                parts.append("video in \(Int(number("frameWidth") ?? 0))x\(Int(number("frameHeight") ?? 0)) \(Int(number("framesPerSecond") ?? 0)) fps, dropped \(Int(number("framesDropped") ?? 0))")
            case "outbound-rtp" where (v["kind"] as? String) == "video":
                parts.append("video out \(Int(number("frameWidth") ?? 0))x\(Int(number("frameHeight") ?? 0)) \(Int(number("framesPerSecond") ?? 0)) fps")
            default: break
            }
        }
        return "path \(pairLocal)->\(pairRemote); " + (parts.isEmpty ? "no samples" : parts.joined(separator: "; "))
    }
}
