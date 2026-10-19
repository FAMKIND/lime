import Foundation
import LiveKit

/// Something the media engine tells the group call manager (LIME-112b). Participant ids are the random LiveKit identities.
enum GroupMediaEvent: Sendable, Equatable {
    case connection(connected: Bool, error: String?)
    case participantConnected(String)
    case participantDisconnected(String)
    case microphone(participant: String, muted: Bool)
    case camera(participant: String, on: Bool)
    case speaking([String])
    /// The frame encryption for this participant works (their key arrived and decrypts) or does not (yet).
    case secured(participant: String, ok: Bool, state: String)
    /// A track appeared or went: the tile's picture may have changed.
    case tracks(participant: String)
    /// After someone else's key was set, the provider's send index was put back to mine (for the diagnostics).
    case sendIndexReset(Int)
}

/// What a group call needs from the media engine. The real one is LiveKit (below); tests use a fake, since simulators cannot make a real call.
@MainActor
protocol GroupCallMedia: AnyObject {
    var onEvent: (@MainActor (GroupMediaEvent) -> Void)? { get set }
    /// Sets another participant's sender key (the frame encryption). Never changes what this phone sends with. Safe before `connect`.
    func setKey(_ key: Data, participant: String, index: Int)
    /// Sets MY sender key and starts sending with it at once (at join, and every time the core renews it because someone left: LIME-112e).
    func setMyKey(_ key: Data, participant: String, index: Int)
    /// Connects to the room with the token, through the given relay (and only through it when `relayOnly`).
    func connect(url: String, token: String, identity: String, iceServers: [IceServer], relayOnly: Bool, microphone: Bool, camera: Bool, lowBandwidth: Bool) async throws
    /// Mobile data: send 480p instead of 720p (restarts the camera with the new size when it is on). Wi-Fi: back to 720p.
    func setLowBandwidth(_ on: Bool) async
    func setMicrophone(_ on: Bool) async
    func setCamera(_ on: Bool) async
    func flipCamera() async
    func disconnect() async
    /// The picture of a participant for the tile (the LiveKit video track), or nil: only the SwiftUI tile looks inside.
    func videoTrack(for participant: String) -> AnyObject?
    /// Frames received so far per remote participant (whether or not anything draws them), for the diagnostics.
    func frameCounts() -> [String: Int]
    /// What the SDK says about each remote camera track, for the diagnostics (subscribed, enabled, muted, decoder frames per second, size, dropped).
    func trackDetails() -> [String: String]
    /// What this phone's own camera is doing, for the diagnostics (LIME-171): the capture, and each simulcast layer's size, rate, limit and bitrate.
    func sendDetails() -> String
}

extension GroupCallMedia {
    func frameCounts() -> [String: Int] { [:] }
    func trackDetails() -> [String: String] { [:] }
    func sendDetails() -> String { "" }
}

/// Counts a remote video track's frames and draws nothing (LIME-162: tells "the track flows but nothing draws it" from "the track is not flowing").
final class FrameProbe: NSObject, VideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return frames }
    /// Off: it only counts what other renderers keep subscribed. On (the review's leaver test, when nothing else draws): it keeps the tracks flowing at a
    /// small size so a count of zero means "cannot decrypt", not "nobody asked for the picture".
    nonisolated(unsafe) static var keepsTracksFlowing = false
    @MainActor var isAdaptiveStreamEnabled: Bool { Self.keepsTracksFlowing }
    @MainActor var adaptiveStreamSize: CGSize { Self.keepsTracksFlowing ? CGSize(width: 160, height: 120) : .zero }
    nonisolated func render(frame: VideoFrame) { lock.lock(); frames += 1; lock.unlock() }
}

/// LiveKit's Swift SDK as the group call media engine. Every participant has their own sender key; the SDK's frame encryption uses
/// them, so the SFU forwards ciphertext only. 720p cap, simulcast, adaptive streams (a phone receives only the sizes it shows).
@MainActor
final class LiveKitGroupMedia: NSObject, GroupCallMedia, RoomDelegate {
    var onEvent: (@MainActor (GroupMediaEvent) -> Void)?
    private let keyProvider = BaseKeyProvider(isSharedKey: false)
    private var room: Room?
    private var myIdentity = ""
    private var myKeyIndex: Int32 = 0

    /// Every key is installed in LiveKit's slot 0, whatever index the core gave it (LIME-163). The Swift SDK never tells the frame cryptors which
    /// slot to use (`RTCFrameCryptor.keyIndex` is not reachable), so media is always sent and read with slot 0: a key kept at slot 1, 2, 3 after
    /// someone left was never what frames used, and a phone that rejoined (and was sent only the sender's current key, at its renewed index) found
    /// nothing in slot 0 for them and stayed on "securely connecting" for ever. The core's index still orders the renewals; here the newest key
    /// simply replaces the older one for that person.
    nonisolated static let slot: Int32 = 0

