import Foundation
import Observation

// MARK: The engines (LimeCore's TransferNew / TransferOld, or fakes for the demo)

protocol MoveNewEngine: AnyObject, Sendable {
    var qr: String { get }
    func acceptHello(_ hello: Data) throws
    func checkCode() throws -> String
    func confirmCode()
    func importChunk(_ chunk: Data) throws
    func summary() -> MoveSummary?
    func progress() -> MoveProgress
    func importFinish() throws -> Data
    func confirmProof() throws -> Data
    /// The app's own items that came with the account (LIME-272c).
    func extra() -> Data
    func abort()
}

protocol MoveOldEngine: AnyObject, Sendable {
    func hello() -> Data
    func checkCode() -> String
    func confirmCode()
    func exportNextChunk() throws -> Data?
    func progress() -> MoveProgress
    func transferConfirm(_ proof: Data) throws
    /// The app's own items to move with the account (LIME-272c), before the first chunk.
    func setExtra(_ bytes: Data) throws
    func abort()
}

final class RealMoveNew: MoveNewEngine, @unchecked Sendable {
    private let core: TransferNew
    init(_ core: TransferNew) { self.core = core }
    var qr: String { core.qr() }
    func acceptHello(_ hello: Data) throws { try core.acceptHello(hello: hello) }
    func checkCode() throws -> String { try core.checkCode() }
    func confirmCode() { core.confirmCode() }
    func importChunk(_ chunk: Data) throws { try core.importChunk(chunk: chunk) }
    func summary() -> MoveSummary? { core.summary() }
    func progress() -> MoveProgress { core.progress() }
    func importFinish() throws -> Data { try core.importFinish() }
    func confirmProof() throws -> Data { try core.confirmProof() }
    func extra() -> Data { core.extra() }
    func abort() { core.abort() }
}

final class RealMoveOld: MoveOldEngine, @unchecked Sendable {
    private let core: TransferOld
    init(_ core: TransferOld) { self.core = core }
    func hello() -> Data { core.hello() }
    func checkCode() -> String { core.checkCode() }
    func confirmCode() { core.confirmCode() }
    func exportNextChunk() throws -> Data? { try core.exportNextChunk() }
    func progress() -> MoveProgress { core.progress() }
    func transferConfirm(_ proof: Data) throws { try core.transferConfirm(proof: proof) }
    func setExtra(_ bytes: Data) throws { try core.setExtra(bytes: bytes) }
    func abort() { core.abort() }
}

// MARK: What the screens show

enum MoveFailure: Equatable {
    /// The phones did not find each other (a network that blocks peers): the hotspot hint.
    case cantConnect
    /// The connection went away part way: start again from a new code.
    case dropped
    /// The other phone stopped it.
    case stoppedByOther
    /// The code is for another account, or is not a lime move code.
    case wrongCode
    /// The old phone sent everything but did not hear back: the new phone may already have it.
    case noConfirmation
    case failed
}

/// Bytes done and the time left, for the progress screens.
struct MoveProgressInfo: Equatable {
    var done: UInt64 = 0
    var total: UInt64 = 0
    var secondsLeft: Int?
    var conversations: UInt64 = 0
    var messages: UInt64 = 0
    var attachments: UInt64 = 0

    var fraction: Double { total == 0 ? 0 : min(1, Double(done) / Double(total)) }

    var megabytes: String {
        let format = ByteCountFormatStyle(style: .file)
        return "\(Int64(done).formatted(format)) of \(Int64(total).formatted(format))"
    }

    var timeLeft: String? {
        guard let secondsLeft, secondsLeft > 1 else { return nil }
        return secondsLeft < 90 ? "About \(secondsLeft) seconds left" : "About \((secondsLeft + 30) / 60) minutes left"
    }

    var spoken: String { "\(Int(fraction * 100)) percent" + (timeLeft.map { ", \($0)" } ?? "") }
}

private struct Pace {
    let started = Date()
    func secondsLeft(done: UInt64, total: UInt64) -> Int? {
        let elapsed = Date().timeIntervalSince(started)
        guard done > 0, elapsed > 1, total >= done else { return nil }
        return Int((elapsed / Double(done) * Double(total - done)).rounded())
    }
}

// MARK: The new phone

/// The new phone's side: waits for the old phone, shows the check code, takes the chunks, and on success puts the key where the store opens.
@MainActor
@Observable
final class MoveToNewPhone {
    enum Phase: Equatable { case waiting, compare(String), receiving, finishing, done, failed(MoveFailure) }

    private(set) var phase: Phase = .waiting
    private(set) var progress = MoveProgressInfo()
    let engine: any MoveNewEngine
    private let accept: @Sendable () async throws -> any MoveChannel
    /// Puts the store's key in the Keychain (it must be there before the store is opened).
    private let keep: @Sendable (Data) throws -> Void
    /// Applies the app's settings that came with the account, before the account opens (LIME-272c).
    private let applyExtra: @Sendable (Data) -> Void
    private var channel: (any MoveChannel)?
    private var task: Task<Void, Never>?
    private var decision: CheckedContinuation<Bool, Never>?
    private let stop: @Sendable () -> Void

    var qr: String { engine.qr }

    init(engine: any MoveNewEngine, accept: @escaping @Sendable () async throws -> any MoveChannel,
         keep: @escaping @Sendable (Data) throws -> Void, applyExtra: @escaping @Sendable (Data) -> Void = { _ in }, stop: @escaping @Sendable () -> Void = {}) {
        self.engine = engine
        self.accept = accept
        self.keep = keep
        self.applyExtra = applyExtra
        self.stop = stop
    }

    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    /// "They match" on the new phone.
    func matches() { decision?.resume(returning: true); decision = nil }

