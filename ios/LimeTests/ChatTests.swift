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
        let mine = Message(MessageItem(id: "1", conversationId: "dm:x", senderId: nil, text: "hi", sentAt: 0, localState: "sending"))
        XCTAssertEqual(mine.state, .sending)
        let theirs = Message(MessageItem(id: "2", conversationId: "dm:x", senderId: "x", text: "yo", sentAt: 0, localState: "received"))
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
        XCTAssertEqual(store.chats.map(\.id), ["dm:sam"])
        await store.accept("dm:ada")
        XCTAssertTrue(store.requests.isEmpty)
        XCTAssertEqual(Set(store.chats.map(\.id)), ["dm:ada", "dm:sam"])
        await store.block("dm:ada")
        XCTAssertEqual(store.chats.map(\.id), ["dm:sam"])
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
        let person = FoundUser(userId: "u", displayName: "Grace Hopper", username: "grace.h", school: "Naval Academy", isSelf: false)
        XCTAssertEqual(NewMessageSheet.detail(person), "@grace.h · Naval Academy")
        XCTAssertNil(NewMessageSheet.detail(FoundUser(userId: "u", displayName: "G", username: nil, school: "", isSelf: false)))
    }
}
