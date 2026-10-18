import AVFoundation
import Foundation
import Observation
import UIKit

/// What a group call needs from LimeCore and the signed-in session. The rules (who may start, join or be sent a key, when keys change,
/// when a call is over) are all in the core; this only asks and obeys. The real one is `StoreGroupCallCore`; tests use a fake.
@MainActor
protocol GroupCallCore: AnyObject {
    func start(conversationID: String, video: Bool) async throws -> GroupCallInfo
    func join(callID: String) async throws -> GroupCallJoin
    func leave(callID: String) async
    func participantGone(callID: String, participant: String) async
    func token(room: String, participant: String) async -> LiveKitToken?
    func iceServers() async -> [IceServer]
    /// Sends what this phone owes the others (starts, joins, keys, leaves); says what went.
    func deliver() async -> GroupCallSendReport?
    /// A tile is stuck without a key: asks its owner to send it again (once per participant per call).
    func requestKey(callID: String, participant: String) async
    func takeEvents() -> [GroupCallEvent]
    func activeCall(conversationID: String) -> GroupCallInfo?
    func title(of conversationID: String) -> String
    /// The call's four-emoji check from everyone's current keys (all held by the core); not ready until every person's key is in.
    func emojiState(callID: String) -> GroupCallEmojiState?
    /// A person chose this group's name (renamed it, or typed another than the default): the core decides, so every phone agrees.
    func isCustomNamed(conversationID: String) -> Bool
}

/// One group call at a time (LIME-112b). A thin adapter: LimeCore decides everything about the call and its keys; LiveKit carries the
/// media (end to end encrypted with a key per sender, so the server only forwards ciphertext); CallKit rings and shows the system call.
@MainActor
@Observable
final class GroupCallManager {
    enum Phase: Equatable { case idle, connecting, active }

    /// One person's tile.
    struct Tile: Identifiable, Equatable {
        let id: String            // the participant (the random LiveKit identity)
        var userID: String
        var name: String
        var isMe: Bool
        var muted = false
        var cameraOn = false
        var speaking = false
        /// Their key has arrived and their media decrypts: until then the tile says "Connecting securely…" and shows no picture.
        var secured = false
    }

    /// A group call that is ringing here.
    struct Incoming: Equatable {
        let callID: String
        let conversationID: String
        let title: String
        let callerName: String
        let video: Bool
    }

    /// A call someone started in a group while lime is open but elsewhere (no ring: a big group, or not rung): the invite sheet.
    struct Invite: Equatable {
        let callID: String
        let conversationID: String
        let title: String
        let video: Bool
    }

    private(set) var phase: Phase = .idle
    private(set) var callID = ""
    private(set) var conversationID = ""
    private(set) var title = ""
    private(set) var video = false
    private(set) var tiles: [Tile] = []
    /// The four-emoji check (LIME-147): from everyone's current media keys; empty while any person's key has not arrived (`emojiWaiting`).
    private(set) var verificationEmoji: [CallEmoji] = []
    private(set) var emojiWaiting = false
    /// The group's name was chosen by a person (LIME-147b): then it names the call; otherwise the people in it do.
    private(set) var groupNameIsCustom = false
    private(set) var muted = false
    private(set) var cameraOn = false
    private(set) var speakerOn = false
    private(set) var startedAt: Date?
    private(set) var incoming: Incoming?
    private(set) var invite: Invite?
    /// Bumped when a tile's picture may have changed (the SwiftUI tile looks the track up again).
    private(set) var picturesVersion = 0
    /// Bumped whenever a call event arrives (the chat's Join pill and bubble read the core again).
    private(set) var changes = 0
    var minimized = false
    var notice: String?
    /// More than 12 people: speaker view and camera off by default.
    var speakerViewByDefault: Bool { tiles.count > Self.gridLimit }
    static let gridLimit = 12

