import Foundation
import Observation

// MARK: The engines (LimeCore's LinkNew / LinkOld, or fakes for the demo and the tests)

/// The new device's side of a link (LIME-343a): what `LinkNew` and the steps around it (register, refresh, the 45 days) do.
protocol LinkNewEngine: AnyObject, Sendable {
    var qr: String { get }
    func acceptHello(_ hello: Data) throws
    func checkCode() throws -> String
    func confirmCode()
    func importChunk(_ chunk: Data) throws
    func progress() -> LinkProgress
    /// Applies the package (all or nothing).
    func importFinish() throws
    /// Registers this device and refreshes my list of devices.
    func registerAndRefresh() async throws
    /// Downloads and imports the last 45 days (after the pointer came); `nil` when there was none.
    func importHistory() async throws -> HistoryImported?
    func historyProgress() -> HistoryProgress
    /// Lets go of the store so the app can open it.
    func release()
    func abort()
}

/// The phone's (or tablet's) side.
protocol LinkOldEngine: AnyObject, Sendable {
    func hello() -> Data
    func checkCode() -> String
    func confirmCode()
    func exportNextChunk() throws -> Data?
    func progress() -> LinkProgress
    func refreshDevices() async throws
    /// The sealed pointer to the history file (builds, seals and uploads it).
    func historyChunk() async throws -> Data
    func historyProgress() -> HistoryProgress
    func abort()
}

final class RealLinkNew: LinkNewEngine, @unchecked Sendable {
    private var core: LinkNew?
    private var store: LimeStore?
    private let transport: Transport
    private let token: @Sendable () async throws -> String
    private let lock = NSLock()
    init(core: LinkNew, store: LimeStore, transport: Transport, token: @escaping @Sendable () async throws -> String) { self.core = core; self.store = store; self.transport = transport; self.token = token }
    private func held() throws -> (LinkNew, LimeStore) {
        lock.lock(); defer { lock.unlock() }
        guard let core, let store else { throw StoreError.Rejected }
        return (core, store)
    }
    var qr: String { (try? held().0.qr()) ?? "" }
    func acceptHello(_ hello: Data) throws { try held().0.acceptHello(hello: hello) }
    func checkCode() throws -> String { try held().0.checkCode() }
    func confirmCode() { try? held().0.confirmCode() }
    func importChunk(_ chunk: Data) throws { try held().0.importChunk(chunk: chunk) }
    func progress() -> LinkProgress {
        guard let core = try? held().0 else { return LinkProgress(done: 0, total: 0) }
        let p = core.progress()
        return LinkProgress(done: p.done, total: p.total)
    }
    func importFinish() throws { _ = try held().0.importFinish() }
    func registerAndRefresh() async throws {
        let (_, store) = try held()
        let transport = self.transport, token = try await self.token()
        try await Task.detached(priority: .userInitiated) {
            _ = try store.registerDevice(transport: transport, authToken: token)
            _ = try store.linkRefreshDevices(transport: transport, authToken: token)
        }.value
    }
    func importHistory() async throws -> HistoryImported? {
        let (core, _) = try held()
        guard core.historyPending() else { return nil }
        let transport = self.transport, token = try await self.token()
        return try await Task.detached(priority: .userInitiated) { try core.importHistory(transport: transport, authToken: token) }.value
    }
    func historyProgress() -> HistoryProgress { (try? held().0.historyProgress()) ?? HistoryProgress(step: "idle", done: 0, total: 0) }
    func release() { lock.lock(); core = nil; store = nil; lock.unlock() }
    func abort() { try? held().0.abort() }
}

final class RealLinkOld: LinkOldEngine, @unchecked Sendable {
    private let core: LinkOld
    private let store: LimeStore
    private let transport: Transport
    private let token: @Sendable () async throws -> String
    init(core: LinkOld, store: LimeStore, transport: Transport, token: @escaping @Sendable () async throws -> String) { self.core = core; self.store = store; self.transport = transport; self.token = token }
    func hello() -> Data { core.hello() }
    func checkCode() -> String { core.checkCode() }
    func confirmCode() { core.confirmCode() }
    func exportNextChunk() throws -> Data? { try core.exportNextChunk() }
    func progress() -> LinkProgress { let p = core.progress(); return LinkProgress(done: p.done, total: p.total) }
    func refreshDevices() async throws {
        let (store, transport, token) = (self.store, self.transport, try await token())
        _ = try await Task.detached(priority: .userInitiated) { try store.linkRefreshDevices(transport: transport, authToken: token) }.value
    }
    func historyChunk() async throws -> Data {
        let (core, transport, token) = (self.core, self.transport, try await token())
        return try await Task.detached(priority: .userInitiated) { try core.historyChunk(transport: transport, authToken: token) }.value
    }
    func historyProgress() -> HistoryProgress { core.historyProgress() }
    func abort() { core.abort() }
}

