import Foundation
import Network

/// What the two phones say to each other while one moves to the other (LIME-272b). The chunks are already sealed by LimeCore (272a); this
/// is only the carrier, so it can be a direct connection, or a pair of in-memory ends for tests and the demo.
enum MoveMessage: Equatable, Sendable {
    /// Old phone to new: its answer to the QR.
    case hello(Data)
    /// New phone to old: the person confirmed the code there.
    case ready
    /// Old phone to new: the next sealed chunk.
    case chunk(Data)
    /// Old phone to new: that was the last chunk.
    case finished
    /// New phone to old: it holds everything (the proof LimeCore checks).
    case proof(Data)
    /// Either side: stop.
    case cancel

    private var tag: UInt8 {
        switch self {
        case .hello: 1
        case .ready: 2
        case .chunk: 3
        case .finished: 4
        case .proof: 5
        case .cancel: 6
        }
    }

    private var payload: Data {
        switch self {
        case .hello(let d), .chunk(let d), .proof(let d): d
        case .ready, .finished, .cancel: Data()
        }
    }

    /// `length (4, big endian) || tag || payload`.
    var framed: Data {
        var out = Data()
        var length = UInt32(payload.count + 1).bigEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(tag)
        out.append(payload)
        return out
    }

    /// The most a single message may hold (a chunk is 256 KiB plus its seal): anything bigger is refused.
    static let maxBody = 1 << 20

    static func decode(tag: UInt8, payload: Data) -> MoveMessage? {
        switch tag {
        case 1: .hello(payload)
        case 2: .ready
        case 3: .chunk(payload)
        case 4: .finished
        case 5: .proof(payload)
        case 6: .cancel
        default: nil
        }
    }
}

enum MoveChannelError: Error, Equatable {
    case closed
    case badMessage
    case timedOut
}

/// One end of the connection between the phones.
protocol MoveChannel: AnyObject, Sendable {
    func send(_ message: MoveMessage) async throws
    /// The next message; throws `closed` when the other end went away.
    func receive() async throws -> MoveMessage
    func close()
}

// MARK: In memory (tests and the demo)

/// Two ends joined in memory: what one sends the other receives, in order.
final class LoopbackMoveChannel: MoveChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [MoveMessage] = []
    private var waiting: CheckedContinuation<MoveMessage, Error>?
    private var closed = false
    private weak var peer: LoopbackMoveChannel?

    static func pair() -> (LoopbackMoveChannel, LoopbackMoveChannel) {
        let a = LoopbackMoveChannel(), b = LoopbackMoveChannel()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    func send(_ message: MoveMessage) async throws {
        guard let peer, !closed else { throw MoveChannelError.closed }
        peer.deliver(message)
    }

    fileprivate func deliver(_ message: MoveMessage) {
        lock.lock()
        if let waiting {
            self.waiting = nil
            lock.unlock()
            waiting.resume(returning: message)
        } else {
            queue.append(message)
            lock.unlock()
        }
    }

    func receive() async throws -> MoveMessage {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !queue.isEmpty {
                let next = queue.removeFirst()
                lock.unlock()
                continuation.resume(returning: next)
            } else if closed {
                lock.unlock()
                continuation.resume(throwing: MoveChannelError.closed)
            } else {
                waiting = continuation
                lock.unlock()
            }
        }
    }

    func close() {
        lock.lock()
        let wasClosed = closed
        closed = true
        let waiting = self.waiting
        self.waiting = nil
        lock.unlock()
        waiting?.resume(throwing: MoveChannelError.closed)
        if !wasClosed { peer?.peerClosed() }
    }

    fileprivate func peerClosed() {
        lock.lock()
        closed = true
        let waiting = self.waiting
        self.waiting = nil
        lock.unlock()
        waiting?.resume(throwing: MoveChannelError.closed)
    }
}

// MARK: A direct connection (Network framework, Wi-Fi or peer to peer)