    @ObservationIgnored let core: GroupCallCore
    @ObservationIgnored private let system: CallSystem
    @ObservationIgnored private let makeMedia: () -> any GroupCallMedia
    @ObservationIgnored private let quietReason: () -> CallQuietReason?
    @ObservationIgnored private let isOtherCallActive: () -> Bool
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let diag = CallDiagnostics.shared
    @ObservationIgnored var alwaysRelay: () -> Bool = { false }
    /// Fetches the mailbox now (set by the app); once a second while a call is on, in case a nudge is missed.
    @ObservationIgnored var fetchNow: (() async -> Void)?
    /// A call ended or I left (the chat line changed, so the app reloads).
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var ringSeconds: Double = 45
    @ObservationIgnored private var media: (any GroupCallMedia)?
    @ObservationIgnored private var poller: Task<Void, Never>?
    @ObservationIgnored private var probe: Task<Void, Never>?
    @ObservationIgnored private var ringTimeout: Task<Void, Never>?
    @ObservationIgnored private var myParticipant = ""
    /// The index of the key this phone sends with, as the core says (set at join and at every renewal): for the guard.
    @ObservationIgnored private var expectedSendIndex = 0
    @ObservationIgnored private var keyed: Set<String> = []
    @ObservationIgnored private var decrypting: [String: Bool] = [:]
    @ObservationIgnored private var busy = false
    /// Who is in each live call that this phone has heard about (from the core's join and leave events), by participant.
    @ObservationIgnored private var roster: [String: [String: Person]] = [:]
    /// The person's chosen layout (Grid or Speaker), kept on this phone; nil until they choose (then the default for the call's size applies).
    @ObservationIgnored private let layoutDefaults: UserDefaults
    static let layoutKey = "lime.groupCallLayout"
    private(set) var chosenLayout: GroupCallLayout.Mode?
    /// Whether that group's chat is the screen the person is looking at (set by the app): no invite sheet over it.
    @ObservationIgnored var isViewingChat: (String) -> Bool = { _ in false }
    /// Who I am (the name and photo on my own tile; never "You").
    @ObservationIgnored private let me: () -> Person?
    /// How the group looks (its emoji and members) for the window's group picture; set by the app.
    /// Who I am, for the group's picture (it includes me: LIME-150).
    @ObservationIgnored var meProvider: () -> Person = { SampleData.me }
    @ObservationIgnored var groupLook: (String) -> (emoji: String?, members: [Person])? = { _ in nil }
    /// System Picture in Picture of the active speaker (a video call); nil in tests and the demo.
    @ObservationIgnored var makePictureInPicture: (() -> (any GroupPiP)?)?
    @ObservationIgnored private var pip: (any GroupPiP)?
    private(set) var pictureInPictureActive = false
    /// One beat before the window's second try when it is not possible at first (LIME-112d).
    /// How long a minimise waits for the system to say the window is possible before it rebuilds the controller, and then again before it falls back.
    @ObservationIgnored var pipWait: Duration = .seconds(1)
    /// The one anchor view for the whole call (LIME-112e): system Picture in Picture opens from it. Each new call screen hosts this same view, so the
    /// controller's content source never changes (the system ignores a changed one on a live controller).
    @ObservationIgnored private var anchorView: UIView?
    @ObservationIgnored private let network: GroupCallNetwork?
    /// Who the window shows now, and since when (a new speaker waits `speakerHoldSeconds` so it does not flicker), and the last other person who spoke.
    @ObservationIgnored private var pipSubject: String?
    @ObservationIgnored private var pipSubjectSince = Date.distantPast
    @ObservationIgnored private var lastOtherSpeaker: String?
    /// The other people by how lately they spoke, newest first (the minimised grid shows the 3 most recent when there are 5 or more).
    @ObservationIgnored private var recentSpeakers: [String] = []
    /// The minimised view (LIME-150): the person's choice (remembered), else the grid up to 4 other people and the speaker above.
    static let pipViewKey = "lime.pipView"
    private(set) var pipViewChoice: PiPGridPlan.View?
    /// The heat guard (6b): the grid keeps only the speaker live while the phone is hot, and goes back after 2 calm minutes.
    @ObservationIgnored private var heat = PiPHeatGuard()
    @ObservationIgnored var thermalState: () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }
    @ObservationIgnored private var heatRecheck: Task<Void, Never>?
    @ObservationIgnored private var lastGridLog = ""
    @ObservationIgnored var speakerHoldSeconds: Double = 2
    /// Minimise was pressed: the app opens the group's chat (so the person can type while talking).
    @ObservationIgnored var onMinimize: ((String) -> Void)?
    /// When each remote tile was first seen without a working key, and who has been asked for it again.
    @ObservationIgnored private var stuckSince: [String: Date] = [:]
    @ObservationIgnored private var asked: Set<String> = []
    /// A tile still without a key after this long asks its owner once to send it again.
    @ObservationIgnored var keyRetrySeconds: Double = 5

    init(core: GroupCallCore, system: CallSystem, quietReason: @escaping () -> CallQuietReason? = { nil },
         isOtherCallActive: @escaping () -> Bool = { false }, now: @escaping () -> Date = Date.init,
         me: @escaping () -> Person? = { nil }, network: GroupCallNetwork? = nil, layoutDefaults: UserDefaults = .standard,
         makeMedia: @escaping () -> any GroupCallMedia) {
        self.core = core
        self.layoutDefaults = layoutDefaults
        self.chosenLayout = layoutDefaults.string(forKey: Self.layoutKey).flatMap(GroupCallLayout.Mode.init(rawValue:))
        self.pipViewChoice = layoutDefaults.string(forKey: Self.pipViewKey).flatMap(PiPGridPlan.View.init(rawValue:))
        self.me = me
        self.network = network
        self.system = system
        self.quietReason = quietReason
        self.isOtherCallActive = isOtherCallActive
        self.now = now
        self.makeMedia = makeMedia
        // The system call screen's buttons also reach the one-to-one calls: each handler passes on what is not about a group call.
        let answer = system.onAnswer, end = system.onEnd, mute = system.onMute
        system.onAnswer = { [weak self] id in
            Task { @MainActor in
                if let self, self.incoming.map({ Self.systemID($0.callID) }) == id { await self.acceptIncoming(fromSystem: true) } else { answer?(id) }
            }
        }
        system.onEnd = { [weak self] id in
            Task { @MainActor in
                if let self, id == Self.systemID(self.callID), self.phase != .idle { await self.leave() }
                else if let self, self.incoming.map({ Self.systemID($0.callID) }) == id { self.dismissIncoming() }
                else { end?(id) }
            }
        }
        system.onMute = { [weak self] id, muted in
            Task { @MainActor in
                if let self, id == Self.systemID(self.callID), self.phase != .idle { await self.setMuted(muted) } else { mute?(id, muted) }
            }
        }
    }

    var inCall: Bool { phase != .idle }

    /// Grid or Speaker: what the person chose, else the default for this many people in this container.
    func effectiveLayout(in size: CGSize) -> GroupCallLayout.Mode {
        chosenLayout ?? GroupCallLayout.defaultMode(people: tiles.count, in: size)
    }

    /// The layout switch: remembered on this phone.
    func chooseLayout(_ mode: GroupCallLayout.Mode) {
        chosenLayout = mode
        layoutDefaults.set(mode.rawValue, forKey: Self.layoutKey)
    }

    /// The minimised window's view: remembered on this phone.
    func choosePiPView(_ view: PiPGridPlan.View) {
        pipViewChoice = view
        layoutDefaults.set(view.rawValue, forKey: Self.pipViewKey)
        refreshPiP()
    }

    /// The view the minimised window shows now.
    var pipView: PiPGridPlan.View { PiPGridPlan.view(choice: pipViewChoice, others: tiles.filter { !$0.isMe }.count) }

    /// Who is large in the speaker layout: the person speaking now (not me), else the last other person who spoke, else the first other person.
    var spotlightID: String? {
        let others = tiles.filter { !$0.isMe }
        if let speaking = others.first(where: \.speaking) { return speaking.id }
        if let last = lastOtherSpeaker, others.contains(where: { $0.id == last }) { return last }
        return others.first?.id
    }

    /// The picture of a participant for the tile (the media engine's video track), or nil. Only the SwiftUI tile looks inside.
    func videoTrack(for participant: String) -> AnyObject? { media?.videoTrack(for: participant) }

    /// The id CallKit knows a group call by: the first 128 bits of the call id, as a UUID.
    nonisolated static func systemID(_ callID: String) -> String {
        let hex = Array(callID.prefix(32))
        guard hex.count == 32 else { return callID }
        let text = String(hex)
        return "\(text.prefix(8))-\(text.dropFirst(8).prefix(4))-\(text.dropFirst(12).prefix(4))-\(text.dropFirst(16).prefix(4))-\(text.dropFirst(20))"
    }

    // MARK: Starting and joining

    /// Starts a call in a group (or joins the one that is on) and connects. `false` when another call is going or the core refuses.
    @discardableResult
    func start(conversationID: String, title: String, video: Bool) async -> Bool {
        guard phase == .idle, !busy, !isOtherCallActive() else { notice = "End your current call to start another."; return false }
        busy = true
        defer { busy = false }
        do {
            let info = try await core.start(conversationID: conversationID, video: video)
            diag.log("group call: start video=\(video), \(info.participantCount) in it")
            return await joinInternal(info: info, title: title, camera: video)
        } catch {
            diag.log("group call: start refused (\(error))")
            notice = "Couldn\u{2019}t start the call. Check that you\u{2019}re still in this group."
            return false
        }
    }

    /// Joins a live call (the chat's Join, a ring answered).
    @discardableResult
    func join(callID: String, conversationID: String, title: String, video: Bool, withVideo: Bool? = nil) async -> Bool {
        guard phase == .idle, !busy else { return false }
        if isOtherCallActive() { notice = "End your current call to join this one."; return false }
        busy = true
        defer { busy = false }
        dismissIncoming()
        let info = core.activeCall(conversationID: conversationID)
        guard let info, info.callId == callID else { notice = "That call has ended."; return false }
        // Joining as voice publishes no camera until the camera is turned on in the call; by default a join is as the call was started.
        return await joinInternal(info: info, title: title, camera: withVideo ?? info.video)
    }

    private func joinInternal(info: GroupCallInfo, title: String, camera wantsCamera: Bool) async -> Bool {
        let joined: GroupCallJoin
        do { joined = try await core.join(callID: info.callId) } catch {
            diag.log("group call: join refused (\(error))")
            notice = "Couldn\u{2019}t join the call."
            return false
        }
        invite = nil
        for other in joined.participants where other.userId != "" { roster[info.callId, default: [:]][other.participant] = Person(id: other.userId, name: other.name) }
        callID = info.callId
        conversationID = info.conversationId
        groupNameIsCustom = core.isCustomNamed(conversationID: info.conversationId)
        self.title = title
        video = info.video
        phase = .connecting
        startedAt = nil
        muted = false
        speakerOn = false
        keyed = []
        decrypting = [:]
        stuckSince = [:]
        asked = []
        myParticipant = joined.participant
        refreshEmoji()
        let myself = me()
        tiles = [Tile(id: joined.participant, userID: myself?.id ?? "", name: myself?.name ?? "Me", isMe: true, secured: true)]
        for other in joined.participants { tiles.append(Tile(id: other.participant, userID: other.userId, name: other.name, isMe: false)) }
        // Many people: speaker view, and the camera starts off.
        cameraOn = wantsCamera && info.video && tiles.count <= Self.gridLimit
        diag.log("group call: joined as \(joined.participant.prefix(4))…, \(joined.participants.count) already in, key index \(joined.keyIndex)")
        system.reportOutgoing(callID: Self.systemID(callID), name: title, video: video)
        let media = makeMedia()
        self.media = media
        media.onEvent = { [weak self] event in self?.handle(media: event) }
        // The key is raw bytes from the core (never text: the core's base64 has no padding, which Swift's decoder refuses).
        expectedSendIndex = Int(joined.keyIndex)
        media.setMyKey(joined.key, participant: joined.participant, index: Int(joined.keyIndex))
        diag.log("group call: setKey me \(joined.participant.prefix(4))… index \(joined.keyIndex) (LiveKit identity \(joined.participant.prefix(4))…)")
        startPolling()
        startProbe()
        // My join and my key go out now (they are what the others wait for), while the connection comes up.
        Task { await deliverAndLog() }
        guard let token = await core.token(room: info.room, participant: joined.participant) else {
            diag.log("group call: no token (not configured)")
            notice = "Group calls aren\u{2019}t available yet."
            await finish(notify: true)
            return false
        }
        let servers = await core.iceServers()
        let relay = alwaysRelay()
        if relay && !servers.contains(where: { $0.username != nil }) {
            diag.log("group call: always relay, no relay credentials")
            notice = CallPrivacy.relayUnavailable
            await finish(notify: true)
            return false
        }
        do {
            let low = network?.isCellular ?? false
            if low { diag.log("group call: on mobile data: sending 480p") }
            try await media.connect(url: token.url, token: token.token, identity: joined.participant, iceServers: servers, relayOnly: relay,
                                    microphone: true, camera: cameraOn, lowBandwidth: low)
            network?.onChange = { [weak self] cellular in
                guard let self, self.phase != .idle else { return }
                self.diag.log("group call: network is \(cellular ? "mobile data: 480p" : "Wi-Fi: 720p")")
                Task { await self.media?.setLowBandwidth(cellular) }
            }
            network?.start()
        } catch {
            diag.log("group call: connect failed (\(error))")
            if phase != .idle { notice = "Couldn\u{2019}t connect to the call."; await finish(notify: true) }
            return false
        }
        return true
    }

    // MARK: Ringing

    /// The incoming ring was answered (lime's Join or the system's Accept).
    func acceptIncoming(fromSystem: Bool = false, withVideo: Bool? = nil) async {
        guard let ring = incoming else { return }
        if !fromSystem { system.requestAnswer(callID: Self.systemID(ring.callID)) }
        // The system's Answer is as the call was started; the in-app banner can say video or voice.
        _ = await join(callID: ring.callID, conversationID: ring.conversationID, title: ring.title, video: ring.video, withVideo: withVideo)
    }

    func declineIncoming() {
        guard let ring = incoming else { return }
        system.reportEnded(callID: Self.systemID(ring.callID), answeredOrOutgoing: false)
        dismissIncoming()
    }

    func dismissIncoming() {
        ringTimeout?.cancel()
        incoming = nil
    }

    /// A call started in a group of mine and nothing rang for it: if lime is open, idle, not silenced and the person is not already looking at
    /// that chat, a sheet offers Dismiss or Join (only while the call is still live).
    private func offerInvite(for event: GroupCallEvent) {
        guard phase == .idle, incoming == nil, invite == nil, !isOtherCallActive(), quietReason() == nil, !isViewingChat(event.conversationId),
              let live = core.activeCall(conversationID: event.conversationId), live.callId == event.callId else { return }
        invite = Invite(callID: event.callId, conversationID: event.conversationId, title: core.title(of: event.conversationId), video: event.video)
        diag.log("group call: invite sheet")
    }

    func dismissInvite() { invite = nil }

    /// Join from the invite sheet (as the call was started, or as voice).
    func acceptInvite(withVideo: Bool? = nil) async {
        guard let invite else { return }
        self.invite = nil
        _ = await join(callID: invite.callID, conversationID: invite.conversationID, title: invite.title, video: invite.video, withVideo: withVideo)
    }

    /// The call that is on in a group, and who is in it (the people the phone has heard join; the count is the core's).
    func liveSummary(conversationID: String) -> (info: GroupCallInfo, people: [Person])? {
        guard let info = core.activeCall(conversationID: conversationID) else { return nil }
        let people = (roster[info.callId] ?? [:]).values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (info, people)
    }

    private func ring(for event: GroupCallEvent) {
        guard event.ring, phase == .idle, incoming == nil, !isOtherCallActive() else { return }
        if let reason = quietReason() {
            diag.log("group call: silenced (\(reason.rawValue)); the chat line still shows it")
            return
        }
        let title = core.title(of: event.conversationId)
        incoming = Incoming(callID: event.callId, conversationID: event.conversationId, title: title, callerName: event.name, video: event.video)
        diag.log("group call: ringing")
        system.reportIncoming(callID: Self.systemID(event.callId), name: "\(event.name) \u{00B7} \(title)", video: event.video) { [weak self] refusal in
            if let refusal { self?.diag.log("group call: system refused the ring (\(refusal))") }
        }
        ringTimeout?.cancel()
        let id = event.callId
        ringTimeout = Task { [weak self] in
            guard let seconds = self?.ringSeconds else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.incoming?.callID == id else { return }
            self.system.reportEnded(callID: Self.systemID(id), answeredOrOutgoing: false)
            self.incoming = nil
        }
    }

    // MARK: Events from the core

    /// Sends what is owed, then handles what arrived. The app calls this after every fetch; a call also does it once a second.
    func pump() async {
        // Events first: when the core renewed my key, this phone switches to it before the others are sent theirs (LIME-112e).
        handle(core.takeEvents())
        await deliverAndLog()
        checkStuckTiles()
    }

    private func deliverAndLog() async {
        guard let report = await core.deliver(), report.sent > 0 || report.waiting > 0 else { return }
        diag.log("group call: sent \(report.sent) ops (\(report.keysSent) keys, last index \(report.lastKeyIndex)), \(report.waiting) waiting")
    }

    /// A remote tile that has had no working key for `keyRetrySeconds` asks its owner, once, to send it again.
    func checkStuckTiles() {
        guard phase != .idle else { return }
        let current = now()
        for tile in tiles where !tile.isMe {
            if tile.secured {
                stuckSince[tile.id] = nil
            } else if let since = stuckSince[tile.id] {
                if current.timeIntervalSince(since) >= keyRetrySeconds, !asked.contains(tile.id) {
                    asked.insert(tile.id)
                    diag.log("group call: asking \(tile.id.prefix(4))… for their key again")
                    let call = callID, id = tile.id
                    Task { await core.requestKey(callID: call, participant: id); await deliverAndLog() }
                }
            } else {
                stuckSince[tile.id] = current
            }
        }
    }

    /// "Jean, Shem, Lee": the first names of the people in the call, in tile order.
    var peopleNames: String {
        tiles.map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }.joined(separator: ", ")
    }

    /// What names the call on screen (the header pill, the people sheet, the mini player): the group's own name when a person chose it
    /// (renamed, or typed another than the default), else the people in the call.
    var callTitle: String { groupNameIsCustom || tiles.isEmpty ? title : peopleNames }

    /// Asks the core for the emoji again: after every join, leave and key (the keys change when people come and go).
    func refreshEmoji() {
        guard phase != .idle, !callID.isEmpty, let state = core.emojiState(callID: callID) else {
            if !verificationEmoji.isEmpty { verificationEmoji = [] }
            emojiWaiting = false
            return
        }
        if state.emoji != verificationEmoji { verificationEmoji = state.emoji }
        emojiWaiting = !state.ready
    }

    func handle(_ events: [GroupCallEvent]) {
        defer { refreshEmoji() }
        if !events.isEmpty { changes += 1 }
        for event in events {
            // Who is in a call, for the chat's live card and the invite sheet (any call in any of my groups).
            switch event.kind {
            case "joined" where !event.userId.isEmpty:
                roster[event.callId, default: [:]][event.participant] = Person(id: event.userId, name: event.name)
            case "left":
                roster[event.callId]?[event.participant] = nil
            case "ended":
                roster[event.callId] = nil
                if invite?.callID == event.callId { invite = nil }
            default:
                break
            }
            switch event.kind {
            case "started":
                if event.ring { ring(for: event) } else { offerInvite(for: event) }
            case "ended":
                if incoming?.callID == event.callId { system.reportEnded(callID: Self.systemID(event.callId), answeredOrOutgoing: false); dismissIncoming() }
                if event.callId == callID, phase != .idle { Task { await self.finish(notify: true, tellCore: false) } }
                onFinished?()
            case "joined" where event.callId == callID:
                if let index = tiles.firstIndex(where: { $0.id == event.participant }) {
                    tiles[index].userID = event.userId
                    tiles[index].name = event.name
                } else if event.participant != myParticipant {
                    tiles.append(Tile(id: event.participant, userID: event.userId, name: event.name, isMe: false))
                }
            case "left" where event.callId == callID:
                tiles.removeAll { $0.id == event.participant }
                keyed.remove(event.participant)
            case "key" where event.callId == callID:
                guard let key = event.key, key.count == 32 else { diag.log("group call: key from \(event.participant.prefix(4))… is not 32 bytes: ignored"); continue }
                media?.setKey(key, participant: event.participant, index: Int(event.keyIndex))
                keyed.insert(event.participant)
                diag.log("group call: key received from \(event.participant.prefix(4))… (index \(event.keyIndex)) accepted; setKey \(event.participant.prefix(4))… (LiveKit identity \(event.participant.prefix(4))…)")
                diag.log("group call: key installed for \(event.participant.prefix(4))… (core index \(event.keyIndex), media slot \(LiveKitGroupMedia.slot))")
                refreshSecured(event.participant)
            case "my_key" where event.callId == callID:
                // The core renewed MY key because someone left: this phone sends with it from now on (before the others' copies arrive: they keep
                // the old index for frames in flight), so whoever left, and anyone who only ever got the old key, can read nothing new.
                guard let key = event.key, key.count == 32, event.participant == myParticipant else { diag.log("group call: my renewed key is not usable: ignored"); continue }
                expectedSendIndex = Int(event.keyIndex)
                media?.setMyKey(key, participant: myParticipant, index: Int(event.keyIndex))
                diag.log("group call: setKey me \(myParticipant.prefix(4))… index \(event.keyIndex) (renewed: someone left) (LiveKit identity \(myParticipant.prefix(4))…)")
            case "key_rejected" where event.callId == callID || callID.isEmpty:
                diag.log("group call: key from \(event.participant.prefix(4))… rejected: \(event.reason)")
            default:
                break
            }
        }
    }

    // MARK: Events from the media engine

    func handle(media event: GroupMediaEvent) {
        switch event {
        case .connection(let connected, let error):
            if connected, phase == .connecting {
                phase = .active
                startedAt = now()
                system.reportConnected(callID: Self.systemID(callID))
                diag.log("group call: connected")
            } else if !connected, phase != .idle {
                diag.log("group call: connection lost \(error ?? "")")
                if error != nil || phase == .active { notice = "The call connection was lost."; Task { await self.finish(notify: true) } }
            }
        case .participantConnected(let id):
            if !tiles.contains(where: { $0.id == id }) { tiles.append(Tile(id: id, userID: "", name: "Someone", isMe: false)) }
        case .participantDisconnected(let id):
            tiles.removeAll { $0.id == id }
            keyed.remove(id)
            let call = callID
            // The core renews my key when someone is gone: take that event first (this phone switches to the new key), then send it to the others.
            Task { await core.participantGone(callID: call, participant: id); handle(core.takeEvents()); _ = await core.deliver(); refreshEmoji() }
        case .microphone(let id, let muted):
            update(id) { $0.muted = muted }
        case .camera(let id, let on):
            update(id) { $0.cameraOn = on }
            refreshPiP()
        case .speaking(let ids):
            for index in tiles.indices { tiles[index].speaking = ids.contains(tiles[index].id) }
            if let other = tiles.first(where: { $0.speaking && !$0.isMe }) { lastOtherSpeaker = other.id }
            for other in tiles where other.speaking && !other.isMe { recentSpeakers.removeAll { $0 == other.id }; recentSpeakers.insert(other.id, at: 0) }
            refreshPiP()
        case .secured(let id, let ok, let state):
            diag.log("group call: frame cryptor \(id.prefix(4))… \(state)")
            if id == myParticipant, !ok { diag.log("group call: WARNING my own frames report \(state): the key this phone sends with may not be the current one") }
            decrypting[id] = ok
            refreshSecured(id)
        case .tracks:
            picturesVersion += 1
            refreshPiP()
        case .sendIndexReset(let index):
            diag.log("group call: send index reset to \(index)")
            // The guard: what this phone encrypts with must be the index the core says is current.
            if index != expectedSendIndex { diag.log("group call: WARNING this phone sends with index \(index) but the core's current index is \(expectedSendIndex)") }
        }
    }

    private func update(_ id: String, _ change: (inout Tile) -> Void) {
        if let index = tiles.firstIndex(where: { $0.id == id }) { change(&tiles[index]) }
    }

    /// A person's picture shows only once their key has arrived and their media decrypts.
    private func refreshSecured(_ id: String) {
        update(id) { tile in
            if !tile.isMe { tile.secured = keyed.contains(id) && decrypting[id] != false }
        }
        picturesVersion += 1
        refreshPiP()
    }

    // MARK: Picture in Picture (LIME-112c)

    /// The call's one anchor view (made on first use, dropped when the call ends): the call screen hosts it, whatever number of times it is rebuilt.
    func pictureInPictureAnchor() -> UIView {
        if let anchorView { return anchorView }
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        anchorView = view
        return view
    }

    /// Makes the window ready for a video call (the call screen's anchor view must be on screen).
    func preparePictureInPicture(sourceView: UIView) {
        guard video, inCall else { return }
        if pip == nil, let made = makePictureInPicture?() {
            pip = made
            made.onStarted = { [weak self] in self?.pictureInPictureActive = true; self?.minimized = true; self?.refreshPiP() }
            made.onStopped = { [weak self] in self?.pictureInPictureActive = false }
            made.onRestore = { [weak self] in self?.pictureInPictureActive = false; self?.minimized = false }
            made.onFailed = { [weak self] in self?.minimized = true }
        }
        pip?.prepare(sourceView: sourceView, subject: pipSubjectValue(for: chooseSubject()))
        refreshPiP()
    }

    /// Minimise (the call screen's button): the group's chat opens so the person can type while talking; a video call floats in system
    /// Picture in Picture, a voice call (or a video call that cannot) leaves the full screen and keeps the slim bar to return by.
    func minimize() {
        onMinimize?(conversationID)
        guard video, phase == .active, let pip else { minimized = true; return }
        if pip.isPossible { pip.start(); return }
        // Not possible yet (the call screen may still be settling): wait for the system's own "possible" (observed, not guessed) for up to a
        // second; if it never comes, rebuild the controller on the current anchor and wait once more; then fall back to the mini player.
        diag.log("group pip not possible: \(pip.notPossibleReason); waiting for it")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let began = self.now()
            var possible = await pip.waitUntilPossible(timeout: self.pipWait)
            self.diag.log("group pip waited \(Int(self.now().timeIntervalSince(began) * 1000)) ms: \(possible ? "possible" : "still not possible: \(pip.notPossibleReason)")")
            if !possible {
                pip.rebuild()
                possible = await pip.waitUntilPossible(timeout: self.pipWait)
            }
            guard self.inCall, !self.minimized else { return }
            if possible { pip.start() } else { self.diag.log("group pip not possible after a rebuild: \(pip.notPossibleReason)"); self.minimized = true }
        }
    }

    /// Who the window shows: the person speaking (not me), kept for `speakerHoldSeconds` before it moves to someone else; when nobody else
    /// is speaking the one shown stays, else the last other speaker, else the first other person; nobody else yet: the group itself.
    private func chooseSubject() -> String? {
        let others = tiles.filter { !$0.isMe }
        guard !others.isEmpty else { return nil }
        let current = others.first { $0.id == pipSubject }
        let speaking = others.first { $0.speaking }
        if let speaking, speaking.id != current?.id {
            if current == nil || now().timeIntervalSince(pipSubjectSince) >= speakerHoldSeconds { return speaking.id }
        }
        if let current { return current.id }
        if let last = lastOtherSpeaker, others.contains(where: { $0.id == last }) { return last }
        return (others.first { $0.secured && $0.cameraOn } ?? others[0]).id
    }

    private func pipSubjectValue(for id: String?) -> PiPSubject {
        guard let id, let tile = tiles.first(where: { $0.id == id }) else {
            // Nobody else yet: the group itself, as the chat shows it (photo, emoji, or its members' photos).
            let look = groupLook(conversationID)
            return .group(id: conversationID, name: title, emoji: look?.emoji, members: look?.members ?? [], me: meProvider())
        }
        return .person(Person(id: tile.userID.isEmpty ? tile.id : tile.userID, name: tile.name))
    }

    /// Points the window at the right person with the right picture (their video, or their photo when their camera is off or their key
    /// has not arrived: never a black window).
    func refreshPiP() {
        guard let pip else { return }
        let id = chooseSubject()
        if id != pipSubject { pipSubject = id; pipSubjectSince = now() }
        let tile = tiles.first { $0.id == id }
        let pictureShowing = (tile?.secured ?? false) && (tile?.cameraOn ?? false) && video
        let showGrid = video && pipView == .grid && !tiles.filter { !$0.isMe }.isEmpty
        if !showGrid {
            pip.show(subject: pipSubjectValue(for: id), track: id.flatMap { media?.videoTrack(for: $0) }, pictureShowing: pictureShowing)
            pip.showGrid([])
            return
        }
        // The grid: the speaker window's own single picture is let go (no second sink on the same track), the cells draw instead.
        pip.show(subject: pipSubjectValue(for: id), track: nil, pictureShowing: false)
        let thermal = thermalState()
        heat.update(thermal: thermal, now: now())
        let people = tiles.map { PiPGridPlan.Person(id: $0.id, name: $0.name, isMe: $0.isMe, speaking: $0.speaking, hasPicture: $0.secured && $0.cameraOn) }
        let cells = PiPGridPlan.cells(people: people, recent: recentSpeakers, speakerID: id, allLive: !heat.reduced)
        let displays = cells.map { cell -> PiPGridDisplay in
            let tile = tiles.first { $0.id == cell.id }
            let person: Person? = cell.isMe ? meProvider() : tile.map { Person(id: $0.userID.isEmpty ? $0.id : $0.userID, name: $0.name) }
            return PiPGridDisplay(cell: cell, person: person, track: cell.live ? media?.videoTrack(for: cell.id) : nil)
        }
        pip.showGrid(displays)
        let line = "live=\(PiPGridPlan.liveCount(cells)) cells=\(cells.count) thermal=\(PiPHeatGuard.name(thermal))\(heat.reduced ? " guard=on" : "")"
        if line != lastGridLog { lastGridLog = line; diag.log("pip_grid \(line)") }
        scheduleHeatRecheck()
    }

    /// While the guard has the grid lightened, look again every 20 s so the grid comes back after 2 calm minutes without anything else prompting it.
    private func scheduleHeatRecheck() {
        guard heat.reduced, heatRecheck == nil else { return }
        heatRecheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self else { return }
            self.heatRecheck = nil
            self.refreshPiP()
        }
    }

    // MARK: In the call

    func setMuted(_ on: Bool) async {
        muted = on
        update(myParticipant) { $0.muted = on }
        await media?.setMicrophone(!on)
    }

    func toggleCamera() async {
        cameraOn.toggle()
        update(myParticipant) { $0.cameraOn = cameraOn }
        await media?.setCamera(cameraOn)
    }

    func flipCamera() async { await media?.flipCamera() }

    func toggleSpeaker() {
        speakerOn.toggle()
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    /// Hang up.
    func leave() async { await finish(notify: true) }

    private func finish(notify: Bool, tellCore: Bool = true) async {
        guard phase != .idle || !callID.isEmpty else { return }
        let id = callID
        let media = self.media
        diag.log("group call: leaving")
        poller?.cancel()
        probe?.cancel()
        stopCameraLog()
        network?.stop()
        pip?.stop(); pip = nil; pictureInPictureActive = false
        heatRecheck?.cancel(); heatRecheck = nil; heat.reset(); recentSpeakers = []; lastGridLog = ""
        anchorView = nil
        pipSubject = nil; lastOtherSpeaker = nil
        phase = .idle
        self.media = nil
        tiles = []
        verificationEmoji = []
        emojiWaiting = false
        callID = ""
        startedAt = nil
        minimized = false
        speakerOn = false
        if notify { system.reportEnded(callID: Self.systemID(id), answeredOrOutgoing: true) }
        await media?.disconnect()
        if tellCore { await core.leave(callID: id); _ = await core.deliver() }
        onFinished?()
    }

    /// How long to wait before looking for call ops again: every second while the call is being set up or anyone's key has not arrived yet (the
    /// keys travel as mail), every 3 seconds once everyone is in and secured. (It used to poll once a second for the whole call: a fetch every
    /// 1.4 s, which also filled the call log.)
    static func pollInterval(phase: Phase, tiles: [Tile]) -> Double {
        phase != .active || tiles.contains { !$0.secured } ? 1 : 3
    }

    private func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                let wait = self.map { Self.pollInterval(phase: $0.phase, tiles: $0.tiles) } ?? 1
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled, self.phase != .idle else { return }
                await self.fetchNow?()
                await self.pump()
                self.refreshPiP()
            }
        }
    }

    /// What the camera may do here (LIME-162): whether iPadOS lets the camera run next to other apps, and every interruption with its reason.
    @ObservationIgnored private var cameraObservers: [NSObjectProtocol] = []

    private func logCameraSupport() {
        guard video, cameraObservers.isEmpty else { return }
        let session = AVCaptureSession()
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        diag.log("group camera: \(device), multitasking camera access supported=\(session.isMultitaskingCameraAccessSupported) enabled=\(session.isMultitaskingCameraAccessEnabled)")
        let center = NotificationCenter.default
        cameraObservers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: nil, queue: .main) { note in
            let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int) ?? -1
            let reason = AVCaptureSession.InterruptionReason(rawValue: raw).map { "\($0)" } ?? "unknown(\(raw))"
            Task { @MainActor in CallDiagnostics.shared.log("group camera: interrupted, reason \(reason)") }
        })
        cameraObservers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in CallDiagnostics.shared.log("group camera: interruption ended") }
        })
        cameraObservers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: nil, queue: .main) { note in
            let error = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.code ?? 0
            Task { @MainActor in CallDiagnostics.shared.log("group camera: runtime error \(error)") }
        })
        cameraObservers.append(center.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in CallDiagnostics.shared.log("group camera: capture started") }
        })
        cameraObservers.append(center.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in CallDiagnostics.shared.log("group camera: capture stopped") }
        })
    }

    private func stopCameraLog() {
        for observer in cameraObservers { NotificationCenter.default.removeObserver(observer) }
        cameraObservers = []
    }

    /// Every 5 seconds of a video call, per remote person: whether their picture should show and whether frames really arrive, in the full call
    /// (the track itself, drawn or not) and in the minimised grid's cell (LIME-162).
    private func startProbe() {
        probe?.cancel()
        logCameraSupport()
        var last: (full: [String: Int], grid: [String: Int], at: Date) = ([:], [:], now())
        probe = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.phase != .idle, self.video else { return }
                let full = self.media?.frameCounts() ?? [:], grid = self.pip?.gridFrameCounts() ?? [:]
                let span = max(0.1, self.now().timeIntervalSince(last.at))
                let parts = self.tiles.filter { !$0.isMe }.map { tile -> String in
                    func rate(_ now: [String: Int], _ before: [String: Int]) -> String { now[tile.id].map { String(format: "%.1f", Double($0 - (before[tile.id] ?? 0)) / span) } ?? "-" }
                    return "\(tile.name.prefix(8))(secured=\(tile.secured ? 1 : 0) cam=\(tile.cameraOn ? 1 : 0) track=\(self.media?.videoTrack(for: tile.id) == nil ? 0 : 1) full=\(rate(full, last.full)) grid=\(rate(grid, last.grid)))"
                }
                last = (full, grid, self.now())
                self.diag.log("video_probe view=\(self.minimized || self.pictureInPictureActive ? "minimised" : "full") \(parts.joined(separator: " "))")
            }
        }
    }
}

