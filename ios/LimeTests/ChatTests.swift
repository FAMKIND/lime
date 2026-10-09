import XCTest
@testable import Lime

final class ChatTests: XCTestCase {
    // MARK: Realtime frames

    private func frame(_ event: String, _ payload: [String: JSONValue], topic: String = "realtime:device:abc") -> RealtimeNudges.Frame {
        RealtimeNudges.Frame(topic: topic, event: event, payload: payload, ref: nil)
    }

    func testTheJoinAsksForAPrivateChannelWithTheToken() throws {
        let join = RealtimeNudges.joinFrame(deviceID: "abc", accessToken: "jwt")
        XCTAssertEqual(join.topic, "realtime:device:abc")
        XCTAssertEqual(join.event, "phx_join")
        XCTAssertEqual(join.payload["access_token"], .string("jwt"))
        guard case .object(let config)? = join.payload["config"] else { return XCTFail("no config") }
        XCTAssertEqual(config["private"], .bool(true))
        // And it survives the JSON the server reads.
        let decoded = try JSONDecoder().decode(RealtimeNudges.Frame.self, from: JSONEncoder().encode(join))
        XCTAssertEqual(decoded, join)
    }

    func testFramesAreTurnedIntoNudgesJoinsAndRefusals() {
        let topic = "realtime:device:abc"
        XCTAssertEqual(RealtimeNudges.interpret(frame("phx_reply", ["status": .string("ok")]), topic: topic), .joined)
        XCTAssertEqual(RealtimeNudges.interpret(frame("phx_reply", ["status": .string("error")]), topic: topic), .refused)
        XCTAssertEqual(RealtimeNudges.interpret(frame("phx_close", [:]), topic: topic), .refused)
        XCTAssertEqual(RealtimeNudges.interpret(frame("system", ["status": .string("error"), "message": .string("You do not have permissions")]), topic: topic), .refused)
        XCTAssertEqual(RealtimeNudges.interpret(frame("system", ["status": .string("ok")]), topic: topic), .ignore)
        let nudge = frame("broadcast", ["event": .string("new"), "payload": .object(["type": .string("new")]), "type": .string("broadcast")])
        XCTAssertEqual(RealtimeNudges.interpret(nudge, topic: topic), .nudge)
        XCTAssertEqual(RealtimeNudges.interpret(frame("broadcast", ["event": .string("other")]), topic: topic), .ignore)
        XCTAssertEqual(RealtimeNudges.interpret(nudge, topic: "realtime:device:someone-else"), .ignore, "another channel's frames are ignored")
        XCTAssertEqual(RealtimeNudges.interpret(frame("phx_reply", ["status": .string("ok")], topic: "phoenix"), topic: topic), .ignore, "heartbeat replies")
    }

    func testTheSocketAddressIsSecureForAProjectAndPlainForTheLocalStack() throws {
        let hosted = try XCTUnwrap(RealtimeNudges.socketURL(baseURL: URL(string: "https://proj.supabase.co")!, apiKey: "k"))
        XCTAssertEqual(hosted.absoluteString, "wss://proj.supabase.co/realtime/v1/websocket?apikey=k&vsn=1.0.0")
        let local = try XCTUnwrap(RealtimeNudges.socketURL(baseURL: URL(string: "http://127.0.0.1:54321")!, apiKey: "k"))
        XCTAssertEqual(local.absoluteString, "ws://127.0.0.1:54321/realtime/v1/websocket?apikey=k&vsn=1.0.0")
    }

    // MARK: Models

