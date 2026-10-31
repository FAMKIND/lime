import Foundation
import Observation
import UIKit

/// Who is signed in on this phone. Tokens live in the Keychain (this device only). After both steps
/// of signing in, LimeCore registers the device with the backend. Signing out forgets all of it.
@MainActor
@Observable
final class AccountSession {
    enum Phase: Equatable { case launching, signedOut, choosingMove, signedIn }

    private(set) var phase: Phase = .launching
    private(set) var profile: Profile?
    private(set) var deviceRegistered = false
    private(set) var maskedEmail: String?
    /// This account's user id, once the device is registered (tests use it).
    private(set) var userID: String?
    /// Signed in on a phone that has no copy of this account while the account already has a phone (LIME-272b): waiting for "Transfer" or
    /// "Start fresh". Nothing is saved until the person chooses, so quitting here signs in again from the start and never replaces keys by accident.
    private(set) var pendingMove: PendingMove?
    /// This phone just handed its account to a new phone: the signed-out screen says so once.
    var movedAway = false
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
        store.sharedUsernameProvider = { [weak self] in self?.profile.flatMap { $0.hideFromSearch ? nil : $0.username } }
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
        if arguments.contains("-lime-demo-move-offer") {
            // UI tests (LIME-272b): the new phone's choice, with a scripted old phone.
            MoveFactory.demo = true
            pendingMove = PendingMove(tokens: AuthTokens(accessToken: "fake-access", refreshToken: "fake-refresh", expiresAt: Date().addingTimeInterval(86_400), userID: "test-user"), profile: nil, maskedEmail: nil)
            phase = .choosingMove
            return
        }
        if arguments.contains("-lime-skip-sign-in") {
            // UI tests: signed in, without a backend.
            profile = Profile(displayName: "Test Teacher", username: "teacher", school: nil, maskedEmail: "t•••@example.invalid")
            maskedEmail = "t•••@example.invalid"
            tokens = AuthTokens(accessToken: "fake-access", refreshToken: "fake-refresh", expiresAt: Date().addingTimeInterval(86_400), userID: "test-user")
            ThemeStore.shared.load(for: "demo")
            await store.bootstrap(arguments: arguments)
            if arguments.contains("-lime-load-sample-chats") { await store.loadSampleChats() }
            if arguments.contains("-lime-demo-chat") {
                AppLock.shared.turnOff()   // the demo starts with Lock lime off (UI tests turn it on)
                // The demo starts from the defaults for what the reader remembers (UI tests change them).
                for key in [ReaderPrefs.fontKey, ReaderPrefs.sizeKey, ReaderPrefs.lineKey, JamSaved.key, VideoPrefs.captionsKey, VideoPrefs.autoAdvanceKey] { UserDefaults.standard.removeObject(forKey: key) }
                store.loadDemo(screen: arguments.firstIndex(of: "-lime-demo-screen").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }) }
            store.demoReviewIfAsked()
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
        // Phones signed in before the owner was recorded never had it: record it now (it also guards against another account's chats).
        if defaults.string(forKey: Self.ownerKey) == nil { defaults.set(saved.userID, forKey: Self.ownerKey) }
        openSpace(for: saved.userID)
        store.accountSignedIn = true
        profile = storedProfile()
        await store.bootstrap(arguments: arguments)
        store.applySharedUsername()
        phase = .signedIn
        await registerDevice()
        if let loaded = try? await auth.loadProfile(tokens: saved) { setProfile(loaded) }
    }

    // MARK: Signing in

    /// Both steps passed (and the profile exists): keep the session and register this device.
    func completeSignIn(tokens: AuthTokens, profile: Profile?, maskedEmail: String? = nil) async {
        if await shouldOfferMove(tokens) {
            pendingMove = PendingMove(tokens: tokens, profile: profile, maskedEmail: maskedEmail)
            phase = .choosingMove
            return
        }
        await finishSignIn(tokens: tokens, profile: profile, maskedEmail: maskedEmail)
    }

    private func finishSignIn(tokens: AuthTokens, profile: Profile?, maskedEmail: String?) async {
        // Each account has its own space (LIME-268): the same person coming back opens their locked store and keeps their keys; another
        // account opens its own and leaves this one intact.
        openSpace(for: tokens.userID)
        defaults.set(tokens.userID, forKey: Self.ownerKey)
        store.accountSignedIn = true
        self.tokens = tokens
        self.maskedEmail = maskedEmail
        try? SessionKeychain.save(tokens, service: sessionService)
        if let profile { setProfile(profile) }
        await store.bootstrap()
        phase = .signedIn
        await registerDevice()
    }

    // MARK: Moving to a new phone (LIME-272b)

    struct PendingMove {
        let tokens: AuthTokens
        let profile: Profile?
        let maskedEmail: String?
    }

    /// True when this phone has no copy of the account and the server already lists a phone for it. A phone that cannot ask (no internet) starts
    /// fresh as before; so does one that already holds the account's store (signed out earlier: 268).
    private func shouldOfferMove(_ tokens: AuthTokens) async -> Bool {
        guard let config, !hasLocalCopy(of: tokens.userID) else { return false }
        let transport = URLSessionTransport(baseURL: config.url, apiKey: config.apiKey)
        let body = (try? JSONSerialization.data(withJSONObject: ["user_id": tokens.userID])) ?? Data()
        let answer: TransportResponse? = try? await Task.detached {
            try transport.request(method: "POST", path: "/functions/v1/users-devices",
                                  headers: [HeaderPair(name: "Authorization", value: "Bearer \(tokens.accessToken)"),
                                            HeaderPair(name: "Content-Type", value: "application/json")], body: body)
        }.value
        guard let answer, answer.status == 200,
              let json = try? JSONSerialization.jsonObject(with: answer.body) as? [String: Any],
              let devices = json["devices"] as? [Any] else { return false }
        return !devices.isEmpty
    }

    private func hasLocalCopy(of userID: String) -> Bool {
        guard let location = try? StorageBootstrap.Location.live(for: userID) else { return false }
        return FileManager.default.fileExists(atPath: location.databaseURL.path) && StorageKeychain.existingKey(service: location.keychainService) != nil
    }

    /// "Start fresh": the sign-in carries on as it always did (new keys; contacts are asked to accept them).
    func startFresh() async {
        guard let pending = pendingMove else { return }
        pendingMove = nil
        await continueSignIn(pending)
    }

    /// Back to the sign-in screens without signing in.
    func cancelPendingMove() async {
        guard let pending = pendingMove else { return }
        pendingMove = nil
        if let auth { await auth.signOut(tokens: pending.tokens) }
        onboardingGeneration += 1
        phase = .signedOut
    }

    /// The moved store is in place with its key in the Keychain: sign in with it. The same keys and device register again (nothing changes).
    func moveArrived() async {
        guard let pending = pendingMove else { return }
        pendingMove = nil
        await continueSignIn(pending)
    }

    private func continueSignIn(_ pending: PendingMove) async {
        #if DEBUG
        if MoveFactory.demo {
            // The demo: signed in on the demo chats, no backend.
            tokens = pending.tokens
            await store.bootstrap(arguments: ProcessInfo.processInfo.arguments)
            store.loadDemo(screen: nil)
            phase = .signedIn
            return
        }
        #endif
        await finishSignIn(tokens: pending.tokens, profile: pending.profile, maskedEmail: pending.maskedEmail)
    }

    /// The account a move for the person signing in is for.
    var pendingMoveUserID: String? { pendingMove?.tokens.userID }

    /// The old phone is sending its account: no sync, no sending, no live listening, and the screen stays on, so nothing arrives after the copy.
    func beginMove() async {
        store.movePaused = true
        await nudges?.stop()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// The move did not finish: carry on as before.
    func endMove() async {
        store.movePaused = false
        UIApplication.shared.isIdleTimerDisabled = false
        guard phase == .signedIn else { return }
        await nudges?.start()
        await store.syncNow()
    }

    /// The new phone has everything: this phone's store is already removed, so sign out, remove its key, and say so on the next screen.
    func finishedMoving() async {
        UIApplication.shared.isIdleTimerDisabled = false
        store.movePaused = false
        await signOut(removingData: true)
        movedAway = true
    }

    /// Opens the space of the account that is signing in. A store from before spaces existed goes to the account that owned it (the recorded owner,
    /// else this one) the first time, whoever signs in now.
    private func openSpace(for userID: String) {
        StorageBootstrap.adoptOldStore(for: defaults.string(forKey: Self.ownerKey) ?? userID)
        store.useAccount(userID)
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
            let problem = ConnectionProblem.from(error)
            // Relaunched with no internet (airplane mode, a locked phone with no signal): this phone registered long ago, so it can still queue
            // and park messages for the mesh. Without a link every send used to become a local-only message that said "Sent" and never went
            // anywhere (LIME-141-fix4). The full registration runs when the internet returns.
            if OfflineLinkRule.shouldConnect(problem) {
                connectOffline(config: config, why: String(describing: problem))
            } else {
                CallDiagnostics.shared.log("session link=none why=\(problem)")
            }
            store.report(problem)
        }
    }

    /// A link for a phone that has registered before but cannot reach the server now: sends queue (and park for the mesh) instead of staying local.
    private func connectOffline(config: BackendConfig, why: String) {
        let transport = URLSessionTransport(baseURL: config.url, apiKey: config.apiKey)
        CallDiagnostics.shared.log("session link=pending why=\(why)")
        store.connect(makeLink(transport), pendingRegistration: true)
    }

    private func makeLink(_ transport: Transport) -> BackendLink {
        BackendLink(transport: transport, token: { [weak self] in
            guard let self else { throw AuthError.notVerified }
            return try await self.accessToken()
        }, staleToken: { [weak self] in await self?.lastAccessToken() ?? "" })
    }

    /// Registered: deliver and fetch for real, and listen for the "new items" nudge while the app is open.
    private func goLive(device: DeviceInfo, transport: Transport, config: BackendConfig) async {
        CallDiagnostics.shared.log("session link=live")
        store.connect(makeLink(transport))
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
        store.startDraftRealtime(config)
        await store.syncNow()
        await store.adoptMyPublicProfile()   // LIME-271c
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
    /// The access token this phone holds, expired or not (sending with no internet).
    func lastAccessToken() -> String { tokens?.accessToken ?? "" }

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

    /// Ends the session on the server and returns to sign-in. The chats, files and keys stay on this device, encrypted and locked (LIME-268):
    /// signing in again as the same account opens them and reuses the same keys (nothing new is published). `removingData` is "Remove everything
    /// from this device": this account's store and keys are deleted too.
    func signOut(removingData: Bool = false) async {
        endBackgroundListening()
        await nudges?.stop()
        nudges = nil
        if let auth, let tokens { await auth.signOut(tokens: tokens) }
        SessionKeychain.clear(service: sessionService)
        defaults.removeObject(forKey: Self.profileKey)
        if removingData {
            defaults.removeObject(forKey: Self.ownerKey)
            store.wipe()
        } else {
            store.closeStore()
        }
        ThemeStore.shared.load(for: nil)
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

    /// Step one of deleting the account: the password is checked and a code is emailed.
    func startAccountDeletion(password: String) async throws {
        guard let auth else { throw AuthError.network }
        try await auth.startAccountDeletion(password: password, tokens: try await currentTokens())
    }

    /// Step two (LIME-113c): the server checks the password and the code and marks the account "deleting" (a refusal here sends nothing to anyone).
    /// Then the phone sends the quiet notices, tells the server, and the server deletes. Whatever happens after the mark, this phone forgets everything
    /// and returns to the welcome screen: the account can no longer sign in, and the server finishes the deletion by itself if a step is lost.
    func deleteAccount(password: String, code: String) async throws {
        guard let auth else { throw AuthError.network }
        let tokens = try await currentTokens()
        let token = try await auth.deleteAccount(password: password, code: code, tokens: tokens)
        await store.sendAccountDeletedNotices()
        try? await auth.confirmAccountDeletion(token: token, step: "notices", tokens: tokens)
        try? await auth.confirmAccountDeletion(token: token, step: "delete", tokens: tokens)
        await signOut(removingData: true)
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
        store.applySharedUsername()
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
