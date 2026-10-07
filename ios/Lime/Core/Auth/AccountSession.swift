import Foundation
import Observation

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

    private static let profileKey = "lime.profile"
    private let sessionService: String
    private let defaults: UserDefaults

    init(auth: (any AuthService)?, config: BackendConfig?, store: ConversationStore,
         sessionService: String = SessionKeychain.defaultService, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.config = config
        self.store = store
        self.sessionService = sessionService
        self.defaults = defaults
    }

    var hasBackend: Bool { auth != nil }

    /// The signed-in person as an avatar (initials from their name).
    var mePerson: Person {
        Person(id: "me", name: profile?.displayName ?? SampleData.me.name, tone: SampleData.me.tone)
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
            profile = Profile(displayName: "Test Teacher", username: "teacher", school: nil)
            maskedEmail = "t•••@example.invalid"
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
        } catch AuthError.network {
            // Offline: carry on with what we have; the next call refreshes.
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
        if profile == nil, let loaded = try? await auth.loadProfile(tokens: saved) { setProfile(loaded) }
    }

    // MARK: Signing in

    /// Both steps passed (and the profile exists): keep the session and register this device.
    func completeSignIn(tokens: AuthTokens, profile: Profile?, maskedEmail: String? = nil) async {
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
        guard let config, tokens != nil, let token = try? await accessToken() else { return }
        let transport = URLSessionTransport(baseURL: config.url, apiKey: config.apiKey)
        guard let device = try? await store.registerDevice(transport: transport, token: token) else {
            deviceRegistered = false
            return
        }
        deviceRegistered = true
        userID = device.userId
        await goLive(device: device, transport: transport, config: config)
    }

    /// Registered: deliver and fetch for real, and listen for the "new items" nudge while the app is open.
    private func goLive(device: DeviceInfo, transport: Transport, config: BackendConfig) async {
        store.connect(BackendLink(transport: transport, token: { [weak self] in
            guard let self else { throw AuthError.notVerified }
            return try await self.accessToken()
        }))
        let store = self.store
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
        guard phase == .signedIn, deviceRegistered else { return }
        await nudges?.start()
        await store.syncNow()
    }

    /// The app left the front: there is no push yet, so stop listening until it returns.
    func appLeftForeground() async {
        await nudges?.stop()
    }

    /// A valid access token, refreshed first when it is about to expire.
    func accessToken() async throws -> String {
        guard var current = tokens else { throw AuthError.notVerified }
        if current.isExpiring(), let auth {
            current = try await auth.refresh(current)
            tokens = current
            try? SessionKeychain.save(current, service: sessionService)
        }
        return current.accessToken
    }

    // MARK: Signing out

    /// Ends the session on the server, then forgets the tokens, the profile and the local store.
    func signOut() async {
        await nudges?.stop()
        nudges = nil
        if let auth, let tokens { await auth.signOut(tokens: tokens) }
        SessionKeychain.clear(service: sessionService)
        defaults.removeObject(forKey: Self.profileKey)
        store.wipe()
        tokens = nil
        profile = nil
        maskedEmail = nil
        deviceRegistered = false
        userID = nil
        onboardingGeneration += 1
        phase = .signedOut
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
        init(_ profile: Profile) { displayName = profile.displayName; username = profile.username; school = profile.school }
        var profile: Profile { Profile(displayName: displayName, username: username, school: school) }
    }
}
