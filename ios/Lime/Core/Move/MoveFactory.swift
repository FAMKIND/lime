import Foundation

/// Builds the two sides of a move from LimeCore (and, in Debug demos, from fakes that play the other phone).
enum MoveFactory {
    #if DEBUG
    /// The demo and UI tests: no real core, no network; a scripted other phone.
    nonisolated(unsafe) static var demo = false
    #endif

    /// The new phone's side for `userID`'s account: the store will be written where that account's space is, and its key goes to that space's Keychain item.
    @MainActor
    static func newPhone(userID: String) throws -> MoveToNewPhone {
        #if DEBUG
        if demo { return DemoMove.newPhone() }
        #endif
        let location = try StorageBootstrap.Location.live(for: userID)
        let core = try TransferNew.offer(userId: userID, destPath: location.databaseURL.path)
        let listener = try MoveListener(qr: core.qr())
        return MoveToNewPhone(
            engine: RealMoveNew(core),
            accept: { try await listener.accept(timeout: 900) },
            keep: { key in
                try StorageKeychain.store(key, service: location.keychainService)
                StorageBootstrap.prepareFiles(in: location)
            },
            stop: { listener.stop() })
    }

    /// The old phone's side, for the code the new phone shows. Throws if the code is not for this account.
    @MainActor
    static func oldPhone(store: ConversationStore, session: AccountSession, qr: String) throws -> MoveFromOldPhone {
        #if DEBUG
        if store.isDemo { return try DemoMove.oldPhone(qr: qr, session: session) }
        #endif
        guard let core = store.core else { throw MoveChannelError.closed }
        let engine = try TransferOld.accept(store: core, qr: qr)
        let browser = MoveBrowser(qr: qr)
        return MoveFromOldPhone(
            engine: RealMoveOld(engine),
            connect: { try await browser.connect(timeout: 25) },
            pause: { Task { await session.beginMove() } },
            resume: { Task { await session.endMove() } },
            moved: { Task { await session.finishedMoving() } },
            stop: { browser.stop() })
    }
}

#if DEBUG
// MARK: Demo and tests: a scripted other phone

final class FakeMoveNew: MoveNewEngine, @unchecked Sendable {
    let qr = "lime-move1:demo"
    private let lock = NSLock()
    private var received: UInt64 = 0
    private(set) var chunks: [Data] = []
    func acceptHello(_ hello: Data) throws {}
    func checkCode() throws -> String { "482917" }
    func confirmCode() {}
    func importChunk(_ chunk: Data) throws { lock.lock(); chunks.append(chunk); received += UInt64(chunk.count); lock.unlock() }
    func summary() -> MoveSummary? { MoveSummary(conversations: 12, messages: 480, attachments: 36, totalBytes: DemoMove.total) }
    func progress() -> MoveProgress { lock.lock(); defer { lock.unlock() }; return MoveProgress(done: received, total: DemoMove.total) }
    func importFinish() throws -> Data { Data(repeating: 7, count: 32) }
    func confirmProof() throws -> Data { Data([9, 9, 9]) }
    func abort() {}
}

final class FakeMoveOld: MoveOldEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var sent = 0
    private(set) var confirmed = false
    func hello() -> Data { Data([1, 2, 3]) }
    func checkCode() -> String { "482917" }
    func confirmCode() {}
    func exportNextChunk() throws -> Data? {
        Thread.sleep(forTimeInterval: DemoMove.pace)
        lock.lock(); defer { lock.unlock() }
        guard sent < DemoMove.chunks else { return nil }
        sent += 1
        return Data(repeating: UInt8(sent), count: Int(DemoMove.total) / DemoMove.chunks)
    }
    func progress() -> MoveProgress { lock.lock(); defer { lock.unlock() }; return MoveProgress(done: UInt64(sent) * DemoMove.total / UInt64(DemoMove.chunks), total: DemoMove.total) }
    func transferConfirm(_ proof: Data) throws { guard proof == Data([9, 9, 9]) else { throw MoveChannelError.badMessage }; confirmed = true }
    func abort() {}
}

enum DemoMove {
    static let chunks = 6
    static let total: UInt64 = 48_000_000
    static let pace = 0.5

    /// The new phone's screens with a scripted old phone on the other end of an in-memory channel.
    @MainActor
    static func newPhone() -> MoveToNewPhone {
        let (mine, theirs) = LoopbackMoveChannel.pair()
        Task.detached {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            try? await theirs.send(.hello(Data([1, 2, 3])))
            guard case .ready? = try? await theirs.receive() else { return }
            for i in 1...chunks {
                try? await Task.sleep(nanoseconds: UInt64(pace * 1_000_000_000))
                try? await theirs.send(.chunk(Data(repeating: UInt8(i), count: Int(total) / chunks)))
            }
            try? await theirs.send(.finished)
            _ = try? await theirs.receive()
        }
        return MoveToNewPhone(engine: FakeMoveNew(), accept: { mine }, keep: { _ in })
    }

    /// The old phone's screens with a scripted new phone.
    @MainActor
    static func oldPhone(qr: String, session: AccountSession) throws -> MoveFromOldPhone {
        guard qr.hasPrefix("lime-move1:") else { throw MoveChannelError.badMessage }
        let (mine, theirs) = LoopbackMoveChannel.pair()
        Task.detached {
            guard case .hello? = try? await theirs.receive() else { return }
            try? await theirs.send(.ready)
            while let message = try? await theirs.receive() {
                if case .finished = message { try? await theirs.send(.proof(Data([9, 9, 9]))); return }
                if case .cancel = message { return }
            }
        }
        return MoveFromOldPhone(engine: FakeMoveOld(), connect: { mine }, pause: {}, resume: {},
                                moved: { Task { await session.finishedMoving() } })
    }
}
#endif
