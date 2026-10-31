import Foundation

/// LIME-272c: the app's own settings that move with the account to a new phone, as one item inside the sealed stream (`TransferOld.setExtra`). Not moved: caches
/// (they refill), the signed-in profile (it is read from the server), and anything that belongs to this phone (Bluetooth, nearby and debug switches).
/// Lock lime comes as "pending": the new phone asks for Face ID or the passcode once before it turns on.
enum MovedSettings {
    /// What is moved, by exact key.
    static let keys: [String] = [
        AppearanceSetting.storageKey, "lime.text.follow", "lime.text.step", "lime.text.font",
        "lime.reader.font", "lime.reader.sizeStep", "lime.reader.lineStep",
        "lime.notify.enabled", "lime.notify.preview", "lime.notify.sound", "lime.notify.callSound", "lime.notify.muted",
        "lime.calls.recents", "lime.calls.lowdata", "lime.calls.volume", "lime.groupCallLayout", "lime.pipView",
        "lime.mentionStyle", "lime.linkPreviews", "lime.keepMedia", "lime.video.captions", "lime.video.autoAdvance", "lime.video-policy",
        "lime.status.manual", "lime.status.hours",
        "lime.jam.savedPosts", "lime.jam.readPosts", "lime.jam.playedPosts", "lime.jam.hiddenPosts",
    ]

    /// What is moved by account: the theme and every chat's look.
    static func accountPrefixes(_ account: String) -> [String] { ["lime.theme.\(account).", "lime.chatlooks.\(account)."] }

    private static func allowed(_ key: String, account: String) -> Bool {
        keys.contains(key) || accountPrefixes(account).contains { key.hasPrefix($0) } || key == AppLock.delayKey || key == AppLock.pendingKey
    }

    /// The settings and wallpaper pictures of `account` as one property list (a few kilobytes, plus the pictures).
    static func collect(account: String, defaults: UserDefaults = .standard) -> Data? {
        var values: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where (keys.contains(key) || accountPrefixes(account).contains { key.hasPrefix($0) }) && PropertyListSerialization.propertyList(value, isValidFor: .binary) {
            values[key] = value
        }
        // Lock lime: not switched on over there until the person has passed it once.
        if defaults.bool(forKey: AppLock.enabledKey) {
            values[AppLock.pendingKey] = true
            values[AppLock.delayKey] = defaults.integer(forKey: AppLock.delayKey)
        }
        var files: [String: Data] = [:]
        if let folder = ChatLooks.shared.wallpaperFolder {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
                if let data = try? Data(contentsOf: folder.appendingPathComponent(name)) { files[name] = data }
            }
        }
        return try? PropertyListSerialization.data(fromPropertyList: ["v": 1, "defaults": values, "wallpapers": files] as [String: Any], format: .binary, options: 0)
    }

    /// Writes them on this phone for `account` (only the allowed keys; a picture only by its plain file name). Returns how many settings were applied.
    @discardableResult
    static func apply(_ data: Data, account: String, defaults: UserDefaults = .standard) -> Int {
        guard let root = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any], root["v"] as? Int == 1 else { return 0 }
        var applied = 0
        for (key, value) in (root["defaults"] as? [String: Any]) ?? [:] where allowed(key, account: account) {
            defaults.set(value, forKey: key)
            applied += 1
        }
        if let files = root["wallpapers"] as? [String: Data], !files.isEmpty,
           let location = try? StorageBootstrap.Location.live(for: account) {
            let folder = location.directory.appendingPathComponent("lime-wallpapers", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, bytes) in files where !name.contains("/") && !name.hasPrefix(".") && name.hasSuffix(".jpg") {
                try? bytes.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        return applied
    }

    /// The live settings objects read the defaults at launch: tell them to read again (the moved account opens right after).
    @MainActor
    static func reloadLiveSettings(notifications: NotificationCoordinator?) {
        TextPreferences.shared.reloadFromDefaults()
        CallSettings.shared.reloadFromDefaults()
        notifications?.settings.reloadFromDefaults()
    }
}
