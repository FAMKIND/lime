import XCTest
@testable import Lime

/// LIME-272c: the app's settings move with the account; caches do not; Lock lime waits for one pass on the new phone.
@MainActor
final class Move272cTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "lime.move272c.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    func testSettingsAreCollectedAndAppliedButCachesAndPhoneOnlySwitchesAreNot() throws {
        let old = suite(), new = suite()
        let account = "acct-\(UUID().uuidString)"
        old.set("dark", forKey: AppearanceSetting.storageKey)
        old.set(4, forKey: "lime.text.step"); old.set("lora", forKey: "lime.text.font"); old.set(false, forKey: "lime.text.follow")
        old.set(true, forKey: "lime.calls.recents"); old.set(1.5, forKey: "lime.calls.volume")
        old.set("blueish", forKey: "lime.theme.\(account).background")
        old.set(Data("looks".utf8), forKey: "lime.chatlooks.\(account).chats")
        old.set(Data("other".utf8), forKey: "lime.theme.someone-else.background")   // another account's: not moved
        // Not moved: caches, the profile cache, the owner, and anything of this phone.
        old.set(Data([1]), forKey: "lime.hero.palettes.v1"); old.set(Data([1]), forKey: "lime.profile"); old.set("x", forKey: "lime.owner")
        old.set(true, forKey: "lime.nearby.running"); old.set(true, forKey: "lime.mesh.help")
        let data = try XCTUnwrap(MovedSettings.collect(account: account, defaults: old))
        XCTAssertGreaterThan(MovedSettings.apply(data, account: account, defaults: new), 6)
        XCTAssertEqual(new.string(forKey: AppearanceSetting.storageKey), "dark")
        XCTAssertEqual(new.integer(forKey: "lime.text.step"), 4)
        XCTAssertEqual(new.string(forKey: "lime.text.font"), "lora")
        XCTAssertEqual(new.double(forKey: "lime.calls.volume"), 1.5)
        XCTAssertEqual(new.string(forKey: "lime.theme.\(account).background"), "blueish")
        XCTAssertEqual(new.data(forKey: "lime.chatlooks.\(account).chats"), Data("looks".utf8), "every chat's look")
        for key in ["lime.theme.someone-else.background", "lime.hero.palettes.v1", "lime.profile", "lime.owner", "lime.nearby.running", "lime.mesh.help"] {
            XCTAssertNil(new.object(forKey: key), "\(key) is not moved")
        }
    }

    func testLockLimeComesAlongAsPendingAndNeverAsOn() throws {
        let old = suite(), new = suite()
        old.set(true, forKey: AppLock.enabledKey); old.set(900, forKey: AppLock.delayKey)
        let data = try XCTUnwrap(MovedSettings.collect(account: "a", defaults: old))
        MovedSettings.apply(data, account: "a", defaults: new)
        XCTAssertFalse(new.bool(forKey: AppLock.enabledKey), "not on until the person has passed it once here")
        XCTAssertTrue(new.bool(forKey: AppLock.pendingKey))
        XCTAssertEqual(new.integer(forKey: AppLock.delayKey), 900, "with the delay it had")
        // The first sign-in on the new phone asks once, and only then is it on.
        let lock = AppLock(defaults: new, authenticator: FakeLockAuthenticator())
        let expectation = expectation(description: "asked")
        Task { await lock.finishMovedLockIfPending(); expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(new.bool(forKey: AppLock.enabledKey))
        XCTAssertFalse(new.bool(forKey: AppLock.pendingKey))
    }

    func testAKeyThatIsNotOnTheListIsIgnoredWhenApplying() throws {
        let new = suite()
        let hostile = try PropertyListSerialization.data(fromPropertyList: ["v": 1, "defaults": ["lime.owner": "attacker", "lime.lock.enabled": true, "lime.text.step": 2], "wallpapers": ["../escape.jpg": Data([1])]] as [String: Any], format: .binary, options: 0)
        MovedSettings.apply(hostile, account: "a", defaults: new)
        XCTAssertNil(new.object(forKey: "lime.owner"))
        XCTAssertFalse(new.bool(forKey: AppLock.enabledKey), "Lock lime is never switched on by a payload")
        XCTAssertEqual(new.integer(forKey: "lime.text.step"), 2)
    }

    func testWallpaperPicturesTravelAndLandInTheNewAccountsSpace() throws {
        let account = "wall-\(UUID().uuidString)"
        let other = "wall2-\(UUID().uuidString)"
        addTeardownBlock {
            for id in [account, other] { try? FileManager.default.removeItem(at: (try! StorageBootstrap.Location.live(for: id)).directory) }
        }
        ChatLooks.shared.load(for: account)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800)).image { c in UIColor.systemPink.setFill(); c.fill(CGRect(x: 0, y: 0, width: 400, height: 800)) }
        ChatLooks.shared.setPhoto(image, for: "dm:sam")
        let data = try XCTUnwrap(MovedSettings.collect(account: account, defaults: suite()))
        defer { ChatLooks.shared.load(for: nil) }
        MovedSettings.apply(data, account: account, defaults: suite())
        let moved = try XCTUnwrap(ChatLooks.shared.photoURL("dm:sam"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("escape.jpg").path), "a picture is only written by its plain file name")
    }
}