/// A TCP connection with length-prefixed messages. The content is already encrypted end to end by the session key from the QR, so the link
/// itself needs no certificate: a stranger who connects first learns nothing and cannot make a hello that verifies.
final class NetworkMoveChannel: MoveChannel, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "lime.move.channel")

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    /// Starts the connection and returns once it is ready (or throws if it fails or the wait runs out).
    func start(timeout: TimeInterval) async throws {
        final class Once: @unchecked Sendable { var done = false }
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let finish: @Sendable (Result<Void, Error>) -> Void = { result in
                self.queue.async {
                    guard !once.done else { return }
                    once.done = true
                    continuation.resume(with: result)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(()))
                case .failed, .cancelled: finish(.failure(MoveChannelError.closed))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(MoveChannelError.timedOut)) }
        }
    }

    func send(_ message: MoveMessage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: message.framed, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func receive() async throws -> MoveMessage {
        let head = try await read(4)
        let length = Int(head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
        guard length >= 1, length <= MoveMessage.maxBody else { throw MoveChannelError.badMessage }
        let body = try await read(length)
        guard let message = MoveMessage.decode(tag: body[body.startIndex], payload: body.dropFirst()) else { throw MoveChannelError.badMessage }
        return message
    }

    private func read(_ count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let data, data.count == count { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? MoveChannelError.closed) }
            }
        }
    }

    func close() { connection.cancel() }
}

// MARK: Finding each other

enum MoveBonjour {
    static let type = "_lime-move._tcp"

    /// The service name both phones use for one move: a hash of the QR's text, so only the phone that scanned it looks for this one.
    static func serviceName(for qr: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in qr.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return "lime-" + String(hash, radix: 16)
    }

    static func parameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// The new phone waits for the old one to connect (one connection; a second is refused).
final class MoveListener: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "lime.move.listener")
    private var continuation: CheckedContinuation<NetworkMoveChannel, Error>?
    private var accepted = false

    init(qr: String) throws {
        listener = try NWListener(using: MoveBonjour.parameters())
        listener.service = NWListener.Service(name: MoveBonjour.serviceName(for: qr), type: MoveBonjour.type)
    }

    /// The first connection that arrives.
    func accept(timeout: TimeInterval) async throws -> NetworkMoveChannel {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NetworkMoveChannel, Error>) in
            queue.async {
                self.continuation = continuation
                self.listener.newConnectionHandler = { [weak self] connection in
                    guard let self, !self.accepted, let continuation = self.continuation else { connection.cancel(); return }
                    self.accepted = true
                    self.continuation = nil
                    let channel = NetworkMoveChannel(connection)
                    Task {
                        do { try await channel.start(timeout: 10); continuation.resume(returning: channel) }
                        catch { continuation.resume(throwing: error) }
                    }
                }
                self.listener.stateUpdateHandler = { [weak self] state in
                    if case .failed = state, let continuation = self?.continuation {
                        self?.continuation = nil
                        continuation.resume(throwing: MoveChannelError.closed)
                    }
                }
                self.listener.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    guard let self, let continuation = self.continuation else { return }
                    self.continuation = nil
                    continuation.resume(throwing: MoveChannelError.timedOut)
                }
            }
        }
    }

    func stop() { listener.cancel() }
}

/// The old phone looks for the new phone's service (named from the QR it scanned) and connects.
final class MoveBrowser: @unchecked Sendable {
    private let name: String
    private let queue = DispatchQueue(label: "lime.move.browser")
    private var browser: NWBrowser?

    init(qr: String) { name = MoveBonjour.serviceName(for: qr) }

    func connect(timeout: TimeInterval) async throws -> NetworkMoveChannel {
        let endpoint: NWEndpoint = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWEndpoint, Error>) in
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            let browser = NWBrowser(for: .bonjour(type: MoveBonjour.type, domain: nil), using: MoveBonjour.parameters())
            self.browser = browser
            let name = self.name
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    if case .service(let found, _, _, _) = result.endpoint, found == name, !once.done {
                        once.done = true
                        continuation.resume(returning: result.endpoint)
                        return
                    }
                }
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state, !once.done { once.done = true; continuation.resume(throwing: MoveChannelError.closed) }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                if !once.done { once.done = true; continuation.resume(throwing: MoveChannelError.timedOut) }
            }
        }
        browser?.cancel()
        let channel = NetworkMoveChannel(NWConnection(to: endpoint, using: MoveBonjour.parameters()))
        try await channel.start(timeout: 10)
        return channel
    }

    func stop() { browser?.cancel() }
}
