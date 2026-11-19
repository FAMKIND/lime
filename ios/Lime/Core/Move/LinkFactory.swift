import Foundation
import UIKit

/// Builds the two sides of a link from LimeCore (and, in Debug demos and tests, from fakes that play the other device).
enum LinkFactory {
    /// This build's kind of device for a new device's QR: the Mac (Catalyst) is a computer and gets no master secret (K2); iPhone and iPad do.
    static var thisIsAComputer: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    /// The kind this device reports for itself: `phone`, `tablet` or `computer` (the core checks it against what the device holds).
    @MainActor static var thisDeviceKind: String {
        if thisIsAComputer { return "computer" }
        return UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"
    }

    /// The new device's side: an empty store in the account's own space (its key goes to that space's Keychain item), a link on it, and the listener the
    /// phone finds by the QR. Cancelling or failing removes that empty store again, so signing in can offer the link again.
    @MainActor
    static func newDevice(session: AccountSession) throws -> LinkToThisDevice {
        #if DEBUG
        if MoveFactory.demo { return DemoLink.newDevice() }
        #endif
        guard let context = session.linkContext() else { throw MoveChannelError.closed }
        let location = try StorageBootstrap.Location.live(for: context.userID)
        let opened = try StorageBootstrap.open(at: location, resetFirst: true)
        do {
            let core = try LinkNew.offer(store: opened.store, isComputer: thisIsAComputer, userId: context.userID)
            let listener = try MoveListener(qr: core.qr())
            return LinkToThisDevice(
                engine: RealLinkNew(core: core, store: opened.store, transport: context.transport, token: context.token),
                accept: { try await listener.accept(timeout: 900) },
                stop: { listener.stop() },
                cleanup: { StorageBootstrap.wipe(at: location); StorageKeychain.deleteKey(service: location.keychainService) })
        } catch {
            StorageBootstrap.wipe(at: location)
            StorageKeychain.deleteKey(service: location.keychainService)
            throw error
        }
    }

    /// The phone's (or tablet's) side, for the code the new device shows. Throws if the code is not a link code for this account, is old or used.
    @MainActor
    static func phone(store: ConversationStore, qr: String) throws -> LinkFromPhone {
        #if DEBUG
        if store.isDemo { return try DemoLink.phone(qr: qr) }
        #endif
        guard let core = store.core, let link = store.link else { throw MoveChannelError.closed }
        let engine = try LinkOld.accept(store: core, qr: qr)
        let browser = MoveBrowser(qr: qr)
        let authenticator = AppLock.shared.authenticator
        return LinkFromPhone(
            engine: RealLinkOld(core: engine, store: core, transport: link.transport, token: { try await link.token() }),
            connect: { try await browser.connect(timeout: 25) },
            authenticate: { await authenticator.authenticate(reason: "Link a new device to your account") },
            linked: { Task { await store.reloadMyDevices() } },
            stop: { browser.stop() })
    }
}

#if DEBUG
// MARK: Demo and tests: a scripted other device

final class FakeLinkNew: LinkNewEngine, @unchecked Sendable {
    let qr = "lime-link-v1:demo"
    private let lock = NSLock()
    private var received: UInt64 = 0
    private(set) var chunks: [Data] = []
    private(set) var registered = false
    var failRegistration = false
    var failHistory = false
    func acceptHello(_ hello: Data) throws {}
    func checkCode() throws -> String { "482917" }
    func confirmCode() {}
    func importChunk(_ chunk: Data) throws { lock.lock(); chunks.append(chunk); received += UInt64(chunk.count); lock.unlock() }
    func progress() -> LinkProgress { lock.lock(); defer { lock.unlock() }; return LinkProgress(done: received, total: DemoLink.total) }
    func importFinish() throws {}
    func registerAndRefresh() async throws { if failRegistration { throw StoreError.TooManyDevices }; registered = true }
    func importHistory() async throws -> HistoryImported? { if failHistory { throw StoreError.Rejected }; return HistoryImported(messages: 480, skipped: 0, conversations: 12, cutoffMs: 0, truncated: false) }
    func historyProgress() -> HistoryProgress { HistoryProgress(step: "importing", done: 1, total: 2) }
    func release() {}
    func abort() {}
}

final class FakeLinkOld: LinkOldEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var sent = 0
    private(set) var confirmed = false
    private(set) var refreshed = false
    var failHistory = false
    func hello() -> Data { Data([1, 2, 3]) }
    func checkCode() -> String { "482917" }
    func confirmCode() { confirmed = true }
    func exportNextChunk() throws -> Data? {
        Thread.sleep(forTimeInterval: DemoLink.pace)
        lock.lock(); defer { lock.unlock() }
        guard sent < DemoLink.chunks else { return nil }
        sent += 1
        return Data(repeating: UInt8(sent), count: Int(DemoLink.total) / DemoLink.chunks)
    }
    func progress() -> LinkProgress { lock.lock(); defer { lock.unlock() }; return LinkProgress(done: UInt64(sent) * DemoLink.total / UInt64(DemoLink.chunks), total: DemoLink.total) }
    func refreshDevices() async throws { refreshed = true }
    func historyChunk() async throws -> Data { if failHistory { throw StoreError.Rejected }; return Data([4, 5, 6]) }
    func historyProgress() -> HistoryProgress { HistoryProgress(step: "uploading", done: 1, total: 2) }
    func abort() {}
}

enum DemoLink {
    static let chunks = 4
    static let total: UInt64 = 24_000_000
    static let pace = 0.4

    /// The new device's screens with a scripted phone on the other end of an in-memory channel.
    @MainActor
    static func newDevice() -> LinkToThisDevice {
        let (mine, theirs) = LoopbackMoveChannel.pair()
        Task.detached {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            try? await theirs.send(.hello(Data([1, 2, 3])))
            guard case .ready? = try? await theirs.receive() else { return }
            for i in 1...chunks {
                try? await Task.sleep(nanoseconds: UInt64(pace * 1_000_000_000))
                try? await theirs.send(.chunk(Data(repeating: UInt8(i), count: Int(total) / chunks)))
            }
            try? await theirs.send(.finished)
            guard case .registered? = try? await theirs.receive() else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            try? await theirs.send(.chunk(Data([4, 5, 6])))
            try? await theirs.send(.finished)
            _ = try? await theirs.receive()
        }
        return LinkToThisDevice(engine: FakeLinkNew(), accept: { mine })
    }

    /// The phone's screens with a scripted new device.
    @MainActor
    static func phone(qr: String) throws -> LinkFromPhone {
        guard qr.hasPrefix("lime-link-v1:") else { throw MoveChannelError.badMessage }
        let (mine, theirs) = LoopbackMoveChannel.pair()
        Task.detached {
            guard case .hello? = try? await theirs.receive() else { return }
            try? await theirs.send(.ready)
            while let message = try? await theirs.receive() {
                if case .finished = message { break }
                if case .cancel = message { return }
            }
            try? await theirs.send(.registered)
            while let message = try? await theirs.receive() {
                if case .finished = message { try? await theirs.send(.done); return }
                if case .cancel = message { return }
            }
        }
        return LinkFromPhone(engine: FakeLinkOld(), connect: { mine }, authenticate: { await AppLock.shared.authenticator.authenticate(reason: "Link a new device") })
    }
}
#endif
