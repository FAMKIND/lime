import XCTest
@testable import Lime

private struct Answer: LockAuthenticator {
    let ok: Bool
    func authenticate(reason: String) async -> Bool { ok }
}

/// LIME-269: the lock's rules (the system's Face ID is faked).
@MainActor
final class AppLock269Tests: XCTestCase {
    private func lock(ok: Bool = true, enabled: Bool = true, delay: AppLockDelay = .immediately) -> AppLock {
        let defaults = UserDefaults(suiteName: "lock-\(UUID().uuidString)")!
        defaults.set(enabled, forKey: AppLock.enabledKey)
        defaults.set(delay.rawValue, forKey: AppLock.delayKey)
        return AppLock(defaults: defaults, authenticator: Answer(ok: ok))
    }

    func testItIsOffByDefaultAndCoversNothing() {
        let defaults = UserDefaults(suiteName: "lock-\(UUID().uuidString)")!
        let lock = AppLock(defaults: defaults, authenticator: Answer(ok: true))
        XCTAssertFalse(lock.isEnabled)
        XCTAssertFalse(lock.isLocked)
        lock.sceneBecameInactive(); lock.sceneEnteredBackground()
        XCTAssertFalse(lock.isCovered)
        XCTAssertFalse(lock.hidesNotificationText())
    }

    func testTheDelayDecidesWhetherComingBackLocks() {
        XCTAssertTrue(AppLock.shouldLock(elapsed: 0, delay: .immediately))
        XCTAssertFalse(AppLock.shouldLock(elapsed: 59, delay: .oneMinute))
        XCTAssertTrue(AppLock.shouldLock(elapsed: 60, delay: .oneMinute))
        XCTAssertFalse(AppLock.shouldLock(elapsed: 899, delay: .fifteenMinutes))
        XCTAssertTrue(AppLock.shouldLock(elapsed: 3600, delay: .oneHour))
    }

    func testLeavingBlursAtOnceAndLocksImmediatelyOrAfterTheDelay() {
        let now = lock(delay: .immediately)
        now.turnOffForSignedOut()   // unlocked, in front
        now.sceneBecameInactive()
        XCTAssertTrue(now.isCovered, "the app switcher's picture is blurred")
        XCTAssertFalse(now.isLocked)
        now.sceneEnteredBackground()
        XCTAssertTrue(now.isLocked)

        let later = lock(delay: .oneHour)
        later.turnOffForSignedOut()
        later.sceneEnteredBackground()
        XCTAssertFalse(later.isLocked, "an hour has not passed")
        later.sceneBecameActive()
        XCTAssertFalse(later.isLocked)
        XCTAssertFalse(later.isCovered, "and the blur goes")
    }

    func testAColdStartIsLockedAndUnlockOpensItOnlyWhenTheSystemSaysYes() async {
        let refused = lock(ok: false)
        XCTAssertTrue(refused.isLocked)
        await refused.unlock()
        XCTAssertTrue(refused.isLocked, "a failed or cancelled Face ID leaves it locked")
        let allowed = lock(ok: true)
        await allowed.unlock()
        XCTAssertFalse(allowed.isLocked)
    }

    func testNotificationsShowNoTextWhileLocked() {
        let locked = lock()
        XCTAssertTrue(locked.hidesNotificationText())
        let open = lock(delay: .oneHour)
        open.turnOffForSignedOut()
        XCTAssertFalse(open.hidesNotificationText(), "unlocked and in front: the text shows")
        open.sceneEnteredBackground()
        XCTAssertFalse(open.hidesNotificationText(now: Date().addingTimeInterval(60)), "inside the delay it is not locked yet")
        XCTAssertTrue(open.hidesNotificationText(now: Date().addingTimeInterval(3601)), "past the delay it is")
    }

    func testTurningItOnNeedsTheSystemToAgree() async {
        let defaults = UserDefaults(suiteName: "lock-\(UUID().uuidString)")!
        let no = AppLock(defaults: defaults, authenticator: Answer(ok: false))
        let turned = await no.turnOn()
        XCTAssertFalse(turned)
        XCTAssertFalse(no.isEnabled)
        let yes = AppLock(defaults: defaults, authenticator: Answer(ok: true))
        let turnedOn = await yes.turnOn()
        XCTAssertTrue(turnedOn)
        XCTAssertTrue(yes.isEnabled)
    }
}
