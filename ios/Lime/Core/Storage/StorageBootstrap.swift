import Foundation

/// Where the encrypted database lives and how it is opened. Everything here is blocking, so call
/// it off the main thread.
///
/// The database is **never backed up** (a restored phone would get the file but not the
/// this-device-only Keychain key). If the store cannot be opened, the old file is moved aside and
/// a fresh store is created; history is meant to come back through Lime's own recovery-key backup
/// and device linking, not through iCloud.
enum StorageBootstrap {
    /// A folder for the database files and the Keychain service that holds its key. Tests use
    /// their own of both.
    struct Location: Sendable {
        var directory: URL
        var keychainService: String

        /// Application Support/Lime, and the app's Keychain item.
        static func live() throws -> Location {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return Location(directory: support.appendingPathComponent("Lime", isDirectory: true),
                            keychainService: StorageKeychain.defaultService)
        }

        var databaseURL: URL { directory.appendingPathComponent("lime.db") }
    }

    struct Opened: Sendable {
        let store: LimeStore
        let path: String
        /// True when the previous database could not be opened (its key was missing, or wrong, or
        /// the file was damaged): it was moved aside and a fresh store was created.
        let startedFresh: Bool
    }

    /// How many `lime-<time>.unreadable.db` files to keep.
    static let keptUnreadableFiles = 2

    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication
    private static let siblingSuffixes = ["-wal", "-shm", "-journal"]

    // MARK: Opening

    static func open(at location: Location? = nil, resetFirst: Bool = false, now: Date = Date()) throws -> Opened {
        let location = try location ?? Location.live()
        try FileManager.default.createDirectory(
            at: location.directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: protection])
        let url = location.databaseURL
        if resetFirst { removeDatabaseFiles(at: url) }

        var startedFresh = false
        let store: LimeStore
        if let key = StorageKeychain.existingKey(service: location.keychainService) {
            do {
                store = try LimeStore.open(path: url.path, key: key)
            } catch let error as StoreError where isUnopenable(error) {
                startedFresh = FileManager.default.fileExists(atPath: url.path)
                store = try startFresh(at: location, moveAside: startedFresh, now: now)
            }
        } else {
            // No key. With no database either this is a first launch, which is not an error.
            let hasOldDatabase = FileManager.default.fileExists(atPath: url.path)
            startedFresh = hasOldDatabase
            store = try startFresh(at: location, moveAside: hasOldDatabase, now: now)
        }

        try store.seedSampleDataIfEmpty()
        prepareFiles(in: location)
        return Opened(store: store, path: url.path, startedFresh: startedFresh)
    }

    /// Errors that mean "this file cannot be used with this key". Anything else (a bad key length,
    /// SQLCipher missing) is a bug and is not hidden by starting fresh.
    private static func isUnopenable(_ error: StoreError) -> Bool {
        switch error {
        case .WrongKeyOrNotADatabase, .Migration, .Database: true
        default: false
        }
    }

    /// Moves the old file aside (if there is one), makes a new key, and opens a new store.
    private static func startFresh(at location: Location, moveAside: Bool, now: Date) throws -> LimeStore {
        if moveAside { try moveDatabaseAside(at: location, now: now) }
        StorageKeychain.deleteKey(service: location.keychainService)
        let key = try StorageKeychain.loadOrCreateKey(service: location.keychainService)
        return try LimeStore.open(path: location.databaseURL.path, key: key)
    }

    // MARK: Unreadable files

    private static func moveDatabaseAside(at location: Location, now: Date) throws {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: now)
        var target = location.directory.appendingPathComponent("lime-\(stamp).unreadable.db")
        var counter = 1
        while fm.fileExists(atPath: target.path) {
            target = location.directory.appendingPathComponent("lime-\(stamp)-\(counter).unreadable.db")
            counter += 1
        }
        try fm.moveItem(at: location.databaseURL, to: target)
        for suffix in siblingSuffixes {
            try? fm.removeItem(atPath: location.databaseURL.path + suffix)
        }
        pruneUnreadableFiles(in: location)
    }

    /// Keeps the newest `keptUnreadableFiles` (the ISO timestamps sort by name).
    static func pruneUnreadableFiles(in location: Location) {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: location.directory.path)) ?? [])
            .filter { $0.hasPrefix("lime-") && $0.hasSuffix(".unreadable.db") }
            .sorted(by: >)
        for name in names.dropFirst(keptUnreadableFiles) {
            try? fm.removeItem(at: location.directory.appendingPathComponent(name))
        }
    }

    static func unreadableFileNames(in location: Location) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: location.directory.path)) ?? [])
            .filter { $0.hasPrefix("lime-") && $0.hasSuffix(".unreadable.db") }
            .sorted()
    }

    // MARK: Backup exclusion and file protection (every launch)

    /// Keeps the folder and every database file out of backups (the attribute can be lost when a
    /// file is replaced, so it is set each launch) and sets the file protection.
    static func prepareFiles(in location: Location) {
        let fm = FileManager.default
        var urls = [location.directory]
        let names = (try? fm.contentsOfDirectory(atPath: location.directory.path)) ?? []
        urls += names.filter { $0.hasPrefix("lime") }.map { location.directory.appendingPathComponent($0) }
        for var url in urls {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            try? fm.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
        }
    }

    static func isExcludedFromBackup(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
    }

    // MARK: Checks

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

    private static func removeDatabaseFiles(at url: URL) {
        for suffix in [""] + siblingSuffixes {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    // MARK: Debug-only launch arguments

    /// `-lime-reset-store` starts from a fresh sample database. It exists for UI tests and works
    /// only in Debug builds: `debugBuild` is false in a Release build, so a Release app ignores it.
    static func resetRequested(arguments: [String], debugBuild: Bool) -> Bool {
        debugBuild && arguments.contains("-lime-reset-store")
    }

    static let isDebugBuild: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

    /// Test hooks (Debug only): `-lime-test-corrupt-key` replaces the Keychain key with random
    /// bytes; `-lime-test-delete-key` removes it. Both simulate a restore without the Keychain.
    static func applyDebugHooks(arguments: [String], service: String = StorageKeychain.defaultService) {
        #if DEBUG
        if arguments.contains("-lime-test-corrupt-key") {
            StorageKeychain.deleteKey(service: service)
            _ = try? StorageKeychain.loadOrCreateKey(service: service) // a different random key
        }
        if arguments.contains("-lime-test-delete-key") {
            StorageKeychain.deleteKey(service: service)
        }
        #endif
    }
}
