import Foundation
import Observation
import UIKit

/// Who is signed in on this phone. Tokens live in the Keychain (this device only). After both steps
/// of signing in, LimeCore registers the device with the backend. Signing out forgets all of it.
@MainActor
@Observable
final class AccountSession {
    enum Phase: Equatable { case launching, signedOut, signedIn }

    private(set) var phase: Phase = .launching
    private(set) var profile: Profile?
    private(set) var deviceRegistered = false
    private(set) var maskedEmail: String?
    /// This account's user id, once the device is registered (tests use it).
    private(set) var userID: String?
    /// Bumped on sign-out so the onboarding screens start fresh.
    private(set) var onboardingGeneration = 0

    let auth: (any AuthService)?
    private let config: BackendConfig?
    private let store: ConversationStore
    private var tokens: AuthTokens?
    private var nudges: RealtimeNudges?
    private var refreshing: Task<AuthTokens, Error>?
    private var isRegistering = false
    /// Keeps listening for a short while after the app leaves the front (iOS allows this briefly).
    private var listening: UIBackgroundTaskIdentifier = .invalid

    private static let profileKey = "lime.profile"
    /// Whose chats and keys are on this phone, so signing in again as the same person keeps them.
    private static let ownerKey = "lime.owner"
    private let sessionService: String
    private let defaults: UserDefaults

    init(auth: (any AuthService)?, config: BackendConfig?, store: ConversationStore,
         sessionService: String = SessionKeychain.defaultService, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.config = config
        self.store = store
        self.sessionService = sessionService
        self.defaults = defaults
        store.registrar = { [weak self] in await self?.registerDevice() }
        store.meProvider = { [weak self] in self?.mePerson ?? SampleData.me }
    }

    var hasBackend: Bool { auth != nil }

    /// The signed-in person as an avatar (initials from their name).
    var mePerson: Person {
        // Coloured from the user id, like every other place this person appears.
        Person(id: tokens?.userID ?? "me", name: profile?.displayName ?? SampleData.me.name)
    }

    // MARK: Launch

