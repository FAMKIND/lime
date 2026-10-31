import XCTest
@testable import Lime

/// LIME-272b: the carrier between the phones, and the two sides of a move driven over an in-memory channel, with LimeCore's real engines.
@MainActor
final class Move272Tests: XCTestCase {
    /// The server stand-in just enough to register a device.
    private final class RegisterOnly: Transport, @unchecked Sendable {
        func request(method: String, path: String, headers: [HeaderPair], body: Data) throws -> TransportResponse {
            let answer = path.hasSuffix("devices-register") ? #"{"user_id":"teacher-1","remaining_one_time_keys":100}"# : "{}"
            return TransportResponse(status: 200, body: Data(answer.utf8))
        }
    }

    func testMessagesAreFramedAndReadBack() {
        for message: MoveMessage in [.hello(Data([1, 2])), .ready, .chunk(Data(repeating: 9, count: 5000)), .finished, .proof(Data([7])), .cancel] {
            let framed = message.framed
            let length = Int(framed.prefix(4).reduce(0) { $0 << 8 | Int($1) })
            XCTAssertEqual(length, framed.count - 4)
            XCTAssertEqual(MoveMessage.decode(tag: framed[4], payload: framed.dropFirst(5)), message)
        }
        XCTAssertNil(MoveMessage.decode(tag: 99, payload: Data()))
    }

    func testTheInMemoryChannelKeepsOrderAndSaysWhenTheOtherEndLeft() async throws {
        let (a, b) = LoopbackMoveChannel.pair()
        for i in 0..<5 { try await a.send(.chunk(Data([UInt8(i)]))) }
        for i in 0..<5 { let got = try await b.receive(); XCTAssertEqual(got, .chunk(Data([UInt8(i)]))) }
        a.close()
        do { _ = try await b.receive(); XCTFail("expected closed") } catch { XCTAssertEqual(error as? MoveChannelError, .closed) }
    }

    func testBothPhonesFindTheSameServiceNameForOneCodeAndNotForAnother() {
        XCTAssertEqual(MoveBonjour.serviceName(for: "lime-move1:abc"), MoveBonjour.serviceName(for: "lime-move1:abc"))
        XCTAssertNotEqual(MoveBonjour.serviceName(for: "lime-move1:abc"), MoveBonjour.serviceName(for: "lime-move1:abd"))
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Data?
        var value: Data? { get { lock.lock(); defer { lock.unlock() }; return stored } set { lock.lock(); stored = newValue; lock.unlock() } }
    }

    private func wait(_ what: String, timeout: TimeInterval = 60, until: () -> Bool) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !until() {
            if Date() > end { XCTFail("timed out waiting for \(what)"); throw CancellationError() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testARealAccountMovesOverTheChannelAndTheOldPhoneIsEmptied() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lime-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let oldPath = root.appendingPathComponent("old/lime.db").path
        try FileManager.default.createDirectory(at: root.appendingPathComponent("old"), withIntermediateDirectories: true)
        let key = Data(repeating: 5, count: 32)
        let old = try LimeStore.open(path: oldPath, key: key)
        try old.seedSampleDataIfEmpty()
        _ = try old.registerDevice(transport: RegisterOnly(), authToken: "tok")
        let before = try old.listConversations().map(\.title)
        XCTAssertFalse(before.isEmpty)

        let destination = root.appendingPathComponent("new/lime.db").path
        let newCore = try TransferNew.offer(userId: "teacher-1", destPath: destination)
        let oldCore = try TransferOld.accept(store: old, qr: newCore.qr())
        let (newEnd, oldEnd) = LoopbackMoveChannel.pair()
        let keptKey = Box()
        var movedCalled = false
        var paused = 0, resumed = 0
        let newSide = MoveToNewPhone(engine: RealMoveNew(newCore), accept: { newEnd }, keep: { keptKey.value = $0 })
        let oldSide = MoveFromOldPhone(engine: RealMoveOld(oldCore), connect: { oldEnd },
                                       pause: { paused += 1 }, resume: { resumed += 1 }, moved: { movedCalled = true })
        newSide.start()
        oldSide.start()
        try await wait("both codes") { if case .compare = newSide.phase, case .compare = oldSide.phase { true } else { false } }
        guard case .compare(let a) = newSide.phase, case .compare(let b) = oldSide.phase else { return XCTFail() }
        XCTAssertEqual(a, b, "both phones show the same code")
        XCTAssertEqual(a.count, 6)
        oldSide.matches()
        newSide.matches()
        try await wait("done") { newSide.phase == .done && oldSide.phase == .done }

        XCTAssertEqual(keptKey.value, key, "the new phone is handed the store's key")
        XCTAssertTrue(movedCalled)
        XCTAssertEqual(paused, 1)
        XCTAssertEqual(resumed, 0, "a finished move does not wake the old phone up again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPath), "the old phone's store is gone")
        let moved = try LimeStore.open(path: destination, key: key)
        XCTAssertEqual(try moved.listConversations().map(\.title), before, "every chat arrived")
        XCTAssertEqual(newSide.progress.done, newSide.progress.total)
    }

    func testCancellingOnTheNewPhoneStopsTheOldOneAndKeepsItsStore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lime-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("old"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let oldPath = root.appendingPathComponent("old/lime.db").path
        let old = try LimeStore.open(path: oldPath, key: Data(repeating: 5, count: 32))
        _ = try old.registerDevice(transport: RegisterOnly(), authToken: "tok")
        let destination = root.appendingPathComponent("new/lime.db").path
        let newCore = try TransferNew.offer(userId: "teacher-1", destPath: destination)
        let oldCore = try TransferOld.accept(store: old, qr: newCore.qr())
        let (newEnd, oldEnd) = LoopbackMoveChannel.pair()
        var resumed = 0
        let newSide = MoveToNewPhone(engine: RealMoveNew(newCore), accept: { newEnd }, keep: { _ in })
        let oldSide = MoveFromOldPhone(engine: RealMoveOld(oldCore), connect: { oldEnd }, pause: {}, resume: { resumed += 1 }, moved: {})
        newSide.start()
        oldSide.start()
        try await wait("codes") { if case .compare = newSide.phase, case .compare = oldSide.phase { true } else { false } }
        newSide.matches()
        newSide.cancel()
        oldSide.matches()
        try await wait("old phone to notice") { if case .failed = oldSide.phase { true } else { false } }
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldPath), "nothing was removed from the old phone")
        XCTAssertEqual(resumed, 1, "the old phone picks up where it was")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination), "nothing was kept on the new phone")
    }

    func testACodeForAnotherAccountIsRefusedByTheOldPhone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lime-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let old = try LimeStore.open(path: root.appendingPathComponent("lime.db").path, key: Data(repeating: 5, count: 32))
        _ = try old.registerDevice(transport: RegisterOnly(), authToken: "tok")
        let other = try TransferNew.offer(userId: "someone-else", destPath: root.appendingPathComponent("n.db").path)
        XCTAssertThrowsError(try TransferOld.accept(store: old, qr: other.qr()))
        XCTAssertThrowsError(try TransferOld.accept(store: old, qr: "https://example.com"))
    }
}
