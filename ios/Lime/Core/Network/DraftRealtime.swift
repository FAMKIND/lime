import Foundation

/// The instant path of a draft written with others (LIME-233b, DESIGN-22 §2): a public Supabase Realtime **broadcast** channel per draft,
/// `draft:<random 128-bit id>`, joined with the **public API key only, no user token**, so the server cannot tie a channel to an account. Every message
/// is encrypted with the draft's key and signed by the author's device in LimeCore (`draft_instant_*`); this class only carries opaque bytes.
/// Anything that fails to decrypt or verify is dropped by the core. The relay stores nothing. It speaks the Phoenix channel protocol like `RealtimeNudges`
/// and reconnects with a growing pause.
actor DraftRealtime {
    private let baseURL: URL
    private let apiKey: String
    private let onWire: @Sendable (_ channel: String, _ wire: Data) -> Void
    private var channels: Set<String> = []
    private var loop: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var joined: Set<String> = []
    private var counter = 0

    init(baseURL: URL, apiKey: String, onWire: @escaping @Sendable (String, Data) -> Void) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.onWire = onWire
    }

    /// The channels to be in (joins the new ones, leaves the others).
    func setChannels(_ wanted: Set<String>) async {
        channels = wanted
        if let socket {
            for channel in wanted.subtracting(joined) { await send(Self.joinFrame(channel: channel, ref: nextRef()), on: socket) }
        }
        if wanted.isEmpty { stop() } else { start() }
    }

    func start() {
        guard loop == nil, !channels.isEmpty else { return }
        loop = Task { [weak self] in
            var pause: UInt64 = 1
            while !Task.isCancelled {
                guard let self else { return }
                let ok = await self.runOnce()
                pause = ok ? 1 : min(pause * 2, 30)
                try? await Task.sleep(for: .seconds(pause))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        joined = []
    }

    /// Broadcasts one wire message to everyone on the channel. False when the socket is not up (the durable path covers it a moment later).
    @discardableResult
    func broadcast(channel: String, wire: Data) async -> Bool {
        guard let socket, joined.contains(channel) else { return false }
        return await send(Self.broadcastFrame(channel: channel, wire: wire, ref: nextRef()), on: socket)
    }

    private func nextRef() -> String {
        counter += 1
        return String(counter)
    }

    private func runOnce() async -> Bool {
        guard let url = Self.socketURL(baseURL: baseURL, apiKey: apiKey) else { return false }
        let task = URLSession(configuration: .ephemeral).webSocketTask(with: url)
        socket = task
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
            joined = []
            if socket === task { socket = nil }
        }
        for channel in channels { await send(Self.joinFrame(channel: channel, ref: nextRef()), on: task) }
        let heartbeat = Task { [weak task] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard let task, let data = try? JSONEncoder().encode(RealtimeNudges.Frame(topic: "phoenix", event: "heartbeat", payload: [:], ref: "hb")),
                      let text = String(data: data, encoding: .utf8) else { return }
                try? await task.send(.string(text))
            }
        }
        defer { heartbeat.cancel() }
        var ever = false
        while !Task.isCancelled {
            guard let message = try? await task.receive() else { return ever }
            let data: Data?
            switch message {
            case .string(let text): data = text.data(using: .utf8)
            case .data(let bytes): data = bytes
            @unknown default: data = nil
            }
            guard let data, let frame = try? JSONDecoder().decode(RealtimeNudges.Frame.self, from: data) else { continue }
            switch Self.interpret(frame) {
            case .joined(let channel): joined.insert(channel); ever = true
            case .wire(let channel, let bytes): onWire(channel, bytes)
            case .refused(let channel): joined.remove(channel)
            case .ignore: break
            }
        }
        return ever
    }

    @discardableResult
    private func send(_ frame: RealtimeNudges.Frame, on task: URLSessionWebSocketTask) async -> Bool {
        guard let data = try? JSONEncoder().encode(frame), let text = String(data: data, encoding: .utf8) else { return false }
        return (try? await task.send(.string(text))) != nil
    }

    // MARK: Pure helpers (unit tested)

    enum Interpretation: Equatable {
        case joined(String), refused(String), wire(String, Data), ignore
    }

    static func topic(for channel: String) -> String { "realtime:draft:\(channel)" }

    static func channel(of topic: String) -> String? {
        topic.hasPrefix("realtime:draft:") ? String(topic.dropFirst("realtime:draft:".count)) : nil
    }

    /// Public, not private: no token. The sender does not hear its own messages.
    static func joinFrame(channel: String, ref: String) -> RealtimeNudges.Frame {
        RealtimeNudges.Frame(
            topic: topic(for: channel), event: "phx_join",
            payload: ["config": .object(["broadcast": .object(["self": .bool(false), "ack": .bool(false)]), "presence": .object(["key": .string("")]), "private": .bool(false)])],
            ref: ref)
    }

    static func broadcastFrame(channel: String, wire: Data, ref: String) -> RealtimeNudges.Frame {
        RealtimeNudges.Frame(
            topic: topic(for: channel), event: "broadcast",
            payload: ["type": .string("broadcast"), "event": .string("d"), "payload": .object(["w": .string(wire.base64EncodedString())])],
            ref: ref)
    }

    static func interpret(_ frame: RealtimeNudges.Frame) -> Interpretation {
        guard let channel = channel(of: frame.topic) else { return .ignore }
        switch frame.event {
        case "phx_reply":
            if case .string("ok")? = frame.payload["status"] { return frame.ref == nil || frame.ref == "hb" ? .ignore : .joined(channel) }
            return .refused(channel)
        case "phx_error", "phx_close": return .refused(channel)
        case "broadcast":
            if case .object(let inner)? = frame.payload["payload"], case .string(let text)? = inner["w"], let bytes = Data(base64Encoded: text) {
                return .wire(channel, bytes)
            }
            return .ignore
        default: return .ignore
        }
    }

    static func socketURL(baseURL: URL, apiKey: String) -> URL? {
        guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = parts.scheme == "http" ? "ws" : "wss"
        parts.path = "/realtime/v1/websocket"
        parts.queryItems = [URLQueryItem(name: "apikey", value: apiKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        return parts.url
    }
}
