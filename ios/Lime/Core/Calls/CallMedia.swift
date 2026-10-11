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
        rtc.isAudioEnabled = true
    }

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
        let answer = try await connection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        try await connection.setLocalDescription(answer)
        return await gathered(connection, fallback: answer.sdp)
    }

    func apply(answer: String) async throws {
        guard let connection else { throw CallMediaError.notStarted }
        try await connection.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer))
    }

    func add(candidate: String, mid: String?, index: Int32) async {
        try? await connection?.add(RTCIceCandidate(sdp: candidate, sdpMLineIndex: index, sdpMid: mid))
    }

    private var fallbackActive = false

    /// CallKit has not called back (it is reset on some phones): configure and activate the audio session ourselves.
    func activateAudioFallback(video: Bool) -> Bool {
        guard manualAudio, !fallbackActive else { return false }
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        do {
            try rtc.setCategory(.playAndRecord, with: video ? [.allowBluetooth, .defaultToSpeaker] : [.allowBluetooth])
            try rtc.setMode(video ? .videoChat : .voiceChat)
            try rtc.setActive(true)
        } catch {
            CallDiagnostics.shared.log("audio fallback failed: \(error)")
            return false
        }
        rtc.isAudioEnabled = true
        fallbackActive = true
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
        Task { @MainActor in if let track, let view = remoteView as? RTCMTLVideoView { track.add(view) } }
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
        Task { @MainActor in if let track, let view = remoteView as? RTCMTLVideoView { track.add(view) } }
    }
}