    /// "They don't match", or Cancel: stop and throw away what was received.
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
            let channel = try await accept()
            self.channel = channel
            guard case .hello(let hello) = try await channel.receive() else { throw MoveChannelError.badMessage }
            try engine.acceptHello(hello)
            phase = .compare(try engine.checkCode())
            guard await withCheckedContinuation({ decision = $0 }) else { return finish(.stoppedByOther, tell: true) }
            engine.confirmCode()
            try await channel.send(.ready)
            phase = .receiving
            let pace = Pace()
            while true {
                switch try await channel.receive() {
                case .chunk(let chunk):
                    try await Task.detached { try engine.importChunk(chunk) }.value
                    update(from: engine.progress(), summary: engine.summary(), pace: pace)
                case .finished:
                    phase = .finishing
                    let key = try await Task.detached { try engine.importFinish() }.value
                    try keep(key)
                    let extra = engine.extra()
                    if !extra.isEmpty { applyExtra(extra) }
                    try await channel.send(.proof(try engine.confirmProof()))
                    phase = .done
                    channel.close()
                    stop()
                    return
                case .cancel:
                    return finish(.stoppedByOther, tell: false)
                default:
                    throw MoveChannelError.badMessage
                }
            }
        } catch MoveChannelError.timedOut {
            finish(.cantConnect, tell: false)
        } catch MoveChannelError.closed {
            finish(.dropped, tell: false)
        } catch {
            finish(.failed, tell: true)
        }
    }

    private func update(from p: MoveProgress, summary: MoveSummary?, pace: Pace) {
        progress = MoveProgressInfo(done: p.done, total: p.total, secondsLeft: pace.secondsLeft(done: p.done, total: p.total),
                                    conversations: summary?.conversations ?? 0, messages: summary?.messages ?? 0, attachments: summary?.attachments ?? 0)
    }

    private func finish(_ failure: MoveFailure, tell: Bool) {
        guard phase != .done else { return }
        engine.abort()
        phase = .failed(failure)
        let channel = self.channel
        Task { if tell { try? await channel?.send(.cancel) }; channel?.close() }
        stop()
    }
}

// MARK: The old phone

/// The old phone's side: finds the new phone, shows the check code, sends the chunks, and on the new phone's proof tells the app to sign out.
@MainActor
@Observable
final class MoveFromOldPhone {
    enum Phase: Equatable { case connecting, compare(String), waitingForOther, sending, done, failed(MoveFailure) }

    private(set) var phase: Phase = .connecting
    private(set) var progress = MoveProgressInfo()
    private let engine: any MoveOldEngine
    private let connect: @Sendable () async throws -> any MoveChannel
    /// The app pauses sync and sending while this runs, and picks them up again if it did not finish.
    private let pause: @MainActor () -> Void
    private let resume: @MainActor () -> Void
    /// The new phone holds everything and LimeCore removed this phone's store: sign out.
    private let moved: @MainActor () -> Void
    private var channel: (any MoveChannel)?
    private var task: Task<Void, Never>?
    private var decision: CheckedContinuation<Bool, Never>?
    private let stop: @Sendable () -> Void

    init(engine: any MoveOldEngine, connect: @escaping @Sendable () async throws -> any MoveChannel,
         pause: @escaping @MainActor () -> Void, resume: @escaping @MainActor () -> Void, moved: @escaping @MainActor () -> Void,
         stop: @escaping @Sendable () -> Void = {}) {
        self.engine = engine
        self.connect = connect
        self.pause = pause
        self.resume = resume
        self.moved = moved
        self.stop = stop
    }

    func start() {
        guard task == nil else { return }
        pause()
        task = Task { await run() }
    }

    func matches() { decision?.resume(returning: true); decision = nil }

    func cancel() {
        decision?.resume(returning: false)
        decision = nil
        task?.cancel()
        let channel = self.channel
        Task { try? await channel?.send(.cancel); channel?.close() }
        engine.abort()
        stop()
        if phase != .done { resume() }
    }

    private func run() async {
        let engine = self.engine
        var sentAll = false
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
            phase = .sending
            let pace = Pace()
            while let chunk = try await Task.detached(operation: { try engine.exportNextChunk() }).value {
                try await channel.send(.chunk(chunk))
                let p = engine.progress()
                progress = MoveProgressInfo(done: p.done, total: p.total, secondsLeft: pace.secondsLeft(done: p.done, total: p.total))
            }
            try await channel.send(.finished)
            sentAll = true
            guard case .proof(let proof) = try await channel.receive() else { throw MoveChannelError.badMessage }
            try engine.transferConfirm(proof)
            phase = .done
            channel.close()
            stop()
            moved()
        } catch MoveChannelError.timedOut {
            finish(.cantConnect, tell: false)
        } catch MoveChannelError.closed {
            finish(sentAll ? .noConfirmation : .dropped, tell: false)
        } catch {
            finish(.failed, tell: true)
        }
    }

    private func finish(_ failure: MoveFailure, tell: Bool) {
        guard phase != .done else { return }
        engine.abort()
        phase = .failed(failure)
        let channel = self.channel
        Task { if tell { try? await channel?.send(.cancel) }; channel?.close() }
        stop()
        resume()
    }
}
