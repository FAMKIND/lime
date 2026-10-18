import XCTest
@testable import Lime

/// LIME-112b: the group call manager is a thin adapter; these check that it obeys the core, hands keys to the media engine, shows a person
/// only once their key arrived, refuses a second call, rings by the core's word, and chains the system call screen's handlers.
@MainActor
final class GroupCallManagerTests: XCTestCase {
    final class FakeCore: GroupCallCore {
        var info = GroupCallInfo(callId: String(repeating: "ab", count: 32), conversationId: "grp:g1", room: String(repeating: "cd", count: 32), video: true,
                                 startedBy: "alice", startedByName: "Alice", startedAtMs: 0, participantCount: 0, joined: false)
        var others: [GroupCallParticipant] = []
        var joinKey = Data(repeating: 9, count: 32)
        var requested: [String] = []
        var report = GroupCallSendReport(sent: 0, keysSent: 0, waiting: 0, lastKeyIndex: 0)
        var token: LiveKitToken? = LiveKitToken(url: "wss://sfu.example.org", token: "t", ttlSeconds: 600)
        var servers = [IceServer(urls: ["turn:turn.example.org:3478"], username: "u", credential: "c")]
        var queued: [GroupCallEvent] = []
        var refuseStart = false
        /// What the core says the four emoji are now (the real one is tested in the core).
        var emoji = GroupCallEmojiState(ready: false, waiting: 1, emoji: [])
        private(set) var asked = 0
        /// The core's answer: a person chose the group's name.
        var customNamed = false
        private(set) var started = 0, joined = 0, left: [String] = [], gone: [String] = [], delivered = 0
        func start(conversationID: String, video: Bool) async throws -> GroupCallInfo {
            if refuseStart { throw AuthError.network }
            started += 1
            return info
        }
        func join(callID: String) async throws -> GroupCallJoin {
            joined += 1
            return GroupCallJoin(call: info, participant: String(repeating: "11", count: 16), key: joinKey, keyIndex: 0, participants: others)
        }
        func leave(callID: String) async { left.append(callID) }
        func participantGone(callID: String, participant: String) async { gone.append(participant) }
        func token(room: String, participant: String) async -> LiveKitToken? { token }
        func iceServers() async -> [IceServer] { servers }
        func deliver() async -> GroupCallSendReport? { delivered += 1; return report }
        func requestKey(callID: String, participant: String) async { requested.append(participant) }
        func takeEvents() -> [GroupCallEvent] { defer { queued = [] }; return queued }
        func activeCall(conversationID: String) -> GroupCallInfo? { info }
        func title(of conversationID: String) -> String { "Grade 4 Team" }
        func emojiState(callID: String) -> GroupCallEmojiState? { asked += 1; return emoji }
        func isCustomNamed(conversationID: String) -> Bool { customNamed }
    }

    final class FakeMedia: GroupCallMedia {
        var onEvent: (@MainActor (GroupMediaEvent) -> Void)?
        var keys: [String: (Data, Int)] = [:]
        var connectArgs: (identity: String, relayOnly: Bool, camera: Bool, low: Bool)?
        private(set) var lowBandwidth: [Bool] = []
        var tracks: [String: AnyObject] = [:]
        var connectError: Error?
        private(set) var disconnected = false, microphone: [Bool] = []
        func setKey(_ key: Data, participant: String, index: Int) { keys[participant] = (key, index) }
        /// Every time this phone was told to send with a key (the join, then each renewal), oldest first.
        private(set) var mySendKeys: [(key: Data, index: Int)] = []
        func setMyKey(_ key: Data, participant: String, index: Int) { keys[participant] = (key, index); mySendKeys.append((key, index)) }
        func connect(url: String, token: String, identity: String, iceServers: [IceServer], relayOnly: Bool, microphone: Bool, camera: Bool, lowBandwidth: Bool) async throws {
            if let connectError { throw connectError }
            connectArgs = (identity, relayOnly, camera, lowBandwidth)
        }
        func setLowBandwidth(_ on: Bool) async { lowBandwidth.append(on) }
        func setMicrophone(_ on: Bool) async { microphone.append(on) }
        func setCamera(_ on: Bool) async {}
        func flipCamera() async {}
        func disconnect() async { disconnected = true }
        func videoTrack(for participant: String) -> AnyObject? { tracks[participant] }
    }

    final class FakePiP: GroupPiP {
        var isPossible = true
        var notPossibleReason: String { "fake" }
        var onStarted: (() -> Void)?, onStopped: (() -> Void)?, onRestore: (() -> Void)?, onFailed: (() -> Void)?
        private(set) var prepared = 0, started = 0, stopped = 0
        /// The anchor each `prepare` got, and the one the window would start from (the latest: a rebound controller).
        private(set) var anchors: [UIView] = [], startedFrom: [UIView?] = []
        private(set) var shown: [(person: String, track: Bool, picture: Bool)] = []
        private(set) var subjects: [PiPSubject] = []
        private(set) var grids: [[PiPGridDisplay]] = []
        func showGrid(_ cells: [PiPGridDisplay]) { grids.append(cells) }
        private(set) var clears = 0
        func clearGrid() { clears += 1; grids.append([]) }
        func prepare(sourceView: UIView, subject: PiPSubject) { prepared += 1; anchors.append(sourceView) }
        func show(subject: PiPSubject, track: AnyObject?, pictureShowing: Bool) { subjects.append(subject); shown.append((subject.name, track != nil, pictureShowing)) }
        func start() { started += 1; startedFrom.append(anchors.last); onStarted?() }
        func stop() { stopped += 1 }
        /// The window becomes possible `possibleAfterRebuild` after a rebuild (a stand-in for iOS).
        var possibleAfterRebuild = false
        private(set) var rebuilt = 0, waited = 0
        func waitUntilPossible(timeout: Duration) async -> Bool {
            waited += 1
            if isPossible { return true }
            try? await Task.sleep(for: timeout)
            return isPossible
        }
        func rebuild() { rebuilt += 1; if possibleAfterRebuild { isPossible = true } }
    }

    final class FakeNetwork: GroupCallNetwork {
        var isCellular = false
        var onChange: ((Bool) -> Void)?
        private(set) var started = false
        func start() { started = true }
        func stop() { started = false }
    }

    private func make(core: FakeCore = FakeCore(), otherCall: Bool = false, quiet: CallQuietReason? = nil) -> (GroupCallManager, FakeCore, FakeMedia, QuietCallSystem) {
        let media = FakeMedia()
        let system = QuietCallSystem()
        let manager = GroupCallManager(core: core, system: system, quietReason: { quiet }, isOtherCallActive: { otherCall },
                                       me: { Person(id: "u-me", name: "Shem Chung") }, makeMedia: { media })
        return (manager, core, media, system)
    }

    private func event(_ kind: String, participant: String = "", user: String = "bob", name: String = "Bob", key: Data? = nil, index: UInt32 = 0, ring: Bool = false, call: String? = nil, reason: String = "") -> GroupCallEvent {
        GroupCallEvent(kind: kind, callId: call ?? String(repeating: "ab", count: 32), conversationId: "grp:g1", userId: user, name: name, participant: participant,
                       video: true, ring: ring, key: key, keyIndex: index, durationMs: 0, reason: reason)
    }

