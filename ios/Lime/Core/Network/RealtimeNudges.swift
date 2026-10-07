import Foundation

/// The "new items" nudge: one private Supabase Realtime channel per device (`device:<id>`), carrying
/// no content. A nudge only means "fetch your mailbox now"; the fetch is what delivers anything. This
/// speaks the Phoenix channel protocol (JSON, version 1) over a `URLSessionWebSocketTask`, so no SDK
/// is needed. It reconnects with a growing pause, and only the device's owner may join the channel
/// (the server checks the token against its devices).
actor RealtimeNudges {
    /// What the server sends or expects, one JSON object per frame.
    struct Frame: Codable, Equatable {
        var topic: String
        var event: String
        var payload: [String: JSONValue]
        var ref: String?
    }

    typealias TokenProvider = @Sendable () async throws -> String

    private let baseURL: URL
    private let apiKey: String
    private let deviceID: String
    private let token: TokenProvider
    private let onNudge: @Sendable () -> Void
    private var loop: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    /// True once the server accepted the join (tests and the About screen read it).
    private(set) var isJoined = false

    init(baseURL: URL, apiKey: String, deviceID: String, token: @escaping TokenProvider, onNudge: @escaping @Sendable () -> Void) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.deviceID = deviceID
        self.token = token
        self.onNudge = onNudge
    }

    var topic: String { "realtime:device:\(deviceID)" }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            var pause: UInt64 = 1
            while !Task.isCancelled {
                guard let self else { return }
                let joined = await self.runOnce()
                pause = joined ? 1 : min(pause * 2, 30)
                try? await Task.sleep(for: .seconds(pause))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        isJoined = false
    }

    /// One connection, until it ends. Returns whether the join succeeded (so the pause resets).
    private func runOnce() async -> Bool {
        guard let url = Self.socketURL(baseURL: baseURL, apiKey: apiKey), let accessToken = try? await token() else { return false }
        let task = URLSession(configuration: .ephemeral).webSocketTask(with: url)
        socket = task
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
            isJoined = false
        }
        guard await send(Self.joinFrame(deviceID: deviceID, accessToken: accessToken), on: task) else { return false }

        let heartbeat = Task { [weak task] in
            var n = 100
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                n += 1
                guard let task, let data = try? JSONEncoder().encode(Frame(topic: "phoenix", event: "heartbeat", payload: [:], ref: String(n))),
                      let text = String(data: data, encoding: .utf8) else { return }
                try? await task.send(.string(text))
            }
        }
        defer { heartbeat.cancel() }

        var joined = false
        while !Task.isCancelled {
            guard let message = try? await task.receive() else { return joined }
            let data: Data?
            switch message {
            case .string(let text): data = text.data(using: .utf8)
            case .data(let bytes): data = bytes
            @unknown default: data = nil
            }
            guard let data, let frame = try? JSONDecoder().decode(Frame.self, from: data) else { continue }
            switch Self.interpret(frame, topic: topic) {
            case .joined: joined = true; isJoined = true
            case .refused: return false
            case .nudge: onNudge()
            case .ignore: break
            }
        }
        return joined
    }

    private func send(_ frame: Frame, on task: URLSessionWebSocketTask) async -> Bool {
        guard let data = try? JSONEncoder().encode(frame), let text = String(data: data, encoding: .utf8) else { return false }
        return (try? await task.send(.string(text))) != nil
    }

    // MARK: Pure helpers (unit tested)

    enum Interpretation: Equatable { case joined, refused, nudge, ignore }

    /// What a frame from the server means for this device's channel.
    static func interpret(_ frame: Frame, topic: String) -> Interpretation {
        guard frame.topic == topic else { return .ignore }
        switch frame.event {
        case "phx_reply":
            if case .string("ok")? = frame.payload["status"] { return .joined }
            return .refused
        case "phx_error", "phx_close":
            return .refused
        case "system":
            return isError(frame) ? .refused : .ignore
        case "broadcast":
            if case .string("new")? = frame.payload["event"] { return .nudge }
            return .ignore
        default:
            return .ignore
        }
    }

    private static func isError(_ frame: Frame) -> Bool {
        if case .string("error")? = frame.payload["status"] { return true }
        return false
    }

    static func joinFrame(deviceID: String, accessToken: String) -> Frame {
        Frame(
            topic: "realtime:device:\(deviceID)", event: "phx_join",
            payload: [
                "config": .object([
                    "broadcast": .object(["ack": .bool(false), "self": .bool(false)]),
                    "presence": .object(["key": .string("")]),
                    "postgres_changes": .array([]),
                    "private": .bool(true),
                ]),
                "access_token": .string(accessToken),
            ],
            ref: "1")
    }

    static func socketURL(baseURL: URL, apiKey: String) -> URL? {
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = baseURL.scheme == "http" ? "ws" : "wss"
        parts.path = "/realtime/v1/websocket"
        parts.queryItems = [URLQueryItem(name: "apikey", value: apiKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        return parts.url
    }
}

/// Enough JSON to talk to Realtime.
enum JSONValue: Codable, Equatable, Sendable {
    case string(String), bool(Bool), number(Double), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
