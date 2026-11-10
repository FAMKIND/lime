import LocalAuthentication
import SwiftUI
import UIKit

// LIME-133b: replaced by the core type LockDelay; delete this copy then.
/// How long lime may be away before it asks again (LIME-269).
enum AppLockDelay: Int, CaseIterable, Identifiable {
    case immediately = 0, oneMinute = 60, fifteenMinutes = 900, oneHour = 3600
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fifteenMinutes: "After 15 minutes"
        case .oneHour: "After 1 hour"
        }
    }
}

/// Asks the system whether it is really the owner: Face ID or Touch ID, with the device passcode always available as the fallback.
protocol LockAuthenticator: Sendable {
    func authenticate(reason: String) async -> Bool
}

struct SystemLockAuthenticator: LockAuthenticator {
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        // `deviceOwnerAuthentication` = biometrics, then the passcode when they fail or are not set up.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// "Face ID", "Touch ID" or "your passcode", for the words on screen.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "your passcode"
        }
    }
}

#if DEBUG
/// UI tests: `-lime-fake-lock-auth` answers yes without the system sheet.
struct FakeLockAuthenticator: LockAuthenticator {
    func authenticate(reason: String) async -> Bool { true }
}
#endif

/// The optional lock on lime itself (LIME-269): off by default. Nothing leaves the device; the check is the system's.
@MainActor @Observable
final class AppLock {
    static let shared = AppLock()

    nonisolated static let enabledKey = "lime.lock.enabled"
    nonisolated static let delayKey = "lime.lock.delay"
    /// A move to a new phone brought Lock lime with it (LIME-272c): it is not on until the person has passed Face ID or the passcode once here.
    nonisolated static let pendingKey = "lime.lock.pending"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var authenticator: LockAuthenticator
    @ObservationIgnored private var leftAt: Date?
    @ObservationIgnored private var authenticating = false
    /// Ask by itself on coming back. UI tests switch this off so the lock screen can be seen before "Unlock" is tapped.
    @ObservationIgnored var asksOnReturn = true

    /// The lock screen is up.
    private(set) var isLocked: Bool
    /// The app is not in front (or the system is over it): the app switcher's snapshot must not show chats.
    private(set) var isCovered = false

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }
    var delay: AppLockDelay {
        get { AppLockDelay(rawValue: defaults.integer(forKey: Self.delayKey)) ?? .immediately }
        set { defaults.set(newValue.rawValue, forKey: Self.delayKey) }
    }

    init(defaults: UserDefaults = .standard, authenticator: LockAuthenticator = SystemLockAuthenticator()) {
        self.defaults = defaults
        self.authenticator = authenticator
        isLocked = defaults.bool(forKey: Self.enabledKey)   // a cold start asks first
    }

    /// Whether being away for `elapsed` seconds calls for the lock.
    static func shouldLock(elapsed: TimeInterval, delay: AppLockDelay) -> Bool { elapsed >= TimeInterval(delay.rawValue) }

    /// Turning it on asks the system once (so Face ID's permission appears here and a phone with no passcode says so) and only then switches on.
    func turnOn() async -> Bool {
        guard await authenticator.authenticate(reason: "Turn on Lock lime") else { return false }
        defaults.set(true, forKey: Self.enabledKey)
        return true
    }

    /// Nobody is signed in: there is nothing to cover. (The setting stays; the lock comes back with the next cold start.)
    func turnOffForSignedOut() {
        isLocked = false
        isCovered = false
    }

    func turnOff() {
        defaults.set(false, forKey: Self.enabledKey)
        isLocked = false
        isCovered = false
    }

    // MARK: Scene changes

    /// Something is over the app or it is leaving: blur it (the app switcher takes its picture now).
    func sceneBecameInactive() {
        guard isEnabled else { return }
        isCovered = true
    }

    func sceneEnteredBackground() {
        guard isEnabled else { return }
        isCovered = true
        if leftAt == nil { leftAt = Date() }
        if delay == .immediately { isLocked = true }
    }

    func sceneBecameActive() {
        defer { if !isLocked { isCovered = false } }
        guard isEnabled else { isLocked = false; return }
        let wasAway = leftAt != nil
        if let leftAt, Self.shouldLock(elapsed: Date().timeIntervalSince(leftAt), delay: delay) { isLocked = true }
        leftAt = nil
        // Ask on coming back from away, not every time a cancelled sheet closes: "Unlock" asks again.
        if isLocked && wasAway { askIfWanted() }
    }

    /// After a move: Lock lime was on on the old phone, so ask once and only then turn it on here (with the same delay it had).
    func finishMovedLockIfPending() async {
        guard defaults.bool(forKey: Self.pendingKey) else { return }
        defaults.removeObject(forKey: Self.pendingKey)
        _ = await turnOn()
    }

    func askIfWanted() {
        guard asksOnReturn, isLocked else { return }
        Task { await unlock() }
    }

    /// Asks for Face ID (or the passcode) and opens lime when it passes. Calling it twice at once asks once.
    func unlock() async {
        guard isLocked, !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        if await authenticator.authenticate(reason: "Unlock lime") {
            isLocked = false
            isCovered = false
        }
    }

    /// Notifications show no message text while the lock is on and lime is away long enough to be locked.
    func hidesNotificationText(now: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        if isLocked { return true }
        guard let leftAt else { return false }
        return Self.shouldLock(elapsed: now.timeIntervalSince(leftAt), delay: delay)
    }
}

// MARK: The cover

/// A window above everything (sheets and calls too): a blur while lime is not in front, the lock screen while it is locked.
@MainActor
final class LockWindow {
    private var window: UIWindow?

    func update(for lock: AppLock) {
        guard lock.isCovered || lock.isLocked else { window?.isHidden = true; window = nil; return }
        if window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let created = UIWindow(windowScene: scene)
            created.windowLevel = .alert + 1
            created.rootViewController = UIHostingController(rootView: LockCoverView(lock: lock))
            created.rootViewController?.view.backgroundColor = .clear
            window = created
        }
        window?.isHidden = false
    }
}

struct LockCoverView: View {
    let lock: AppLock
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency || lock.isLocked {
                Theme.canvas
            } else {
                Rectangle().fill(.ultraThickMaterial)
            }
            if lock.isLocked { LockScreen(lock: lock) }
        }
        .ignoresSafeArea()
    }
}

/// A plain lime screen with one button.
struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 34)).foregroundStyle(Theme.text).accessibilityHidden(true)
            Text("lime is locked").font(Theme.title).foregroundStyle(Theme.text)
            Button { Task { await lock.unlock() } } label: {
                Text("Unlock").font(Theme.title).padding(.horizontal, 28).frame(minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)
            .foregroundStyle(Theme.primaryInk)
            .accessibilityLabel("Unlock lime")
            .accessibilityIdentifier("lock-unlock")
        }
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("lock-screen")
    }
}
