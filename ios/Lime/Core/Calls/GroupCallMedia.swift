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

    func setKey(_ key: Data, participant: String, index: Int) {
        keyProvider.setKey(keyData: key, participantId: participant, index: Int32(index))
        // `setKey` moves the provider's one "current index" (what this phone sends with): someone else's key must not change it.
        keyProvider.setCurrentKeyIndex(myKeyIndex)
        if participant != myIdentity, !myIdentity.isEmpty { onEvent?(.sendIndexReset(Int(myKeyIndex))) }
    }

    func setMyKey(_ key: Data, participant: String, index: Int) {
        myIdentity = participant
        myKeyIndex = Int32(index)
        keyProvider.setKey(keyData: key, participantId: participant, index: Int32(index))
        keyProvider.setCurrentKeyIndex(myKeyIndex)
    }

    private var lowBandwidth = false
    private var cameraOptions: CameraCaptureOptions {
        lowBandwidth ? CameraCaptureOptions(dimensions: Dimensions(width: 848, height: 480), fps: 24) : CameraCaptureOptions(dimensions: .h720_169, fps: 30)
    }

    func connect(url: String, token: String, identity: String, iceServers: [IceServer], relayOnly: Bool, microphone: Bool, camera: Bool, lowBandwidth: Bool) async throws {
        myIdentity = identity
        self.lowBandwidth = lowBandwidth
        let relay = ConnectOptions(
            iceServers: iceServers.map { LiveKit.IceServer(urls: $0.urls, username: $0.username, credential: $0.credential) },
            iceTransportPolicy: relayOnly ? .relay : .all)
        let options = RoomOptions(
            defaultCameraCaptureOptions: cameraOptions,
            adaptiveStream: true,
            dynacast: true,
            encryptionOptions: EncryptionOptions(keyProvider: keyProvider, encryptionType: .gcm))
        let room = Room(delegate: self, connectOptions: relay, roomOptions: options)
        self.room = room
        try await room.connect(url: url, token: token, connectOptions: relay, roomOptions: options)
        if microphone { _ = try? await room.localParticipant.setMicrophone(enabled: true) }
        if camera { _ = try? await room.localParticipant.setCamera(enabled: true, captureOptions: cameraOptions) }
    }

    func setMicrophone(_ on: Bool) async { _ = try? await room?.localParticipant.setMicrophone(enabled: on) }
    func setCamera(_ on: Bool) async { _ = try? await room?.localParticipant.setCamera(enabled: on, captureOptions: on ? cameraOptions : nil) }

    func setLowBandwidth(_ on: Bool) async {
        guard on != lowBandwidth else { return }
        lowBandwidth = on
        guard let participant = room?.localParticipant, participant.isCameraEnabled() else { return }
        // A new capture size needs a new capture: off and on again (a brief gap for the others).
        _ = try? await participant.setCamera(enabled: false)
        _ = try? await participant.setCamera(enabled: true, captureOptions: cameraOptions)
    }

    func flipCamera() async {
        guard let track = room?.localParticipant.firstCameraPublication?.track as? LocalVideoTrack,
              let capturer = track.capturer as? CameraCapturer else { return }
        _ = try? await capturer.switchCameraPosition()
    }

    func disconnect() async {
        await room?.disconnect()
        room = nil
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
        Task { @MainActor in
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