// MARK: What the screens show

enum LinkFailure: Equatable {
    case cantConnect
    case dropped
    case stoppedByOther
    case wrongCode
    /// The account already has 5 devices.
    case tooManyDevices
    case failed
}

/// Where a link has got: the phases the two screens show.
enum LinkStep: Equatable {
    /// "Getting your chats": the package.
    case package
    /// "Getting the last 45 days": the history file.
    case history
}

// MARK: The new device

/// The new device's side: shows the QR, waits for the phone, shows the check code, takes the package, registers, then gets the last 45 days.
@MainActor
@Observable
final class LinkToThisDevice {
    enum Phase: Equatable { case waiting, compare(String), receiving(LinkStep), done, failed(LinkFailure) }

    private(set) var phase: Phase = .waiting
    private(set) var progress = MoveProgressInfo()
    /// The 45 days could not be imported: the device works, without that history (said once, after).
    private(set) var historyMissing = false
    let engine: any LinkNewEngine
    private let accept: @Sendable () async throws -> any MoveChannel
    private let stop: @Sendable () -> Void
    private let cleanup: @Sendable () -> Void
    private var channel: (any MoveChannel)?
    private var task: Task<Void, Never>?
    private var decision: CheckedContinuation<Bool, Never>?

    var qr: String { engine.qr }

    init(engine: any LinkNewEngine, accept: @escaping @Sendable () async throws -> any MoveChannel, stop: @escaping @Sendable () -> Void = {}, cleanup: @escaping @Sendable () -> Void = {}) {
        self.engine = engine
        self.accept = accept
        self.stop = stop
        self.cleanup = cleanup
    }

    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    func matches() { decision?.resume(returning: true); decision = nil }

    /// "They don't match", or Cancel: stop and throw away what was received (and the empty store made for it).
    func cancel() {
        decision?.resume(returning: false)
        decision = nil
        task?.cancel()
        let channel = self.channel
        Task { try? await channel?.send(.cancel); channel?.close() }
        engine.abort()
        engine.release()
        stop()
        if phase != .done { cleanup() }
    }