    /// At launch: pick up a saved session, or ask the person to sign in.
    func resume(arguments: [String] = ProcessInfo.processInfo.arguments) async {
        #if DEBUG
        if arguments.contains("-lime-reset-session") {
            // UI tests: forget any saved session first.
            SessionKeychain.clear(service: sessionService)
            defaults.removeObject(forKey: Self.profileKey)
            store.wipe()
        }
        if arguments.contains("-lime-skip-sign-in") {
            // UI tests: signed in, without a backend.
            profile = Profile(displayName: "Test Teacher", username: "teacher", school: nil, maskedEmail: "t•••@example.invalid")
            maskedEmail = "t•••@example.invalid"
            tokens = AuthTokens(accessToken: "fake-access", refreshToken: "fake-refresh", expiresAt: Date().addingTimeInterval(86_400), userID: "test-user")
            await store.bootstrap(arguments: arguments)
            if arguments.contains("-lime-load-sample-chats") { await store.loadSampleChats() }
            if arguments.contains("-lime-demo-chat") { store.loadDemo(screen: arguments.firstIndex(of: "-lime-demo-screen").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }) }
            phase = .signedIn
            return
        }
        #endif
        guard let auth, var saved = SessionKeychain.load(service: sessionService) else {
            phase = .signedOut
            return
        }
        do {
            if saved.isExpiring() {
                saved = try await auth.refresh(saved)
                try? SessionKeychain.save(saved, service: sessionService)
            }
        } catch AuthError.network, AuthError.unavailable {
            // Offline, or the server is down: carry on with what we have; the next call refreshes.
        } catch {
            // The session ended on the server (signed out elsewhere, or revoked).
            SessionKeychain.clear(service: sessionService)
            phase = .signedOut
            return
        }
        tokens = saved
        profile = storedProfile()
        await store.bootstrap(arguments: arguments)
        phase = .signedIn
        await registerDevice()
        if let loaded = try? await auth.loadProfile(tokens: saved) { setProfile(loaded) }
    }

    // MARK: Signing in

    /// Both steps passed (and the profile exists): keep the session and register this device.
    func completeSignIn(tokens: AuthTokens, profile: Profile?, maskedEmail: String? = nil) async {
        // Someone else's chats and keys are never kept for a different account.
        if let owner = defaults.string(forKey: Self.ownerKey), owner != tokens.userID { store.wipe() }
        defaults.set(tokens.userID, forKey: Self.ownerKey)
        self.tokens = tokens
        self.maskedEmail = maskedEmail
        try? SessionKeychain.save(tokens, service: sessionService)
        if let profile { setProfile(profile) }
        await store.bootstrap()
        phase = .signedIn
        await registerDevice()
    }

    /// The core registers this device once both factors have passed.
    func registerDevice() async {
        guard let config, tokens != nil, !isRegistering, !deviceRegistered else { return }
        isRegistering = true
        defer { isRegistering = false }
        do {
            let token = try await accessToken()
            let transport = URLSessionTransport(baseURL: config.url, apiKey: config.apiKey)
            let device = try await store.registerDevice(transport: transport, token: token)
            deviceRegistered = true
            userID = device.userId
            await goLive(device: device, transport: transport, config: config)
        } catch {
            deviceRegistered = false
            store.report(ConnectionProblem.from(error))
        }
    }

    /// Registered: deliver and fetch for real, and listen for the "new items" nudge while the app is open.
    private func goLive(device: DeviceInfo, transport: Transport, config: BackendConfig) async {
        store.connect(BackendLink(transport: transport, token: { [weak self] in
            guard let self else { throw AuthError.notVerified }
            return try await self.accessToken()
        }))
        let store = self.store
        store.myUserID = userID
        await nudges?.stop()
        let live = RealtimeNudges(
            baseURL: config.url, apiKey: config.apiKey, deviceID: device.deviceId,
            token: { [weak self] in
                guard let self else { throw AuthError.notVerified }
                return try await self.accessToken()
            },
            onNudge: { Task { @MainActor in await store.syncNow() } })
        nudges = live
        await live.start()
        await store.syncNow()
    }

    // MARK: Foreground and background

    /// The app came to the front: listen for nudges and catch up on anything that arrived meanwhile.
    func appBecameActive() async {
        endBackgroundListening()
        guard phase == .signedIn, deviceRegistered else { return }
        await nudges?.start()
        await store.syncNow()
    }

    /// The app left the front. There is no push yet, so Lime keeps listening only for the short time
    /// iOS lets a background app run (a message that arrives then becomes a local notification); when
    /// that time is up, or the person signs out, it stops and waits for the app to return.
    func appLeftForeground() async {
        guard nudges != nil, phase == .signedIn else { await nudges?.stop(); return }
        guard listening == .invalid else { return }
        listening = UIApplication.shared.beginBackgroundTask(withName: "lime.listen") { [weak self] in
            Task { @MainActor in
                await self?.nudges?.stop()
                self?.endBackgroundListening()
            }
        }
    }

    private func endBackgroundListening() {
        guard listening != .invalid else { return }
        UIApplication.shared.endBackgroundTask(listening)
        listening = .invalid
    }

    /// A valid access token, refreshed first when it is about to expire. Calls that arrive together
    /// share one refresh (a refresh token is single-use, so two at once could lose the session).
    func accessToken() async throws -> String {
        guard let current = tokens else { throw AuthError.notVerified }
        guard current.isExpiring(), let auth else { return current.accessToken }
        let task = refreshing ?? Task { try await auth.refresh(current) }
        refreshing = task
        do {
            let fresh = try await task.value
            refreshing = nil
            tokens = fresh
            try? SessionKeychain.save(fresh, service: sessionService)
            return fresh.accessToken
        } catch {
            refreshing = nil
            throw error
        }
    }

    #if DEBUG
    /// Tests: the current tokens (after a refresh if one was due).
    func debugTokens() async throws -> AuthTokens { try await currentTokens() }

    /// Tests: pretend the access token's hour is up, so the next call really refreshes it.
    func debugExpireAccessToken() {
        tokens?.expiresAt = Date().addingTimeInterval(-60)
    }
    #endif

    // MARK: Signing out

    /// Ends the session on the server, then forgets the tokens, the profile and the local store.
    func signOut() async {
        endBackgroundListening()
        await nudges?.stop()
        nudges = nil
        if let auth, let tokens { await auth.signOut(tokens: tokens) }
        SessionKeychain.clear(service: sessionService)
        defaults.removeObject(forKey: Self.profileKey)
        defaults.removeObject(forKey: Self.ownerKey)
        store.wipe()
        tokens = nil
        profile = nil
        maskedEmail = nil
        deviceRegistered = false
        userID = nil
        onboardingGeneration += 1
        phase = .signedOut
    }

    /// The server no longer accepts this session. Unlike signing out, this keeps the chats and keys on
    /// the phone: signing in again as the same person picks them up where they were.
    func endSession() async {
        await nudges?.stop()
        nudges = nil
        SessionKeychain.clear(service: sessionService)
        store.disconnect()
        tokens = nil
        deviceRegistered = false
        userID = nil
        maskedEmail = nil
        onboardingGeneration += 1
        phase = .signedOut
    }

    // MARK: Settings: editing the profile and the password

    /// Saves the whole profile (an editor changes one field and sends all of them). Throws the
    /// server's reason, e.g. `AuthError.usernameTaken`.
    func updateProfile(_ draft: ProfileDraft) async throws {
        guard let auth else { throw AuthError.network }
        let saved = try await auth.saveProfile(draft, tokens: try await currentTokens())
        var kept = saved
        kept.maskedEmail = saved.maskedEmail ?? profile?.maskedEmail
        setProfile(kept)
    }

    /// Step one of changing the password: the current one is checked and a code is emailed.
    func startPasswordChange(current: String) async throws {
        guard let auth else { throw AuthError.network }
        try await auth.startPasswordChange(current: current, tokens: try await currentTokens())
    }

    /// Step two: the code and the new password. The server ends the account's other sessions and
    /// returns a fresh one that has passed both steps; this phone carries on with it.
    func finishPasswordChange(code: String, newPassword: String) async throws {
        guard let auth else { throw AuthError.network }
        let fresh = try await auth.finishPasswordChange(code: code, newPassword: newPassword, tokens: try await currentTokens())
        tokens = fresh
        try? SessionKeychain.save(fresh, service: sessionService)
    }

    /// The tokens, refreshed first when they are about to expire.
    private func currentTokens() async throws -> AuthTokens {
        _ = try await accessToken()
        guard let tokens else { throw AuthError.notVerified }
        return tokens
    }

    // MARK: Profile (not secret: a name for the About sheet)

    private func setProfile(_ profile: Profile) {
        self.profile = profile
        if let data = try? JSONEncoder().encode(StoredProfile(profile)) {
            defaults.set(data, forKey: Self.profileKey)
        }
    }

    private func storedProfile() -> Profile? {
        guard let data = defaults.data(forKey: Self.profileKey) else { return nil }
        return (try? JSONDecoder().decode(StoredProfile.self, from: data))?.profile
    }

    private struct StoredProfile: Codable {
        var displayName: String
        var username: String?
        var school: String?
        var aboutEmoji: String?
        var aboutText: String?
        var hideFromSearch: Bool?
        var maskedEmail: String?
        init(_ profile: Profile) {
            displayName = profile.displayName; username = profile.username; school = profile.school
            aboutEmoji = profile.aboutEmoji; aboutText = profile.aboutText
            hideFromSearch = profile.hideFromSearch; maskedEmail = profile.maskedEmail
        }
        var profile: Profile {
            Profile(displayName: displayName, username: username, school: school, aboutEmoji: aboutEmoji, aboutText: aboutText,
                    hideFromSearch: hideFromSearch ?? false, maskedEmail: maskedEmail)
        }
    }
}