    private let bob = String(repeating: "22", count: 16)

    func testStartingJoinsConnectsAndSetsMyKeyUnderMyOwnIdentity() async {
        let (manager, core, media, _) = make()
        let ok = await manager.start(conversationID: "grp:g1", title: "Grade 4 Team", video: true)
        XCTAssertTrue(ok)
        XCTAssertEqual(core.started, 1)
        XCTAssertEqual(core.joined, 1)
        XCTAssertEqual(media.connectArgs?.identity, String(repeating: "11", count: 16), "the random participant id, not a user id")
        XCTAssertEqual(media.keys[String(repeating: "11", count: 16)]?.1, 0)
        XCTAssertEqual(media.keys[String(repeating: "11", count: 16)]?.0, Data(repeating: 9, count: 32))
        XCTAssertEqual(manager.phase, .connecting)
        media.onEvent?(.connection(connected: true, error: nil))
        XCTAssertEqual(manager.phase, .active)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(core.delivered >= 1, "my join and key are sent without waiting for the call to connect")
        await manager.leave()
    }

    func testAlwaysRelayConnectsRelayOnlyAndRefusesWithoutCredentials() async {
        let (manager, _, media, _) = make()
        manager.alwaysRelay = { true }
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: false)
        XCTAssertEqual(media.connectArgs?.relayOnly, true)
        await manager.leave()
        let core = FakeCore()
        core.servers = [IceServer(urls: ["stun:turn.example.org:3478"], username: nil, credential: nil)]
        let (second, _, media2, _) = make(core: core)
        second.alwaysRelay = { true }
        let ok = await second.start(conversationID: "grp:g1", title: "T", video: false)
        XCTAssertFalse(ok)
        XCTAssertNil(media2.connectArgs, "never falls back to a direct connection the person asked not to make")
        XCTAssertEqual(second.notice, CallPrivacy.relayUnavailable)
        XCTAssertEqual(second.phase, .idle)
        XCTAssertEqual(core.left.count, 1, "and the core is told I am not in it")
    }

    func testAPersonShowsOnlyOnceTheirKeyArrivedAndTheirMediaDecrypts() async {
        let core = FakeCore()
        core.others = [GroupCallParticipant(participant: bob, userId: "bob", name: "Bob")]
        let (manager, _, media, _) = make(core: core)
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: true)
        XCTAssertEqual(manager.tiles.map(\.name), ["Shem Chung", "Bob"])
        XCTAssertFalse(manager.tiles[1].secured, "no key yet: \"Connecting securely\", no picture")
        manager.handle([event("key", participant: bob, key: Data(repeating: 5, count: 32), index: 2)])
        XCTAssertEqual(media.keys[bob]?.1, 2)
        XCTAssertEqual(media.keys[bob]?.0, Data(repeating: 5, count: 32))
        XCTAssertTrue(manager.tiles[1].secured, "the key arrived and nothing says it fails")
        manager.handle(media: .secured(participant: bob, ok: false, state: "decryption_failed"))
        XCTAssertFalse(manager.tiles[1].secured, "undecryptable media is never shown")
        manager.handle(media: .secured(participant: bob, ok: true, state: "ok"))
        XCTAssertTrue(manager.tiles[1].secured)
        XCTAssertTrue(manager.tiles[0].secured, "my own tile")
        await manager.leave()
    }

    func testPeopleJoiningAndLeavingChangeTheTilesAndTheMediaServerReportingGoneTellsTheCore() async {
        let (manager, core, _, _) = make()
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: false)
        manager.handle([event("joined", participant: bob)])
        XCTAssertEqual(manager.tiles.map(\.name), ["Shem Chung", "Bob"])
        manager.handle([event("left", participant: bob)])
        XCTAssertEqual(manager.tiles.map(\.name), ["Shem Chung"])
        manager.handle(media: .participantConnected(bob))
        manager.handle(media: .participantDisconnected(bob))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(core.gone, [bob], "a participant the media server says is gone counts as having left")
        XCTAssertEqual(manager.tiles.map(\.name), ["Shem Chung"])
        await manager.leave()
    }

    func testOnlyOneCallAtATime() async {
        let (manager, core, _, _) = make(otherCall: true)
        let ok = await manager.start(conversationID: "grp:g1", title: "T", video: false)
        XCTAssertFalse(ok)
        XCTAssertEqual(core.started, 0)
        XCTAssertNotNil(manager.notice)
        let free = make()
        _ = await free.0.start(conversationID: "grp:g1", title: "T", video: false)
        let again = await free.0.start(conversationID: "grp:g1", title: "T", video: false)
        XCTAssertFalse(again, "already in a group call")
        await free.0.leave()
    }

    func testLeavingTellsTheCoreAndEndsTheMedia() async {
        let (manager, core, media, _) = make()
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: false)
        media.onEvent?(.connection(connected: true, error: nil))
        await manager.leave()
        XCTAssertEqual(manager.phase, .idle)
        XCTAssertEqual(core.left, [core.info.callId])
        XCTAssertTrue(media.disconnected)
        XCTAssertTrue(manager.tiles.isEmpty)
    }

    func testNoTokenMeansGroupCallsAreNotSetUpYet() async {
        let core = FakeCore()
        core.token = nil
        let (manager, _, media, _) = make(core: core)
        let ok = await manager.start(conversationID: "grp:g1", title: "T", video: false)
        XCTAssertFalse(ok)
        XCTAssertNil(media.connectArgs)
        XCTAssertEqual(manager.notice, "Group calls aren\u{2019}t available yet.")
        XCTAssertEqual(core.left.count, 1)
    }

    func testARingFollowsTheCoresWordAndIsSilencedByDoNotDisturb() async {
        let (manager, _, _, _) = make()
        manager.handle([event("started", user: "alice", name: "Alice", ring: false)])
        XCTAssertNil(manager.incoming, "a big group or one waiting in Requests: no ring")
        manager.handle([event("started", user: "alice", name: "Alice", ring: true)])
        XCTAssertEqual(manager.incoming?.callerName, "Alice")
        XCTAssertEqual(manager.incoming?.title, "Grade 4 Team")
        manager.handle([event("ended")])
        XCTAssertNil(manager.incoming, "the call ended before it was answered")
        let (quiet, _, _, _) = make(quiet: .dnd)
        quiet.handle([event("started", user: "alice", name: "Alice", ring: true)])
        XCTAssertNil(quiet.incoming, "Do Not Disturb silences a group ring (the chat line still shows the call)")
        let (busy, _, _, _) = make(otherCall: true)
        busy.handle([event("started", user: "alice", name: "Alice", ring: true)])
        XCTAssertNil(busy.incoming, "no ring over another call")
    }

    func testAnsweringARingJoinsTheCall() async {
        let (manager, core, media, _) = make()
        manager.handle([event("started", user: "alice", name: "Alice", ring: true)])
        await manager.acceptIncoming(fromSystem: true)
        XCTAssertEqual(core.joined, 1)
        XCTAssertNotNil(media.connectArgs)
        XCTAssertNil(manager.incoming)
        await manager.leave()
    }

    func testManyPeopleStartInSpeakerViewWithTheCameraOff() async {
        let core = FakeCore()
        core.others = (0..<12).map { GroupCallParticipant(participant: String(format: "%032x", $0 + 1), userId: "u\($0)", name: "P\($0)") }
        let (manager, _, media, _) = make(core: core)
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: true)
        XCTAssertTrue(manager.speakerViewByDefault, "13 people")
        XCTAssertEqual(media.connectArgs?.camera, false, "camera off by default above 12")
        await manager.leave()
        let (small, _, media2, _) = make()
        _ = await small.start(conversationID: "grp:g1", title: "T", video: true)
        XCTAssertFalse(small.speakerViewByDefault)
        XCTAssertEqual(media2.connectArgs?.camera, true)
        await small.leave()
    }

    func testTheSystemCallScreenIsSharedWithOneToOneCalls() async {
        let system = QuietCallSystem()
        var passedOn: [String] = []
        system.onAnswer = { passedOn.append($0) }
        let manager = GroupCallManager(core: FakeCore(), system: system, makeMedia: { FakeMedia() })
        _ = manager
        system.onAnswer?("a-one-to-one-call")
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(passedOn, ["a-one-to-one-call"], "what is not about a group call goes to the one-to-one handler")
        XCTAssertEqual(GroupCallManager.systemID(String(repeating: "ab", count: 32)).count, 36)
        XCTAssertNotNil(UUID(uuidString: GroupCallManager.systemID(String(repeating: "0123456789abcdef", count: 4))), "a call id becomes a valid UUID for CallKit")
    }

    func testTheCallBubbleSaysWhoStartedTheCallAndJoinWhileItIsOn() {
        let live = CallBubble(body: #"{"video":true,"duration_ms":0,"outcome":"live","outgoing":false,"group":true,"started_by":"alice"}"#, mine: false)
        XCTAssertEqual(live?.title(startedBy: "Alice"), "Alice started a call")
        XCTAssertEqual(live?.chatDetail, "Join")
        XCTAssertEqual(live?.live, true)
        let mine = CallBubble(body: #"{"video":false,"duration_ms":0,"outcome":"live","outgoing":true,"group":true,"started_by":"me"}"#, mine: true)
        XCTAssertEqual(mine?.title(startedBy: nil), "Call started", "never \"You\"")
        let ended = CallBubble(body: #"{"video":true,"duration_ms":1390000,"outcome":"completed","outgoing":false,"group":true,"started_by":"alice"}"#, mine: false)
        XCTAssertEqual(ended?.title(startedBy: "Alice"), "Call ended")
        XCTAssertEqual(ended?.chatDetail, "23:10")
        XCTAssertFalse(ended?.isMissedIncoming ?? true, "an ended group call is never shown as missed")
        // A one-to-one call is unchanged.
        let oneToOne = CallBubble(body: #"{"video":true,"duration_ms":23000,"outcome":"completed","outgoing":true}"#, mine: true)
        XCTAssertEqual(oneToOne?.title, "Video call")
        XCTAssertEqual(oneToOne?.chatDetail, "0:23")
    }

    func testAKeyTheCoreHandsOverAsRawBytesReachesTheMediaEngineAndSecuresTheTile() async {
        // LIME-112b-fix: the core used to hand keys over as base64 text without padding, which Swift's decoder refuses, so no key ever
        // reached the SDK and every tile stayed on "Connecting securely". Keys are raw bytes now: nothing to decode.
        XCTAssertNil(Data(base64Encoded: Data(repeating: 5, count: 32).base64EncodedString().replacingOccurrences(of: "=", with: "")), "the trap, for the record")
        let core = FakeCore()
        core.others = [GroupCallParticipant(participant: bob, userId: "bob", name: "Bob")]
        let (manager, _, media, _) = make(core: core)
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: true)
        XCTAssertEqual(media.keys[String(repeating: "11", count: 16)]?.0, Data(repeating: 9, count: 32), "my own key reaches the SDK")
        manager.handle([event("key", participant: bob, key: Data(repeating: 5, count: 32), index: 1)])
        XCTAssertEqual(media.keys[bob]?.0, Data(repeating: 5, count: 32), "Bob's key reaches the SDK under his own LiveKit identity")
        XCTAssertTrue(manager.tiles[1].secured)
        manager.handle([event("key", participant: bob, key: Data(repeating: 5, count: 31), index: 1)])
        XCTAssertEqual(media.keys[bob]?.0.count, 32, "a key that is not 32 bytes is ignored")
        await manager.leave()
    }

    func testATileStuckWithoutAKeyAsksItsOwnerOnceToSendItAgain() async {
        let core = FakeCore()
        core.others = [GroupCallParticipant(participant: bob, userId: "bob", name: "Bob")]
        var clock = Date(timeIntervalSince1970: 1_000)
        let media = FakeMedia()
        let manager = GroupCallManager(core: core, system: QuietCallSystem(), now: { clock }, makeMedia: { media })
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: true)
        manager.checkStuckTiles()
        clock = clock.addingTimeInterval(4)
        manager.checkStuckTiles()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(core.requested.isEmpty, "not before five seconds")
        clock = clock.addingTimeInterval(2)
        manager.checkStuckTiles()
        manager.checkStuckTiles()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(core.requested, [bob], "once, for the one who is stuck")
        manager.handle([event("key", participant: bob, key: Data(repeating: 5, count: 32), index: 0)])
        XCTAssertTrue(manager.tiles[1].secured)
        await manager.leave()
    }

    func testARefusedKeyIsLoggedWithItsReason() async {
        let (manager, _, _, _) = make()
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: false)
        manager.handle([event("key_rejected", participant: bob, reason: "not_owner")])
        XCTAssertTrue(CallDiagnostics.shared.lines.last?.contains("rejected: not_owner") ?? false)
        await manager.leave()
    }

    // MARK: LIME-112c

    func testJoiningAVideoCallAsVoicePublishesNoCamera() async {
        let (manager, core, media, _) = make()
        XCTAssertTrue(core.info.video, "the call is a video call")
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: false)
        XCTAssertEqual(media.connectArgs?.camera, false, "Voice from the menu: audio only, whatever kind of call is on")
        XCTAssertFalse(manager.cameraOn)
        XCTAssertTrue(manager.video, "it is still the video call for the others")
        await manager.leave()
        let (second, _, media2, _) = make()
        _ = await second.join(callID: core.info.callId, conversationID: "grp:g1", title: "T", video: true, withVideo: false)
        XCTAssertEqual(media2.connectArgs?.camera, false, "Voice from the call card or the header")
        await second.leave()
        let (third, _, media3, _) = make()
        _ = await third.join(callID: core.info.callId, conversationID: "grp:g1", title: "T", video: true)
        XCTAssertEqual(media3.connectArgs?.camera, true, "a plain join is as the call was started")
        await third.leave()
    }

    func testAnsweringARingingVideoCallAsVoiceHasNoCamera() async {
        let (manager, _, media, _) = make()
        manager.handle([event("started", user: "alice", name: "Alice", ring: true)])
        await manager.acceptIncoming(withVideo: false)
        XCTAssertEqual(media.connectArgs?.camera, false)
        await manager.leave()
        let (system, _, media2, _) = make()
        system.handle([event("started", user: "alice", name: "Alice", ring: true)])
        await system.acceptIncoming(fromSystem: true)
        XCTAssertEqual(media2.connectArgs?.camera, true, "the system's Answer is as the call was started")
        await system.leave()
    }

    func testMyOwnTileHasMyNameAndMyPhotoNotYou() async {
        let (manager, _, _, _) = make()
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: true)
        XCTAssertEqual(manager.tiles.first?.name, "Shem Chung")
        XCTAssertEqual(manager.tiles.first?.userID, "u-me", "so the same photo as everywhere else is used")
        XCTAssertTrue(manager.tiles.first?.isMe ?? false)
        await manager.leave()
    }

    private func pipCall(speakers: Int = 2, grid: Bool = false, thermal: @escaping () -> ProcessInfo.ThermalState = { .nominal }) async -> (GroupCallManager, FakePiP, FakeMedia, FakeCore, () -> Date, (TimeInterval) -> Void) {
        let core = FakeCore()
        core.others = (0..<speakers).map { GroupCallParticipant(participant: String(format: "%032x", $0 + 1), userId: "u\($0)", name: ["Bob", "Carol", "Dee"][$0]) }
        var clock = Date(timeIntervalSince1970: 5_000)
        let media = FakeMedia()
        let pip = FakePiP()
        let manager = GroupCallManager(core: core, system: QuietCallSystem(), now: { clock }, me: { Person(id: "u-me", name: "Shem Chung") },
                                       layoutDefaults: UserDefaults(suiteName: "pipcall-\(UUID().uuidString)")!, makeMedia: { media })
        if !grid { manager.choosePiPView(.speaker) }
        manager.thermalState = thermal
        manager.makePictureInPicture = { pip }
        _ = await manager.start(conversationID: "grp:g1", title: "Grade 4 Team", video: true)
        media.onEvent?(.connection(connected: true, error: nil))
        manager.preparePictureInPicture(sourceView: UIView())
        return (manager, pip, media, core, { clock }, { clock = clock.addingTimeInterval($0) })
    }

    func testTheWindowFollowsTheSpeakerWithAHoldAndIgnoresMe() async {
        let (manager, pip, _, core, _, advance) = await pipCall()
        let bob = core.others[0].participant, carol = core.others[1].participant
        let me = manager.tiles[0].id
        XCTAssertEqual(pip.prepared, 1)
        manager.handle(media: .speaking([bob]))
        XCTAssertEqual(pip.shown.last?.person, "Bob")
        advance(1)
        manager.handle(media: .speaking([carol]))
        XCTAssertEqual(pip.shown.last?.person, "Bob", "a new speaker within the 2 s hold does not move the window")
        advance(2)
        manager.handle(media: .speaking([carol]))
        XCTAssertEqual(pip.shown.last?.person, "Carol", "after the hold it follows")
        manager.handle(media: .speaking([me]))
        XCTAssertEqual(pip.shown.last?.person, "Carol", "when I am the one speaking it keeps the last other speaker")
        manager.handle(media: .speaking([]))
        XCTAssertEqual(pip.shown.last?.person, "Carol", "and when nobody is speaking")
        await manager.leave()
    }

    /// LIME-150: the minimised grid.
    private func secure(_ manager: GroupCallManager, _ core: FakeCore, _ media: FakeMedia, _ who: [Int]) {
        for index in who {
            let id = core.others[index].participant
            media.tracks[id] = NSObject()
            manager.handle([GroupCallEvent(kind: "key", callId: core.info.callId, conversationId: "grp:g1", userId: "u\(index)", name: core.others[index].name, participant: id, video: true, ring: false,
                                           key: Data(repeating: 5, count: 32), keyIndex: 0, durationMs: 0, reason: "")])
            manager.handle(media: .camera(participant: id, on: true))
        }
    }

    func testTheMinimisedViewIsTheGridUpToFourOtherPeopleAndTheChoiceIsRemembered() async {
        let (manager, _, _, _, _, _) = await pipCall(speakers: 2, grid: true)
        XCTAssertEqual(manager.pipView, .grid, "the default for a small call")
        manager.choosePiPView(.speaker)
        XCTAssertEqual(manager.pipView, .speaker)
        XCTAssertEqual(PiPGridPlan.view(choice: nil, others: 4), .grid)
        XCTAssertEqual(PiPGridPlan.view(choice: nil, others: 5), .speaker)
        XCTAssertEqual(PiPGridPlan.view(choice: .grid, others: 8), .grid, "the person's choice wins")
        await manager.leave()
    }

    func testTheGridShowsEveryoneWithTheSpeakerRingedAndPhotosWhereThereIsNoPicture() async {
        let (manager, pip, media, core, _, _) = await pipCall(speakers: 2, grid: true)
        secure(manager, core, media, [0])
        manager.handle(media: .speaking([core.others[1].participant]))
        let cells = pip.grids.last!.map(\.cell)
        XCTAssertEqual(cells.map(\.name), ["Bob", "Carol"], "the others, not me, for two")
        XCTAssertEqual(cells.map(\.speaking), [false, true], "the speaker is ringed")
        XCTAssertEqual(cells.map(\.live), [true, false], "Bob's picture is live; Carol has no key or camera yet: her photo")
        XCTAssertEqual(pip.grids.last!.map { $0.track != nil }, [true, false])
        XCTAssertEqual(pip.shown.last?.track, false, "the speaker window lets go of the track while the grid draws")
        await manager.leave()
    }

    func testThreeOthersMakeATwoByTwoWithMyPictureAsTheFourthCell() async {
        let (manager, pip, _, _, _, _) = await pipCall(speakers: 3, grid: true)
        manager.refreshPiP()
        let cells = pip.grids.last!.map(\.cell)
        XCTAssertEqual(cells.count, 4)
        XCTAssertEqual(cells.last?.isMe, true)
        XCTAssertEqual(pip.grids.last?.last?.person?.id, manager.meProvider().id)
        await manager.leave()
    }

    func testTheSpeakerViewKeepsTheSingleSpeakerWindowAndClearsTheGrid() async {
        let (manager, pip, _, core, _, _) = await pipCall(speakers: 2)
        manager.handle(media: .speaking([core.others[0].participant]))
        XCTAssertEqual(pip.shown.last?.person, "Bob")
        XCTAssertTrue(pip.grids.allSatisfy(\.isEmpty), "no grid in the speaker view")
        await manager.leave()
    }

    func testTheHeatGuardKeepsOnlyTheSpeakerLiveWhileHotAndComesBackAfterTwoCalmMinutes() async {
        var thermal = ProcessInfo.ThermalState.nominal
        let (manager, pip, media, core, _, advance) = await pipCall(speakers: 3, grid: true, thermal: { thermal })
        secure(manager, core, media, [0, 1, 2])
        manager.handle(media: .speaking([core.others[0].participant]))
        XCTAssertEqual(PiPGridPlan.liveCount(pip.grids.last!.map(\.cell)), 3, "all three pictures live")
        thermal = .serious
        manager.refreshPiP()
        let hot = pip.grids.last!.map(\.cell)
        XCTAssertEqual(PiPGridPlan.liveCount(hot), 1, "only the speaker stays live")
        XCTAssertEqual(hot.filter(\.live).first?.name, "Bob")
        XCTAssertEqual(hot.count, 4, "same layout")
        thermal = .fair
        manager.refreshPiP()
        advance(60)
        manager.refreshPiP()
        XCTAssertEqual(PiPGridPlan.liveCount(pip.grids.last!.map(\.cell)), 1, "one calm minute is not enough")
        advance(61)
        manager.refreshPiP()
        XCTAssertEqual(PiPGridPlan.liveCount(pip.grids.last!.map(\.cell)), 3, "two calm minutes: all live again")
        await manager.leave()
    }

    /// LIME-163: a received key goes to the media layer for that person only, however many times people left before, and never moves this phone's own
    /// send key; the media layer keeps every key in the one slot that frames really use.
    func testAReceivedKeyNeverTouchesMyOwnSendKeyAndLiveKitUsesOneSlotForEveryKey() async {
        let (manager, _, media, core, _, _) = await pipCall(speakers: 2)
        let bob = core.others[0].participant, carol = core.others[1].participant
        let sends = media.mySendKeys.count
        for (round, index) in [UInt32(1), 2, 3].enumerated() {
            for (user, who) in [("u0", bob), ("u1", carol)] {
                manager.handle([GroupCallEvent(kind: "key", callId: core.info.callId, conversationId: "grp:g1", userId: user, name: "x", participant: who, video: true, ring: false,
                                               key: Data(repeating: UInt8(10 + round), count: 32), keyIndex: index, durationMs: 0, reason: "")])
            }
        }
        XCTAssertEqual(media.mySendKeys.count, sends, "someone else's key never changes what this phone sends with")
        XCTAssertEqual(media.keys[bob]?.1, 3, "their newest key, at the core's index")
        XCTAssertEqual(media.keys[carol]?.1, 3)
        XCTAssertEqual(LiveKitGroupMedia.slot, 0, "frames are sent and read with slot 0: every key is installed there")
        await manager.leave()
    }

    /// LIME-150-fix5: Grid mode owns the window.
    func testGridModeNeverTakesTheSpeakerPathAndSomeoneLeavingDoesNotFlipTheWindow() async {
        let (manager, pip, media, core, _, _) = await pipCall(speakers: 2, grid: true)
        secure(manager, core, media, [0, 1])
        manager.handle(media: .speaking([core.others[0].participant]))
        let before = pip.shown.count
        XCTAssertTrue(pip.shown.allSatisfy { $0.picture == false }, "the speaker window never shows a picture while the grid owns the window")
        // Both leave, one rejoins: the mode does not change, so the grid is never cleared and the speaker path does not run.
        manager.handle([event("left", participant: core.others[0].participant), event("left", participant: core.others[1].participant)])
        manager.refreshPiP()
        XCTAssertEqual(pip.clears, 0, "the grid is not torn down while nobody is here")
        XCTAssertTrue(pip.shown.dropFirst(before).allSatisfy { $0.picture == false })
        manager.handle(media: .speaking([]))
        XCTAssertTrue(pip.shown.allSatisfy { $0.picture == false })
        await manager.leave()
    }

    func testTheModeComesFromTheCallAndTheChoiceNotFromWhoIsInTheRoom() {
        XCTAssertEqual(PiPGridPlan.mode(video: true, choice: nil, others: 0).mode, .grid)
        XCTAssertEqual(PiPGridPlan.mode(video: true, choice: nil, others: 2).mode, .grid)
        XCTAssertEqual(PiPGridPlan.mode(video: true, choice: nil, others: 6).mode, .speaker)
        XCTAssertEqual(PiPGridPlan.mode(video: true, choice: .speaker, others: 2).mode, .speaker)
        XCTAssertEqual(PiPGridPlan.mode(video: true, choice: .grid, others: 9).mode, .grid)
        XCTAssertEqual(PiPGridPlan.mode(video: false, choice: .grid, others: 2).mode, .speaker, "a voice call has no grid")
        XCTAssertFalse(PiPGridPlan.mode(video: true, choice: nil, others: 2).why.isEmpty)
    }

    func testTheWindowShowsThePhotoWhenTheCameraIsOffOrTheKeyIsMissingAndNeverNothing() async {
        let (manager, pip, media, core, _, _) = await pipCall(speakers: 1)
        let bob = core.others[0].participant
        media.tracks[bob] = NSObject()
        manager.handle(media: .speaking([bob]))
        XCTAssertEqual(pip.shown.last?.person, "Bob")
        XCTAssertEqual(pip.shown.last?.picture, false, "his key has not arrived: his photo, not undecrypted video")
        manager.handle([GroupCallEvent(kind: "key", callId: core.info.callId, conversationId: "grp:g1", userId: "u0", name: "Bob", participant: bob, video: true, ring: false,
                                       key: Data(repeating: 5, count: 32), keyIndex: 0, durationMs: 0, reason: "")])
        manager.handle(media: .camera(participant: bob, on: false))
        XCTAssertEqual(pip.shown.last?.picture, false, "his camera is off: his photo")
        manager.handle(media: .camera(participant: bob, on: true))
        XCTAssertEqual(pip.shown.last?.picture, true, "key and camera: his picture")
        XCTAssertEqual(pip.shown.last?.track, true)
        manager.handle([event("left", participant: bob)])
        manager.refreshPiP()
        XCTAssertEqual(pip.shown.last?.person, "Grade 4 Team", "nobody else yet: the group's own avatar, never an empty window")
        XCTAssertEqual(pip.shown.last?.picture, false)
        await manager.leave()
    }

    func testMinimiseOpensTheChatAndAVideoCallFloatsWhileAVoiceCallKeepsTheBar() async {
        let (manager, pip, _, core, _, _) = await pipCall()
        var opened: [String] = []
        manager.onMinimize = { opened.append($0) }
        manager.minimize()
        XCTAssertEqual(opened, ["grp:g1"], "the group's chat opens so the person can type")
        XCTAssertEqual(pip.started, 1)
        XCTAssertTrue(manager.pictureInPictureActive)
        XCTAssertTrue(manager.minimized)
        pip.onRestore?()
        XCTAssertFalse(manager.minimized, "tapping the window brings the call screen back")
        XCTAssertFalse(manager.pictureInPictureActive)
        await manager.leave()
        XCTAssertEqual(pip.stopped, 1, "leaving the call closes the window")
        // A voice call has no window: the slim bar.
        let voice = FakeCore()
        voice.info = GroupCallInfo(callId: core.info.callId, conversationId: "grp:g1", room: core.info.room, video: false, startedBy: "alice", startedByName: "Alice", startedAtMs: 0, participantCount: 0, joined: false)
        let media = FakeMedia()
        let manager2 = GroupCallManager(core: voice, system: QuietCallSystem(), makeMedia: { media })
        let pip2 = FakePiP()
        manager2.makePictureInPicture = { pip2 }
        var opened2: [String] = []
        manager2.onMinimize = { opened2.append($0) }
        _ = await manager2.start(conversationID: "grp:g1", title: "T", video: false)
        media.onEvent?(.connection(connected: true, error: nil))
        manager2.preparePictureInPicture(sourceView: UIView())
        manager2.minimize()
        XCTAssertEqual(opened2, ["grp:g1"], "a voice call opens the chat too")
        XCTAssertTrue(manager2.minimized)
        XCTAssertEqual(pip2.started, 0, "no picture, no window")
        await manager2.leave()
    }

    func testTheCallHasOneAnchorForItsWholeLifeSoTheWindowFloatsOnEveryMinimise() async {
        let (manager, pip, _, _, _, _) = await pipCall()
        let anchor = manager.pictureInPictureAnchor()
        XCTAssertTrue(manager.pictureInPictureAnchor() === anchor, "asked twice: the same view")
        pip.isPossible = true
        for round in 1...4 {
            manager.minimize()
            XCTAssertEqual(pip.started, round, "round \(round): the window starts")
            pip.onRestore?()
            // A new call screen hosts the same anchor and hands it on again: nothing to rebind.
            manager.preparePictureInPicture(sourceView: manager.pictureInPictureAnchor())
            XCTAssertTrue(pip.anchors.last === anchor, "round \(round): the controller still has the one anchor")
        }
        XCTAssertEqual(Set(pip.anchors.map { ObjectIdentifier($0) }).count <= 2, true, "never a new anchor per call screen")
        await manager.leave()
        XCTAssertFalse(manager.pictureInPictureAnchor() === anchor, "a new call gets a new anchor")
    }

    func testAWindowThatIsNotPossibleYetIsWaitedForThenRebuiltThenTheFallback() async {
        let (manager, pip, _, _, _, _) = await pipCall()
        manager.pipWait = .milliseconds(20)
        pip.isPossible = false
        pip.possibleAfterRebuild = true
        manager.minimize()
        XCTAssertEqual(pip.started, 0)
        XCTAssertFalse(manager.minimized, "not yet: it waits for the system first")
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(pip.rebuilt, 1, "still not possible after the wait: the controller is rebuilt")
        XCTAssertEqual(pip.started, 1, "and the window starts once it is")
        XCTAssertTrue(manager.pictureInPictureActive)

        // Possible by itself during the wait: no rebuild.
        pip.onRestore?()
        pip.isPossible = false
        pip.possibleAfterRebuild = false
        manager.minimize()
        pip.isPossible = true
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(pip.started, 2)
        XCTAssertEqual(pip.rebuilt, 1, "it became possible on its own: no second rebuild")

        // Never possible: the bar, as before.
        pip.onRestore?()
        pip.isPossible = false
        manager.minimize()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(pip.started, 2)
        XCTAssertEqual(pip.rebuilt, 2)
        XCTAssertTrue(manager.minimized, "still not possible after a rebuild: the mini player")
        XCTAssertFalse(manager.pictureInPictureActive)
        await manager.leave()
    }

    func testTheWindowRebindsToANewAnchorAndKeepsAnUnchangedOne() {
        XCTAssertEqual(PiPSourceBinding.action(hasController: false, sameSource: false), .create)
        XCTAssertEqual(PiPSourceBinding.action(hasController: true, sameSource: true), .keep)
        XCTAssertEqual(PiPSourceBinding.action(hasController: true, sameSource: false), .rebind, "the rebuilt call screen has a new anchor")
    }

    func testTheEmojiWaitUntilEveryKeyIsInAndAreAskedForAgainAfterEveryJoinKeyAndLeave() async {
        let (manager, _, media, core, _, _) = await pipCall()
        _ = media
        let bob = core.others[0].participant
        XCTAssertTrue(manager.emojiWaiting, "someone's key has not arrived: no emoji, a waiting chip")
        XCTAssertTrue(manager.verificationEmoji.isEmpty)
        let first = [CallEmoji(emoji: "🐶", name: "dog"), CallEmoji(emoji: "🐱", name: "cat"), CallEmoji(emoji: "🐭", name: "mouse"), CallEmoji(emoji: "🐹", name: "hamster")]
        core.emoji = GroupCallEmojiState(ready: true, waiting: 0, emoji: first)
        let before = core.asked
        manager.handle([event("key", participant: bob, key: Data(repeating: 3, count: 32), index: 0)])
        XCTAssertEqual(manager.verificationEmoji, first, "the key arrived: the four are shown")
        XCTAssertFalse(manager.emojiWaiting)
        XCTAssertGreaterThan(core.asked, before)
        // Someone joins: the core's four change, and the app shows the new ones (and waits again for the new person's key).
        core.emoji = GroupCallEmojiState(ready: false, waiting: 1, emoji: [])
        manager.handle([event("joined", participant: String(repeating: "77", count: 16), user: "dee", name: "Dee")])
        XCTAssertTrue(manager.emojiWaiting)
        XCTAssertTrue(manager.verificationEmoji.isEmpty, "no emoji while a key is missing")
        let second = [CallEmoji(emoji: "🐰", name: "rabbit"), first[0], first[1], first[2]]
        core.emoji = GroupCallEmojiState(ready: true, waiting: 0, emoji: second)
        manager.handle([event("key", participant: String(repeating: "77", count: 16), user: "dee", key: Data(repeating: 4, count: 32), index: 0)])
        XCTAssertEqual(manager.verificationEmoji, second)
        // Someone leaves: new keys, new four.
        let third = [first[3], first[2], first[1], first[0]]
        core.emoji = GroupCallEmojiState(ready: true, waiting: 0, emoji: third)
        manager.handle([event("left", participant: String(repeating: "77", count: 16), user: "dee")])
        XCTAssertEqual(manager.verificationEmoji, third)
        await manager.leave()
        XCTAssertTrue(manager.verificationEmoji.isEmpty, "gone with the call")
        XCTAssertFalse(manager.emojiWaiting)
    }

    func testWhenTheCoreRenewsMyKeyThisPhoneSendsWithItAtOnceAndTheGuardLogsAMismatch() async {
        let (manager, _, media, core, _, _) = await pipCall()
        XCTAssertEqual(media.mySendKeys.map(\.index), [0], "at join: the first key, index 0")
        let mine = String(repeating: "11", count: 16)
        // Someone left: the core renewed my key (index 1) and says so.
        let renewed = Data(repeating: 0x77, count: 32)
        manager.handle([event("my_key", participant: mine, user: "u-me", name: "Shem Chung", key: renewed, index: 1)])
        XCTAssertEqual(media.mySendKeys.map(\.index), [0, 1], "this phone switches to index 1")
        XCTAssertEqual(media.mySendKeys.last?.key, renewed)
        XCTAssertEqual(media.keys[mine]?.1, 1)
        // Another renewal: n + 1 again.
        manager.handle([event("my_key", participant: mine, user: "u-me", name: "Shem Chung", key: Data(repeating: 0x78, count: 32), index: 2)])
        XCTAssertEqual(media.mySendKeys.map(\.index), [0, 1, 2])
        // A key that is not mine, or not 32 bytes, changes nothing.
        manager.handle([event("my_key", participant: core.others[0].participant, key: renewed, index: 9)])
        manager.handle([event("my_key", participant: mine, user: "u-me", key: Data(repeating: 1, count: 5), index: 9)])
        XCTAssertEqual(media.mySendKeys.map(\.index), [0, 1, 2])
        // The guard: the media layer says it sends with an index the core does not call current.
        func linesAfter(_ marker: String) -> [String] {
            let all = CallDiagnostics.shared.lines
            return all.lastIndex { $0.contains(marker) }.map { Array(all[($0 + 1)...]) } ?? []
        }
        CallDiagnostics.shared.log("MARK-112e-a")
        media.onEvent?(.sendIndexReset(0))
        XCTAssertTrue(linesAfter("MARK-112e-a").contains { $0.contains("WARNING this phone sends with index 0 but the core's current index is 2") })
        CallDiagnostics.shared.log("MARK-112e-b")
        media.onEvent?(.sendIndexReset(2))
        XCTAssertFalse(linesAfter("MARK-112e-b").contains { $0.contains("WARNING this phone sends") })
        await manager.leave()
    }

    func testTheCallIsNamedByThePeopleUnlessAPersonChoseTheGroupsName() async {
        // The group kept its default name: the people in the call name it, and the names follow who is there.
        let (manager, _, _, core, _, _) = await pipCall()
        XCTAssertFalse(manager.groupNameIsCustom)
        XCTAssertEqual(manager.callTitle, "Shem, Bob, Carol", "the people (me first), not the group's name")
        manager.handle([event("left", participant: core.others[1].participant, user: "carol")])
        XCTAssertEqual(manager.callTitle, "Shem, Bob", "it follows who is in the call")
        await manager.leave()
        // A name a person chose (renamed, or typed): that names the call.
        let custom = FakeCore()
        custom.customNamed = true
        custom.others = [GroupCallParticipant(participant: String(repeating: "22", count: 16), userId: "u1", name: "Bob Lee")]
        let media = FakeMedia()
        let named = GroupCallManager(core: custom, system: QuietCallSystem(), me: { Person(id: "u-me", name: "Shem Chung") }, makeMedia: { media })
        _ = await named.start(conversationID: "grp:g1", title: "Grade 4 Team", video: true)
        XCTAssertTrue(named.groupNameIsCustom)
        XCTAssertEqual(named.callTitle, "Grade 4 Team")
        await named.leave()
    }

    func testMobileDataSends480pAndWiFiGoesBackTo720p() async {
        let network = FakeNetwork()
        network.isCellular = true
        let media = FakeMedia()
        let manager = GroupCallManager(core: FakeCore(), system: QuietCallSystem(), network: network, makeMedia: { media })
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: true)
        XCTAssertEqual(media.connectArgs?.low, true, "on mobile data at the start: 480p")
        XCTAssertTrue(network.started)
        network.onChange?(false)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(media.lowBandwidth, [false], "Wi-Fi: back to 720p")
        network.onChange?(true)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(media.lowBandwidth, [false, true])
        await manager.leave()
        XCTAssertFalse(network.started)
    }

    // MARK: LIME-146

    func testACallThatDoesNotRingOffersTheInviteSheetOnlyWhenLimeIsOpenIdleAndElsewhere() async {
        let (manager, _, _, _) = make()
        manager.handle([event("started", user: "alice", name: "Alice", ring: false)])
        XCTAssertEqual(manager.invite?.conversationID, "grp:g1")
        XCTAssertEqual(manager.invite?.title, "Grade 4 Team")
        manager.dismissInvite()
        XCTAssertNil(manager.invite)
        // Looking at that chat already: no sheet.
        let (viewing, _, _, _) = make()
        viewing.isViewingChat = { $0 == "grp:g1" }
        viewing.handle([event("started", user: "alice", name: "Alice", ring: false)])
        XCTAssertNil(viewing.invite, "no sheet over the chat the call is in")
        // Already in a call, or silenced: no sheet.
        let (busy, _, _, _) = make(otherCall: true)
        busy.handle([event("started", user: "alice", name: "Alice", ring: false)])
        XCTAssertNil(busy.invite, "no sheet while in a call")
        let (quiet, _, _, _) = make(quiet: .workHours)
        quiet.handle([event("started", user: "alice", name: "Alice", ring: false)])
        XCTAssertNil(quiet.invite, "work hours and Do Not Disturb silence it")
        // A group that rings shows the ring, not the sheet.
        let (ringing, _, _, _) = make()
        ringing.handle([event("started", user: "alice", name: "Alice", ring: true)])
        XCTAssertNil(ringing.invite)
        XCTAssertNotNil(ringing.incoming)
        // The call ends before it is answered: the sheet goes.
        let (ended, _, _, _) = make()
        ended.handle([event("started", user: "alice", name: "Alice", ring: false)])
        ended.handle([event("ended")])
        XCTAssertNil(ended.invite)
    }

    func testJoiningFromTheInviteSheetJoinsAndClearsItAndVoiceHasNoCamera() async {
        let (manager, core, media, _) = make()
        manager.handle([event("started", user: "alice", name: "Alice", ring: false)])
        await manager.acceptInvite(withVideo: false)
        XCTAssertNil(manager.invite)
        XCTAssertEqual(core.joined, 1)
        XCTAssertEqual(media.connectArgs?.camera, false, "Join with voice only")
        await manager.leave()
        let (second, core2, media2, _) = make()
        second.handle([event("started", user: "alice", name: "Alice", ring: false)])
        await second.acceptInvite()
        XCTAssertEqual(core2.joined, 1)
        XCTAssertEqual(media2.connectArgs?.camera, true, "Join: as the call was started")
        await second.leave()
    }

    func testTheLiveCardKnowsWhoIsThereFromTheJoinAndLeaveEvents() async {
        let (manager, _, _, _) = make()
        let carol = String(repeating: "33", count: 16)
        manager.handle([event("joined", participant: bob, user: "u-bob", name: "Bob Brown"), event("joined", participant: carol, user: "u-carol", name: "Carol Clark")])
        XCTAssertEqual(manager.liveSummary(conversationID: "grp:g1")?.people.map(\.name), ["Bob Brown", "Carol Clark"])
        manager.handle([event("left", participant: bob, user: "u-bob")])
        XCTAssertEqual(manager.liveSummary(conversationID: "grp:g1")?.people.map(\.name), ["Carol Clark"])
        manager.handle([event("ended")])
        XCTAssertEqual(manager.liveSummary(conversationID: "grp:g1")?.people.count, 0, "the card forgets a call that ended")
    }

    func testTheLiveCardWordsNameWhoIsThereAndNeverSayYou() {
        XCTAssertEqual(LiveCardWords.who([], count: 0), "Nobody is there yet")
        XCTAssertEqual(LiveCardWords.who([], count: 1), "1 person is there")
        XCTAssertEqual(LiveCardWords.who([], count: 3), "3 people are there")
        XCTAssertEqual(LiveCardWords.who(["Jean Park"], count: 1), "Jean is there")
        XCTAssertEqual(LiveCardWords.who(["Jean Park", "Lee Wu"], count: 2), "Jean and Lee are there")
        XCTAssertEqual(LiveCardWords.who(["Jean Park", "Lee Wu", "Sam Ito"], count: 4), "Jean, Lee and 2 others are there")
        XCTAssertEqual(LiveCardWords.who(["Jean Park"], count: 3), "Jean is there and 2 others")
        XCTAssertFalse(LiveCardWords.spoken(who: "Jean is there", video: true).contains("You"))
        XCTAssertEqual(LiveCardWords.spoken(who: "Jean is there", video: false), "Voice call in progress. Jean is there. Join")
    }

    // MARK: LIME-146b

    func testTheCallCircleSaysJoinOrReturnWithoutACount() {
        XCTAssertEqual(LiveCallButton.label(video: true, returning: false), "Join video call")
        XCTAssertEqual(LiveCallButton.label(video: false, returning: false), "Join voice call")
        XCTAssertEqual(LiveCallButton.label(video: true, returning: true), "Return to call")
        XCTAssertFalse(LiveCallButton.label(video: true, returning: false).contains("people"), "no count on the button: the card has it")
    }

    func testTappingACallBubbleNeverCallsOnePersonInAGroup() {
        let live = CallBubble(video: true, duration: 0, outcome: .completed, mine: false, isGroup: true, live: true, startedBy: "alice")
        let ended = CallBubble(video: true, duration: 60, outcome: .completed, mine: false, isGroup: true, live: false, startedBy: "alice")
        let oneToOne = CallBubble(video: false, duration: 5, outcome: .completed, mine: true)
        XCTAssertEqual(CallBubbleTap.action(isGroup: true, call: live), .join, "a live card joins in one tap")
        XCTAssertEqual(CallBubbleTap.action(isGroup: true, call: ended), .callGroupAgain, "an ended group call asks to call the group again")
        XCTAssertEqual(CallBubbleTap.action(isGroup: true, call: oneToOne), .callGroupAgain, "an old one-to-one bubble in a group never calls a person either")
        XCTAssertEqual(CallBubbleTap.action(isGroup: false, call: oneToOne), .callBack, "in a DM: the call-back question as before")
    }

    func testAloneInMyOwnCallTheCardWaitsForOthers() {
        XCTAssertEqual(LiveCardWords.who([], count: 1, iAmIn: true), "Waiting for others")
        XCTAssertEqual(LiveCardWords.who([], count: 0, iAmIn: true), "Waiting for others")
        XCTAssertEqual(LiveCardWords.who([], count: 1, iAmIn: false), "1 person is there", "someone else's card is unchanged")
        XCTAssertEqual(LiveCardWords.who(["Jean Park"], count: 2, iAmIn: true), "Jean is there and 1 other")
    }

    func testTheWindowShowsTheGroupAsTheChatDoesWhenNobodyElseIsThere() async {
        let members = [Person(id: "u1", name: "Jean Park"), Person(id: "u2", name: "Lee Wu")]
        let core = FakeCore()
        let media = FakeMedia()
        let pip = FakePiP()
        let manager = GroupCallManager(core: core, system: QuietCallSystem(), makeMedia: { media })
        manager.groupLook = { id in id == "grp:g1" ? ("🍎", members) : nil }
        manager.makePictureInPicture = { pip }
        _ = await manager.start(conversationID: "grp:g1", title: "Grade 4 Team", video: true)
        media.onEvent?(.connection(connected: true, error: nil))
        manager.preparePictureInPicture(sourceView: UIView())
        manager.refreshPiP()
        XCTAssertEqual(pip.subjects.last, .group(id: "grp:g1", name: "Grade 4 Team", emoji: "🍎", members: members, me: SampleData.me))
        await manager.leave()
    }

    @MainActor func testTheWindowsGroupPictureUsesPhotosAndInitialsOnlyForMembersWithNone() {
        let cache = AvatarCache.shared
        cache.reset()
        defer { cache.reset() }
        func jpeg() -> Data { UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 1) { UIColor.green.setFill(); $0.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) } }
        // A group photo wins.
        cache.set(jpeg(), for: "grp:g1")
        let photo = PiPGroupAvatarView(groupID: "grp:g1", name: "G", emoji: "🍎", members: [Person(id: "a", name: "A B")])
        XCTAssertTrue(photo.showsGroupPhoto)
        XCTAssertFalse(photo.showsEmoji)
        cache.set(nil, for: "grp:g1")
        // Else the emoji.
        let emoji = PiPGroupAvatarView(groupID: "grp:g1", name: "G", emoji: "🍎", members: [Person(id: "a", name: "A B")])
        XCTAssertTrue(emoji.showsEmoji)
        // Else a cluster of up to four members: photos for those who have one, initials for the rest.
        cache.set(jpeg(), for: "a")
        let four = (0..<4).map { Person(id: ["a", "b", "c", "d"][$0], name: "P\($0) Q") }
        let cluster = PiPGroupAvatarView(groupID: "grp:g1", name: "G", emoji: nil, members: four)
        XCTAssertEqual(cluster.clusterCount, 4)
        XCTAssertFalse(cluster.showsGroupPhoto || cluster.showsEmoji)
        let many = PiPGroupAvatarView(groupID: "grp:g1", name: "G", emoji: nil, members: (0..<7).map { Person(id: "m\($0)", name: "M\($0) N") })
        XCTAssertEqual(many.clusterCount, 4, "three members and the +4 slot, like the chat's cluster")
        XCTAssertEqual(cluster.accessibilityLabel, "G")
    }

    // MARK: LIME-148b

    func testTheLayoutChoiceIsRememberedAndOverridesTheDefault() async {
        let defaults = UserDefaults(suiteName: "lime.tests.layout.\(UUID().uuidString)")!
        let media = FakeMedia()
        let core = FakeCore()
        core.others = [GroupCallParticipant(participant: bob, userId: "bob", name: "Bob")]
        let manager = GroupCallManager(core: core, system: QuietCallSystem(), layoutDefaults: defaults, makeMedia: { media })
        let size = CGSize(width: 375, height: 470)
        _ = await manager.start(conversationID: "grp:g1", title: "T", video: true)
        XCTAssertNil(manager.chosenLayout)
        XCTAssertEqual(manager.effectiveLayout(in: size), .speaker, "one person plus me: one-on-one by default")
        manager.chooseLayout(.grid)
        XCTAssertEqual(manager.effectiveLayout(in: size), .grid)
        await manager.leave()
        // A new call on this phone (a new manager) remembers it.
        let again = GroupCallManager(core: FakeCore(), system: QuietCallSystem(), layoutDefaults: defaults, makeMedia: { media })
        XCTAssertEqual(again.chosenLayout, .grid, "kept on this device")
    }

    func testTheSpeakerLargeIsTheSpeakingPersonElseTheLastToSpeakNeverMe() async {
        let core = FakeCore()
        core.others = [GroupCallParticipant(participant: bob, userId: "bob", name: "Bob"), GroupCallParticipant(participant: String(repeating: "33", count: 16), userId: "c", name: "Carol")]
        let (manager, _, media, _) = await { () -> (GroupCallManager, FakeCore, FakeMedia, QuietCallSystem) in
            let m = FakeMedia()
            let manager = GroupCallManager(core: core, system: QuietCallSystem(), layoutDefaults: UserDefaults(suiteName: "lime.tests.\(UUID().uuidString)")!, makeMedia: { m })
            _ = await manager.start(conversationID: "grp:g1", title: "T", video: true)
            return (manager, core, m, QuietCallSystem())
        }()
        _ = media
        XCTAssertEqual(manager.spotlightID, bob, "nobody has spoken: the first other person")
        let carol = core.others[1].participant
        manager.handle(media: .speaking([carol]))
        XCTAssertEqual(manager.spotlightID, carol)
        manager.handle(media: .speaking([manager.tiles[0].id]))
        XCTAssertEqual(manager.spotlightID, carol, "I am never the large one")
        await manager.leave()
    }
}
