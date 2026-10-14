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
    }

    final class FakeMedia: GroupCallMedia {
        var onEvent: (@MainActor (GroupMediaEvent) -> Void)?
        var keys: [String: (Data, Int)] = [:]
        var connectArgs: (identity: String, relayOnly: Bool, camera: Bool)?
        var connectError: Error?
        private(set) var disconnected = false, microphone: [Bool] = []
        func setKey(_ key: Data, participant: String, index: Int) { keys[participant] = (key, index) }
        func connect(url: String, token: String, identity: String, iceServers: [IceServer], relayOnly: Bool, microphone: Bool, camera: Bool) async throws {
            if let connectError { throw connectError }
            connectArgs = (identity, relayOnly, camera)
        }
        func setMicrophone(_ on: Bool) async { microphone.append(on) }
        func setCamera(_ on: Bool) async {}
        func flipCamera() async {}
        func disconnect() async { disconnected = true }
        func videoTrack(for participant: String) -> AnyObject? { nil }
    }

    private func make(core: FakeCore = FakeCore(), otherCall: Bool = false, quiet: CallQuietReason? = nil) -> (GroupCallManager, FakeCore, FakeMedia, QuietCallSystem) {
        let media = FakeMedia()
        let system = QuietCallSystem()
        let manager = GroupCallManager(core: core, system: system, quietReason: { quiet }, isOtherCallActive: { otherCall }, makeMedia: { media })
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
        XCTAssertEqual(manager.tiles.map(\.name), ["You", "Bob"])
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
        XCTAssertEqual(manager.tiles.map(\.name), ["You", "Bob"])
        manager.handle([event("left", participant: bob)])
        XCTAssertEqual(manager.tiles.map(\.name), ["You"])
        manager.handle(media: .participantConnected(bob))
        manager.handle(media: .participantDisconnected(bob))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(core.gone, [bob], "a participant the media server says is gone counts as having left")
        XCTAssertEqual(manager.tiles.map(\.name), ["You"])
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
        XCTAssertEqual(mine?.title(startedBy: nil), "You started a call")
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
}