#if DEBUG
extension GroupCallManager {
    /// Debug demo (`-lime-demo-screen group-call-N`): a group call on screen with N people and no network, for screenshots of the layout.
    func demoCall(people: Int, video: Bool = true, title: String = "Grade 4 Team", conversationID: String = "grp:demo", customName: Bool = false) {
        let names = ["Shem Chung", "Jean Park", "Lee Wong", "Sam Park", "Priya Nair", "Dee Ito", "Max Roy", "Ana Cruz", "Tom Lee", "Uma Das", "Vic Hale", "Wen Xu", "Yan Zhu"]
        // The demo starts from the default layout (the person's remembered choice would make tests and screenshots depend on the last run).
        chosenLayout = nil
        layoutDefaults.removeObject(forKey: Self.layoutKey)
        groupNameIsCustom = customName
        phase = .active
        self.video = video
        self.title = title
        callID = "demo"
        self.conversationID = conversationID
        startedAt = Date().addingTimeInterval(-83)
        verificationEmoji = groupCallEmoji(callId: "demo", participants: (0..<min(people, names.count)).map { GroupCallKey(participant: String(format: "%032x", $0), key: Data(repeating: UInt8($0 + 1), count: 32)) })
        tiles = (0..<min(people, names.count)).map {
            Tile(id: "demo-\($0)", userID: "demo-user-\($0)", name: names[$0], isMe: $0 == 0, muted: $0 == 2, cameraOn: false, speaking: $0 == 1, secured: true)
        }
    }
}
#endif
