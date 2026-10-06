import Foundation

/// Where the encrypted database lives and how it is opened. Everything here is blocking, so call
/// it off the main thread.
enum StorageBootstrap {
    struct Opened: Sendable {
        let store: LimeStore
        let path: String
    }

    /// The database file: Application Support/Lime/lime.db.
    static func databaseURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("Lime", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory.appendingPathComponent("lime.db")
    }

    /// Opens (creating if needed) the encrypted store, seeds the made-up sample data into an
    /// empty one, and sets the file protection on the database files.
    static func open(resetFirst: Bool = false) throws -> Opened {
        let url = try databaseURL()
        if resetFirst { removeDatabaseFiles(at: url) }
        let key = try StorageKeychain.loadOrCreateKey()
        let store = try LimeStore.open(path: url.path, key: key)
        try store.seedSampleDataIfEmpty()
        protectDatabaseFiles(at: url)
        return Opened(store: store, path: url.path)
    }

    /// True when the file cannot be opened with a key that is not ours. This is the app's own
    /// proof, next to the core's, that the data on disk is encrypted.
    static func rejectsWrongKey(path: String) -> Bool {
        do {
            _ = try LimeStore.open(path: path, key: Data(repeating: 0, count: 32))
            return false
        } catch {
            return true
        }
    }

    private static let suffixes = ["", "-wal", "-shm", "-journal"]

    private static func removeDatabaseFiles(at url: URL) {
        for suffix in suffixes {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    private static func protectDatabaseFiles(at url: URL) {
        for suffix in suffixes where FileManager.default.fileExists(atPath: url.path + suffix) {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path + suffix)
        }
    }
}