    private func run() async {
        let engine = self.engine
        do {
            let channel = try await accept()
            self.channel = channel
            guard case .hello(let hello) = try await channel.receive() else { throw MoveChannelError.badMessage }
            try engine.acceptHello(hello)
            phase = .compare(try engine.checkCode())
            guard await withCheckedContinuation({ decision = $0 }) else { return finish(.stoppedByOther, tell: true) }
            engine.confirmCode()
            try await channel.send(.ready)
            phase = .receiving(.package)
            let pace = LinkPace()
            packages: while true {
                switch try await channel.receive() {
                case .chunk(let chunk):
                    try await Task.detached { try engine.importChunk(chunk) }.value
                    let p = engine.progress()
                    progress = MoveProgressInfo(done: p.done, total: p.total, secondsLeft: pace.secondsLeft(done: p.done, total: p.total))
                case .finished:
                    try await Task.detached { try engine.importFinish() }.value
                    break packages
                case .cancel:
                    return finish(.stoppedByOther, tell: false)
                default:
                    throw MoveChannelError.badMessage
                }
            }
            // This device joins the account, then the phone sends where the history is.
            do { try await engine.registerAndRefresh() } catch StoreError.TooManyDevices { return finish(.tooManyDevices, tell: true) }
            try await channel.send(.registered)
            phase = .receiving(.history)
            progress = MoveProgressInfo()
            history: while true {
                switch try await channel.receive() {
                case .chunk(let pointer):
                    try await Task.detached { try engine.importChunk(pointer) }.value
                case .finished:
                    break history
                case .cancel:
                    historyMissing = true
                    break history
                default:
                    throw MoveChannelError.badMessage
                }
            }
            let watcher = Task { @MainActor in
                while !Task.isCancelled {
                    let h = engine.historyProgress()
                    progress = MoveProgressInfo(done: h.done, total: h.total)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
            do { if try await engine.importHistory() == nil { historyMissing = true } } catch { historyMissing = true }
            watcher.cancel()
            try? await channel.send(.done)
            engine.release()
            phase = .done
            channel.close()
            stop()
        } catch MoveChannelError.timedOut {
            finish(.cantConnect, tell: false)
        } catch MoveChannelError.closed {
            finish(.dropped, tell: false)
        } catch {
            finish(.failed, tell: true)
        }
    }

    private func finish(_ failure: LinkFailure, tell: Bool) {
        guard phase != .done else { return }
        engine.abort()
        engine.release()
        phase = .failed(failure)
        let channel = self.channel
        Task { if tell { try? await channel?.send(.cancel) }; channel?.close() }
        stop()
        cleanup()
    }
}

// MARK: The phone

/// The phone's side: finds the new device, shows the check code, needs Face ID or the passcode before it goes on, sends the package, then the 45 days.
@MainActor
@Observable
final class LinkFromPhone {
    enum Phase: Equatable { case connecting, compare(String), waitingForOther, sending(LinkStep), done, failed(LinkFailure) }

    private(set) var phase: Phase = .connecting
    private(set) var progress = MoveProgressInfo()
    /// Face ID or the passcode was not passed: still at the code, nothing was sent.
    private(set) var notYou = false
    /// The last 45 days could not be sent: the device is linked without them.
    private(set) var historyMissing = false
    private let engine: any LinkOldEngine
    private let connect: @Sendable () async throws -> any MoveChannel
    private let authenticate: @Sendable () async -> Bool
    private let linked: @MainActor () -> Void
    private let stop: @Sendable () -> Void
    private var channel: (any MoveChannel)?
    private var task: Task<Void, Never>?
    private var decision: CheckedContinuation<Bool, Never>?

    init(engine: any LinkOldEngine, connect: @escaping @Sendable () async throws -> any MoveChannel, authenticate: @escaping @Sendable () async -> Bool,
         linked: @escaping @MainActor () -> Void = {}, stop: @escaping @Sendable () -> Void = {}) {
        self.engine = engine
        self.connect = connect
        self.authenticate = authenticate
        self.linked = linked
        self.stop = stop
    }

    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// "They match": Face ID or the passcode first (LIME-343a); only then does the code count.
    func matches() {
        let authenticate = self.authenticate
        Task { @MainActor in
            if await authenticate() {
                notYou = false
                decision?.resume(returning: true)
                decision = nil
            } else {
                notYou = true
            }
        }
    }

    func cancel() {
        decision?.resume(returning: false)
        decision = nil
        task?.cancel()
        let channel = self.channel
        Task { try? await channel?.send(.cancel); channel?.close() }
        engine.abort()
        stop()
    }

    private func run() async {
        let engine = self.engine
        do {
            let channel = try await connect()
            self.channel = channel
            try await channel.send(.hello(engine.hello()))
            phase = .compare(engine.checkCode())
            guard await withCheckedContinuation({ decision = $0 }) else { return finish(.stoppedByOther, tell: true) }
            engine.confirmCode()
            phase = .waitingForOther
            switch try await channel.receive() {
            case .ready: break
            case .cancel: return finish(.stoppedByOther, tell: false)
            default: throw MoveChannelError.badMessage
            }
            phase = .sending(.package)
            let pace = LinkPace()
            while let chunk = try await Task.detached(operation: { try engine.exportNextChunk() }).value {
                try await channel.send(.chunk(chunk))
                let p = engine.progress()
                progress = MoveProgressInfo(done: p.done, total: p.total, secondsLeft: pace.secondsLeft(done: p.done, total: p.total))
            }
            try await channel.send(.finished)
            // The new device registers; then both lists are refreshed and the history goes.
            switch try await channel.receive() {
            case .registered: break
            case .cancel: return finish(.tooManyDevices, tell: false)
            default: throw MoveChannelError.badMessage
            }
            phase = .sending(.history)
            progress = MoveProgressInfo()
            try? await engine.refreshDevices()
            let watcher = Task { @MainActor in
                while !Task.isCancelled {
                    let h = engine.historyProgress()
                    progress = MoveProgressInfo(done: h.done, total: h.total)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
            do { try await channel.send(.chunk(try await engine.historyChunk())) } catch { historyMissing = true }
            watcher.cancel()
            try await channel.send(.finished)
            guard case .done = try await channel.receive() else { throw MoveChannelError.badMessage }
            phase = .done
            channel.close()
            stop()
            linked()
        } catch MoveChannelError.timedOut {
            finish(.cantConnect, tell: false)
        } catch MoveChannelError.closed {
            finish(.dropped, tell: false)
        } catch {
            finish(.failed, tell: true)
        }
    }

    private func finish(_ failure: LinkFailure, tell: Bool) {
        guard phase != .done else { return }
        engine.abort()
        phase = .failed(failure)
        let channel = self.channel
        Task { if tell { try? await channel?.send(.cancel) }; channel?.close() }
        stop()
    }
}

private struct LinkPace {
    let started = Date()
    func secondsLeft(done: UInt64, total: UInt64) -> Int? {
        let elapsed = Date().timeIntervalSince(started)
        guard done > 0, elapsed > 1, total >= done else { return nil }
        return Int((elapsed / Double(done) * Double(total - done)).rounded())
    }
}