    func setKey(_ key: Data, participant: String, index: Int) {
        keyProvider.setKey(keyData: key, participantId: participant, index: Self.slot)
        // `setKey` moves the provider's one "current index" (what data packets are sealed with): someone else's key must not change it.
        keyProvider.setCurrentKeyIndex(Self.slot)
        if participant != myIdentity, !myIdentity.isEmpty { onEvent?(.sendIndexReset(Int(myKeyIndex))) }
    }

    func setMyKey(_ key: Data, participant: String, index: Int) {
        myIdentity = participant
        myKeyIndex = Int32(index)
        keyProvider.setKey(keyData: key, participantId: participant, index: Self.slot)
        keyProvider.setCurrentKeyIndex(Self.slot)
    }

    private var lowBandwidth = false
    /// Settings → Calls → Low Data Mode (LIME-169): a smaller, slower picture and a bitrate cap going out, the lowest layer asked for coming in.
    private var lowData = CallSettings.shared.lowDataMode
    private var settingsObserver: NSObjectProtocol?

    private var cameraOptions: CameraCaptureOptions {
        let plan = CallVideoPlan.capture(lowData: lowData, cellular: lowBandwidth, group: true)
        return CameraCaptureOptions(dimensions: Dimensions(width: Int32(plan.width), height: Int32(plan.height)), fps: plan.fps)
    }

    /// Low Data Mode: one small layer with a cap. Otherwise three layers (`CallVideoPlan.normalLayers`: 30 / 24 / 20 fps), so a grid cell fed from the
    /// middle or low layer still moves smoothly (LIME-171).
    private var videoPublishOptions: VideoPublishOptions? {
        if lowData, let bitrate = CallVideoPlan.maxBitrate(lowData: true), let fps = CallVideoPlan.maxFps(lowData: true) {
            return VideoPublishOptions(encoding: VideoEncoding(maxBitrate: bitrate, maxFps: fps), simulcast: false)
        }
        guard let high = CallVideoPlan.normalLayers.first else { return nil }
        let lower = CallVideoPlan.normalLayers.dropFirst().map {
            VideoParameters(dimensions: Dimensions(width: Int32($0.width), height: Int32($0.height)), encoding: VideoEncoding(maxBitrate: $0.maxBitrate, maxFps: $0.maxFps))
        }
        return VideoPublishOptions(encoding: VideoEncoding(maxBitrate: high.maxBitrate, maxFps: high.maxFps), simulcast: true, simulcastLayers: Array(lower))
    }

