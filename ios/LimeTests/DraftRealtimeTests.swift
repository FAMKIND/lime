import XCTest
@testable import Lime

/// LIME-233b: the instant path's frames (public channel, no token, opaque bytes both ways).
final class DraftRealtimeTests: XCTestCase {
    func testTheJoinIsPublicAndCarriesNoToken() throws {
        let frame = DraftRealtime.joinFrame(channel: "abc123", ref: "1")
        XCTAssertEqual(frame.topic, "realtime:draft:abc123")
        XCTAssertEqual(frame.event, "phx_join")
        let json = String(data: try JSONEncoder().encode(frame), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"private\":false"), json)
        XCTAssertFalse(json.contains("access_token"), "no user token")
    }

    func testABroadcastCarriesTheWireAndComesBackAsTheSameBytes() throws {
        let wire = Data((0..<40).map { UInt8($0) })
        let sent = DraftRealtime.broadcastFrame(channel: "abc123", wire: wire, ref: "2")
        XCTAssertEqual(DraftRealtime.interpret(sent), .wire("abc123", wire))
    }

    func testOtherTopicsAndRefusalsAreRecognised() {
        XCTAssertEqual(DraftRealtime.interpret(.init(topic: "realtime:device:xyz", event: "broadcast", payload: [:], ref: nil)), .ignore)
        XCTAssertEqual(DraftRealtime.interpret(.init(topic: "realtime:draft:c", event: "phx_reply", payload: ["status": .string("error")], ref: "1")), .refused("c"))
        XCTAssertEqual(DraftRealtime.interpret(.init(topic: "realtime:draft:c", event: "phx_reply", payload: ["status": .string("ok")], ref: "1")), .joined("c"))
        XCTAssertEqual(DraftRealtime.interpret(.init(topic: "realtime:draft:c", event: "broadcast", payload: ["payload": .object(["w": .string("###")])], ref: nil)), .ignore)
    }

    func testTheSocketURLIsSecureAndUsesThePublicKey() {
        let url = DraftRealtime.socketURL(baseURL: URL(string: "https://x.supabase.co")!, apiKey: "pub")
        XCTAssertEqual(url?.absoluteString, "wss://x.supabase.co/realtime/v1/websocket?apikey=pub&vsn=1.0.0")
    }
}
