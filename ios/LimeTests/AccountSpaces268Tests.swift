import XCTest
@testable import Lime

/// LIME-268: each account has its own store and key; signing out closes the store but keeps it; "Remove everything" deletes it.
final class AccountSpaces268Tests: XCTestCase {
    private func location(_ name: String) -> StorageBootstrap.Location {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lime-spaces-\(UUID().uuidString)", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        let service = "app.lime.tests.spaces.\(UUID().uuidString)"
        addTeardownBlock {
            StorageKeychain.deleteKey(service: service)
            try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        }
        return .init(directory: directory, keychainService: service)
    }

    private func conversations(at location: StorageBootstrap.Location) throws -> Int {
        try StorageBootstrap.open(at: location).store.listConversations().count
    }

    func testClosingAStoreKeepsItsChatsAndTheKeyOpensItAgain() throws {
        let space = location("a")
        try autoreleasepool { try StorageBootstrap.open(at: space).store.seedSampleDataIfEmpty() }
        let before = try conversations(at: space)
        XCTAssertGreaterThan(before, 0)
        XCTAssertEqual(try conversations(at: space), before, "signing out and in again finds the same chats")
        XCTAssertFalse(try StorageBootstrap.open(at: space).startedFresh, "the same key opened it: nothing was recreated")
    }

    func testAnotherAccountGetsItsOwnEmptySpaceAndTheFirstIsIntact() throws {
        let a = location("a"), b = location("b")
        try autoreleasepool { try StorageBootstrap.open(at: a).store.seedSampleDataIfEmpty() }
        let kept = try conversations(at: a)
        XCTAssertEqual(try conversations(at: b), 0, "B starts empty")
        XCTAssertNotEqual(StorageKeychain.existingKey(service: a.keychainService), StorageKeychain.existingKey(service: b.keychainService), "each space has its own key")
        XCTAssertEqual(try conversations(at: a), kept, "and A is intact after B was opened")
    }

    func testRemoveEverythingDeletesOnlyThatAccountsSpaceAndKey() throws {
        let a = location("a"), b = location("b")
        try autoreleasepool {
            try StorageBootstrap.open(at: a).store.seedSampleDataIfEmpty()
            try StorageBootstrap.open(at: b).store.seedSampleDataIfEmpty()
        }
        let other = try conversations(at: b)
        StorageBootstrap.wipe(at: a)
        XCTAssertNil(StorageKeychain.existingKey(service: a.keychainService))
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.databaseURL.path))
        XCTAssertEqual(try conversations(at: b), other, "B is untouched")
    }

    func testAStoreFromBeforeSpacesMovesToItsOwnerWithItsKey() throws {
        let old = location("old"), space = location("space")
        try autoreleasepool { try StorageBootstrap.open(at: old).store.seedSampleDataIfEmpty() }
        let chats = try conversations(at: old)
        XCTAssertTrue(StorageBootstrap.adoptOldStore(for: "user-1", legacy: old, space: space))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.databaseURL.path), "moved, not copied")
        XCTAssertNil(StorageKeychain.existingKey(service: old.keychainService), "the key moved with it")
        XCTAssertEqual(try conversations(at: space), chats)
        XCTAssertFalse(StorageBootstrap.adoptOldStore(for: "user-1", legacy: old, space: space), "nothing left to move")
    }
}