    func testDeliveryStatesComeFromTheCoresLocalState() {
        XCTAssertEqual(DeliveryState(localState: "sending"), .sending)
        XCTAssertEqual(DeliveryState(localState: "sent"), .sent)
        XCTAssertEqual(DeliveryState(localState: "failed"), .failed)
        XCTAssertEqual(DeliveryState(localState: "sent_local"), .sent, "an older local-only message counts as sent")
        let mine = Message(MessageItem(id: "1", conversationId: "dm:x", senderId: nil, text: "hi", sentAt: 0, localState: "sending", attachments: [], edited: false, deleted: false, reactions: [], forwarded: false, linkPreview: nil, threadRoot: nil))
        XCTAssertEqual(mine.state, .sending)
        let theirs = Message(MessageItem(id: "2", conversationId: "dm:x", senderId: "x", text: "yo", sentAt: 0, localState: "received", attachments: [], edited: false, deleted: false, reactions: [], forwarded: false, linkPreview: nil, threadRoot: nil))
        XCTAssertEqual(theirs.state, .received)
    }

    func testARequestIsSetApartFromTheChats() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lime-chat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let core = try LimeStore.open(path: directory.appendingPathComponent("lime.db").path, key: Data(repeating: 7, count: 32))
        let id = try core.startDm(userId: "u-1", displayName: "Grace Hopper")
        let summaries = try core.listConversations()
        XCTAssertEqual(summaries.map(\.title), ["Grace Hopper"])
        XCTAssertEqual(Conversation(summaries[0], messages: []).isRequest, false)
        try core.blockSender(conversationId: id)
        XCTAssertTrue(try core.listConversations().isEmpty, "a blocked conversation is not listed")
    }

    @MainActor
    func testTheDemoSplitsRequestsFromChatsAndAcceptingMovesOne() async {
        let store = ConversationStore()
        store.loadDemo()
        XCTAssertEqual(store.requests.map(\.id), ["dm:ada"])
        XCTAssertEqual(store.chats.map(\.id), ["dm:sam", "dm:lee"])
        await store.accept("dm:ada")
        XCTAssertTrue(store.requests.isEmpty)
        XCTAssertEqual(Set(store.chats.map(\.id)), ["dm:ada", "dm:sam", "dm:lee"])
        await store.block("dm:ada")
        XCTAssertEqual(store.chats.map(\.id), ["dm:sam", "dm:lee"])
    }

    @MainActor
    func testOpeningAChatMarksItRead() async {
        let store = ConversationStore()
        store.loadDemo()
        XCTAssertEqual(store.conversation("dm:ada")?.unread, 1)
        await store.markRead("dm:ada")
        XCTAssertEqual(store.conversation("dm:ada")?.unread, 0)
    }

    func testAFoundPersonShowsUsernameAndSchool() {
        let person = FoundUser(userId: "u", displayName: "Grace Hopper", username: "grace.h", school: "Naval Academy", aboutEmoji: nil, aboutText: nil, isSelf: false)
        XCTAssertEqual(NewMessageSheet.detail(person), "@grace.h · Naval Academy")
        XCTAssertNil(NewMessageSheet.detail(FoundUser(userId: "u", displayName: "G", username: nil, school: "", aboutEmoji: nil, aboutText: nil, isSelf: false)))
    }

    // MARK: Avatars

    func testAnAvatarColourComesFromTheUserIdAndNothingElse() throws {
        // "abc" = 97 * 31^2 + 98 * 31 + 99 = 96354, and 96354 % 8 = 2. Fixed forever, on every phone.
        XCTAssertEqual(AvatarTone.tone(for: "abc"), 2)
        XCTAssertEqual(AvatarTone.tone(for: "abc"), AvatarTone.tone(for: "abc"))
        XCTAssertEqual(Person(id: "abc", name: "Anyone").tone, 2)
        XCTAssertEqual(Person(id: "abc", name: "Someone Else").tone, 2, "the name never changes the colour")
        for id in ["a91aae66-1111-4222-8333-444455556666", "d967a1e4-9999-4888-8777-666655554444", "u-1", ""] {
            XCTAssertTrue((0..<8).contains(AvatarTone.tone(for: id)))
        }

        // LimeCore colours the people of a conversation with the same rule: a search result, a chat
        // header, Messages and Requests therefore agree.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lime-tone-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let core = try LimeStore.open(path: directory.appendingPathComponent("lime.db").path, key: Data(repeating: 5, count: 32))
        for id in ["a91aae66-1111-4222-8333-444455556666", "d967a1e4-9999-4888-8777-666655554444", "u-1", "x"] {
            _ = try core.startDm(userId: id, displayName: "Some One")
            let member = try XCTUnwrap(core.listConversations().first { $0.id == "dm:\(id)" }?.members.first)
            XCTAssertEqual(Int(member.tone), AvatarTone.tone(for: id), id)
            XCTAssertEqual(Conversation(try XCTUnwrap(core.listConversations().first { $0.id == "dm:\(id)" }), messages: []).members.first?.tone,
                           Person(id: id, name: "Some One").tone)
        }
    }

    // MARK: Telling the truth about failures

    func testEachFailureHasItsOwnTrueMessage() {
        XCTAssertEqual(ConnectionProblem.from(StoreError.Unauthorized), .sessionEnded)
        XCTAssertEqual(ConnectionProblem.from(AuthError.notVerified), .sessionEnded)
        XCTAssertEqual(ConnectionProblem.from(StoreError.Network), .offline)
        XCTAssertEqual(ConnectionProblem.from(AuthError.network), .offline)
        XCTAssertEqual(ConnectionProblem.from(StoreError.RateLimited), .busy)
        XCTAssertEqual(ConnectionProblem.from(AuthError.rateLimited), .busy)
        XCTAssertEqual(ConnectionProblem.from(StoreError.Unavailable), .server)
        XCTAssertEqual(ConnectionProblem.from(AuthError.unavailable), .server)
        XCTAssertEqual(ConnectionProblem.from(StoreError.Rejected), .other)
        XCTAssertEqual(ConnectionProblem.sessionEnded.message, "Your session has ended. Please sign in again.")
        XCTAssertTrue(ConnectionProblem.sessionEnded.needsSignIn)
        XCTAssertFalse(ConnectionProblem.offline.needsSignIn)
        // "Check your connection" is for a real connection failure only.
        for problem in [ConnectionProblem.sessionEnded, .busy, .server, .other] {
            XCTAssertFalse(problem.message.lowercased().contains("connection"), "\(problem)")
        }
        XCTAssertTrue(ConnectionProblem.offline.message.lowercased().contains("connection"))
    }

    @MainActor
    func testTheStoreShowsAndClearsAProblem() {
        let store = ConversationStore()
        store.loadDemo()
        XCTAssertNil(store.problem)
        store.report(.sessionEnded)
        XCTAssertEqual(store.problem, .sessionEnded)
    }

    // MARK: One refresh at a time

    /// An auth service that counts refreshes (and takes a moment, so calls overlap).
    private final class CountingAuth: AuthService, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var refreshes: Int { lock.withLock { count } }
        private var unused: AuthError { .server("unused") }
        func identify(_ identifier: String) async throws -> IdentifyResult { throw unused }
        func signIn(identifier: String, password: String) async throws -> PasswordSignIn { throw unused }
        func verifySignInCode(_ code: String, tokens: AuthTokens) async throws { throw unused }
        func resendSignInCode(tokens: AuthTokens) async throws { throw unused }
        func startSignUp(email: String) async throws { throw unused }
        func verifySignUpCode(email: String, code: String) async throws -> AuthTokens { throw unused }
        func setInitialPassword(_ password: String, tokens: AuthTokens) async throws -> AuthTokens { throw unused }
        func startReset(identifier: String) async throws { throw unused }
        func finishReset(identifier: String, code: String, newPassword: String) async throws -> AuthTokens { throw unused }
        func startPasswordChange(current: String, tokens: AuthTokens) async throws { throw unused }
        func finishPasswordChange(code: String, newPassword: String, tokens: AuthTokens) async throws -> AuthTokens { throw unused }
        func saveProfile(_ draft: ProfileDraft, tokens: AuthTokens) async throws -> Profile { throw unused }
        func loadProfile(tokens: AuthTokens) async throws -> Profile? { nil }
        func signOut(tokens: AuthTokens) async {}
        func refresh(_ tokens: AuthTokens) async throws -> AuthTokens {
            let n = lock.withLock { count += 1; return count }
            try await Task.sleep(for: .milliseconds(150))
            return AuthTokens(accessToken: "fresh-\(n)", refreshToken: "refresh-\(n)", expiresAt: Date().addingTimeInterval(3600), userID: tokens.userID)
        }
    }

    @MainActor
    func testCallsThatArriveTogetherShareOneRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lime-refresh-\(UUID().uuidString)", isDirectory: true)
        let location = StorageBootstrap.Location(directory: directory, keychainService: "app.lime.tests.refresh.\(UUID().uuidString)")
        let sessionService = "app.lime.tests.refresh.session.\(UUID().uuidString)"
        defer {
            StorageKeychain.deleteKey(service: location.keychainService)
            SessionKeychain.clear(service: sessionService)
            try? FileManager.default.removeItem(at: directory)
        }
        let auth = CountingAuth()
        let session = AccountSession(auth: auth, config: nil, store: ConversationStore(storageLocation: location),
                                     sessionService: sessionService, defaults: UserDefaults(suiteName: "lime-refresh-\(UUID().uuidString)")!)
        let stale = AuthTokens(accessToken: "stale", refreshToken: "r0", expiresAt: Date().addingTimeInterval(-10), userID: "u")
        await session.completeSignIn(tokens: stale, profile: nil)
        async let first = session.accessToken()
        async let second = session.accessToken()
        async let third = session.accessToken()
        let tokens = try await [first, second, third]
        XCTAssertEqual(tokens, ["fresh-1", "fresh-1", "fresh-1"])
        XCTAssertEqual(auth.refreshes, 1, "a refresh token is single-use: one refresh serves everyone")
        let again = try await session.accessToken()
        XCTAssertEqual(again, "fresh-1", "and it is not refreshed again while it is good")
        XCTAssertEqual(auth.refreshes, 1)
    }

    @MainActor
    func testEndingASessionKeepsTheChatsAndASecondAccountNeverSeesThem() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lime-end-\(UUID().uuidString)", isDirectory: true)
        let location = StorageBootstrap.Location(directory: directory, keychainService: "app.lime.tests.end.\(UUID().uuidString)")
        let sessionService = "app.lime.tests.end.session.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: "lime-end-\(UUID().uuidString)")!
        defer {
            StorageKeychain.deleteKey(service: location.keychainService)
            SessionKeychain.clear(service: sessionService)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ConversationStore(storageLocation: location)
        let session = AccountSession(auth: CountingAuth(), config: nil, store: store, sessionService: sessionService, defaults: defaults)
        let mine = AuthTokens(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), userID: "user-1")
        await session.completeSignIn(tokens: mine, profile: nil)
        let id = try XCTUnwrap(store.core).startDmForTest("user-2")
        await store.reload()
        XCTAssertEqual(store.conversations.map(\.id), [id])

        // The server stopped accepting the session: sign in again as the same person, nothing lost.
        await session.endSession()
        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertEqual(store.conversations.map(\.id), [id], "the chats stay on the phone")
        await session.completeSignIn(tokens: mine, profile: nil)
        XCTAssertEqual(store.conversations.map(\.id), [id])

        // A different person signing in on this phone never gets someone else's chats.
        await session.endSession()
        let other = AuthTokens(accessToken: "b", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), userID: "user-9")
        await session.completeSignIn(tokens: other, profile: nil)
        XCTAssertTrue(store.conversations.isEmpty)
    }
}

private extension LimeStore {
    func startDmForTest(_ user: String) throws -> String {
        try startDm(userId: user, displayName: "Someone")
    }
}