    func connect(url: String, token: String, identity: String, iceServers: [IceServer], relayOnly: Bool, microphone: Bool, camera: Bool, lowBandwidth: Bool) async throws {
        myIdentity = identity
        self.lowBandwidth = lowBandwidth
        lowData = CallSettings.shared.lowDataMode
        let relay = ConnectOptions(
            iceServers: iceServers.map { LiveKit.IceServer(urls: $0.urls, username: $0.username, credential: $0.credential) },
            iceTransportPolicy: relayOnly ? .relay : .all)
        let options = RoomOptions(
            defaultCameraCaptureOptions: cameraOptions,
            defaultVideoPublishOptions: videoPublishOptions ?? VideoPublishOptions(),
            adaptiveStream: true,
            dynacast: true,
            encryptionOptions: EncryptionOptions(keyProvider: keyProvider, encryptionType: .gcm))
        let room = Room(delegate: self, connectOptions: relay, roomOptions: options)
        self.room = room
        try await room.connect(url: url, token: token, connectOptions: relay, roomOptions: options)
        if microphone { _ = try? await room.localParticipant.setMicrophone(enabled: true) }
        if camera { _ = try? await room.localParticipant.setCamera(enabled: true, captureOptions: cameraOptions, publishOptions: videoPublishOptions) }
        applyPlaybackSettings()
        settingsObserver = NotificationCenter.default.addObserver(forName: CallSettings.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.settingsChanged() }
        }
    }

    /// A change in Settings → Calls reaches the call that is running.
    private func settingsChanged() async {
        let wanted = CallSettings.shared.lowDataMode
        if wanted != lowData {
            lowData = wanted
            await republishCamera()
        }
        applyPlaybackSettings()
    }

    /// The others' voices at the chosen volume, and (Low Data Mode) the lowest layer and rate of their video. Also for people who join later.
    private func applyPlaybackSettings() {
        guard let room else { return }
        let volume = CallSettings.shared.volume
        for participant in room.remoteParticipants.values {
            for publication in participant.trackPublications.values {
                guard let remote = publication as? RemoteTrackPublication else { continue }
                if let audio = remote.track as? RemoteAudioTrack { audio.volume = volume }
                if remote.kind == .video, remote.source == .camera {
                    let low = lowData
                    let quality: VideoQuality = low ? .low : .high
                    Task {
                        try? await remote.set(videoQuality: quality)
                        if low { try? await remote.set(preferredFPS: 15) }
                    }
                }
            }
        }
    }

    /// A new capture size and publish limits need a new capture: off and on again (a brief gap for the others).
    private func republishCamera() async {
        guard let participant = room?.localParticipant, participant.isCameraEnabled() else { return }
        _ = try? await participant.setCamera(enabled: false)
        _ = try? await participant.setCamera(enabled: true, captureOptions: cameraOptions, publishOptions: videoPublishOptions)
    }

    func setMicrophone(_ on: Bool) async { _ = try? await room?.localParticipant.setMicrophone(enabled: on) }
    func setCamera(_ on: Bool) async { _ = try? await room?.localParticipant.setCamera(enabled: on, captureOptions: on ? cameraOptions : nil, publishOptions: on ? videoPublishOptions : nil) }

    func setLowBandwidth(_ on: Bool) async {
        guard on != lowBandwidth else { return }
        lowBandwidth = on
        await republishCamera()
    }

    func flipCamera() async {
        guard let track = room?.localParticipant.firstCameraPublication?.track as? LocalVideoTrack,
              let capturer = track.capturer as? CameraCapturer else { return }
        _ = try? await capturer.switchCameraPosition()
    }

    func disconnect() async {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
        await room?.disconnect()
        room = nil
    }

    private var probes: [String: (sid: String, probe: FrameProbe)] = [:]

    func frameCounts() -> [String: Int] {
        guard let room else { return [:] }
        var out: [String: Int] = [:]
        for (key, participant) in room.remoteParticipants {
            let id = key.stringValue
            guard let track = participant.firstCameraVideoTrack else { continue }
            let sid = track.sid?.stringValue ?? ""
            if probes[id]?.sid != sid {
                let probe = FrameProbe()
                probes[id] = (sid, probe)
                DispatchQueue.global(qos: .utility).async { track.add(videoRenderer: probe) }
                Task { await track.set(reportStatistics: true) }
            }
            out[id] = probes[id]?.probe.count ?? 0
        }
        return out
    }

    func trackDetails() -> [String: String] {
        guard let room else { return [:] }
        var out: [String: String] = [:]
        for (key, participant) in room.remoteParticipants {
            guard let publication = participant.firstCameraPublication as? RemoteTrackPublication else { continue }
            var text = "sub=\(publication.isSubscribed ? 1 : 0) on=\(publication.isEnabled ? 1 : 0) muted=\(publication.isMuted ? 1 : 0)"
            if let inbound = publication.track?.statistics?.inboundRtpStream.first {
                text += " dec=\(inbound.framesDecoded.map(String.init) ?? "-") drop=\(inbound.framesDropped.map(String.init) ?? "-")"
                text += " pkts=\(inbound.packetsReceived.map(String.init) ?? "-") bytes=\(inbound.bytesReceived.map(String.init) ?? "-")"
                text += " sdkfps=\(inbound.framesPerSecond.map { String(format: "%.0f", $0) } ?? "-") size=\(inbound.frameWidth.map(String.init) ?? "-")x\(inbound.frameHeight.map(String.init) ?? "-")"
                text += " lost=\(inbound.packetsLost.map(String.init) ?? "-") freeze=\(inbound.freezeCount.map(String.init) ?? "-") jit=\(inbound.jitter.map { String(format: "%.0fms", $0 * 1000) } ?? "-")"
            }
            out[key.stringValue] = text
        }
        return out
    }

    func sendDetails() -> String {
        guard let track = room?.localParticipant.firstCameraPublication?.track as? LocalVideoTrack, let stats = track.statistics else { return "" }
        var parts: [String] = []
        if let source = stats.videoSource.first {
            parts.append("capture=\(source.width.map(String.init) ?? "-")x\(source.height.map(String.init) ?? "-")@\(source.framesPerSecond.map { String(format: "%.0f", $0) } ?? "-")")
        }
        for layer in stats.outboundRtpStream.sorted(by: { ($0.frameWidth ?? 0) > ($1.frameWidth ?? 0) }) {
            let size = "\(layer.frameWidth.map(String.init) ?? "-")x\(layer.frameHeight.map(String.init) ?? "-")"
            let fps = layer.framesPerSecond.map { String(format: "%.0f", $0) } ?? "-"
            let target = layer.targetBitrate.map { String(format: "%.0fk", $0 / 1000) } ?? "-"
            parts.append("[\(layer.rid ?? "-") \(size)@\(fps) enc=\(layer.framesEncoded.map(String.init) ?? "-") sent=\(layer.framesSent.map(String.init) ?? "-") limit=\(layer.qualityLimitationReason?.rawValue ?? "-") tgt=\(target)]")
        }
        if let remote = stats.remoteInboundRtpStream.first {
            parts.append("rtt=\(remote.roundTripTime.map { String(format: "%.0fms", $0 * 1000) } ?? "-") lost=\(remote.fractionLost.map { String(format: "%.2f", $0) } ?? "-")")
        }
        if let pair = stats.iceCandidatePair.first(where: { $0.nominated == true }) {
            parts.append("avail=\(pair.availableOutgoingBitrate.map { String(format: "%.0fk", $0 / 1000) } ?? "-")")
        }
        return parts.joined(separator: " ")
    }

    func videoTrack(for participant: String) -> AnyObject? {
        guard let room else { return nil }
        if participant == myIdentity { return room.localParticipant.firstCameraVideoTrack ?? (room.localParticipant.firstCameraPublication?.track as? VideoTrack) }
        return room.remoteParticipants.first { $0.key.stringValue == participant }?.value.firstCameraVideoTrack
    }

    // MARK: RoomDelegate (called on LiveKit's own queues; each hop is to the main actor)

    private func emit(_ event: GroupMediaEvent) { onEvent?(event) }

    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        let connected = connectionState == .connected
        let disconnected = connectionState == .disconnected
        guard connected || disconnected else { return }
        Task { @MainActor in self.emit(.connection(connected: connected, error: nil)) }
    }

    nonisolated func room(_ room: Room, didFailToConnectWithError error: LiveKitError?) {
        let text = error.map { "\($0)" } ?? "failed"
        Task { @MainActor in self.emit(.connection(connected: false, error: text)) }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        guard let id = participant.identity?.stringValue else { return }
        Task { @MainActor in self.emit(.participantConnected(id)) }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        guard let id = participant.identity?.stringValue else { return }
        Task { @MainActor in self.emit(.participantDisconnected(id)) }
    }

    nonisolated func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) {
        guard let id = participant.identity?.stringValue else { return }
        let source = trackPublication.source
        Task { @MainActor in
            if source == .microphone { self.emit(.microphone(participant: id, muted: isMuted)) }
            if source == .camera { self.emit(.camera(participant: id, on: !isMuted)); self.emit(.tracks(participant: id)) }
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        guard let id = participant.identity?.stringValue else { return }
        let source = publication.source
        let muted = publication.isMuted
        Task { @MainActor in
            self.applyPlaybackSettings()   // a voice or a picture that arrives after the call began gets the settings too
            if source == .camera { self.emit(.camera(participant: id, on: !muted)) }
            if source == .microphone { self.emit(.microphone(participant: id, muted: muted)) }
            self.emit(.tracks(participant: id))
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        guard let id = participant.identity?.stringValue else { return }
        Task { @MainActor in self.emit(.tracks(participant: id)) }
    }

    nonisolated func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        guard let id = participant.identity?.stringValue else { return }
        let source = publication.source
        let track = publication.track
        Task { @MainActor in
            // Statistics on my own camera: the numbers the call diagnostics report (LIME-171).
            if source == .camera { await track?.set(reportStatistics: true) }
            if source == .camera { self.emit(.camera(participant: id, on: true)) }
            self.emit(.tracks(participant: id))
        }
    }

    nonisolated func room(_ room: Room, participant: LocalParticipant, didUnpublishTrack publication: LocalTrackPublication) {
        guard let id = participant.identity?.stringValue else { return }
        let source = publication.source
        Task { @MainActor in
            if source == .camera { self.emit(.camera(participant: id, on: false)) }
            self.emit(.tracks(participant: id))
        }
    }

    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        let ids = participants.compactMap { $0.identity?.stringValue }
        Task { @MainActor in self.emit(.speaking(ids)) }
    }

    nonisolated func room(_ room: Room, trackPublication: TrackPublication, didUpdateE2EEState state: E2EEState) {
        let sid = trackPublication.sid
        let owner = ([room.localParticipant] as [Participant] + Array(room.remoteParticipants.values)).first { $0.trackPublications.keys.contains(sid) }
        guard let id = owner?.identity?.stringValue else { return }
        let ok = state == .ok || state == .key_ratcheted
        let name = state.toString()
        Task { @MainActor in self.emit(.secured(participant: id, ok: ok, state: name)) }
    }
}
