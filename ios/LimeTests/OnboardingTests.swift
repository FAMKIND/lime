import XCTest
@testable import Lime

/// A clock the tests move by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

@MainActor
final class OnboardingModelTests: XCTestCase {
    private var completed: [(AuthTokens, Profile?)] = []

    private func makeModel(clock: TestClock = TestClock()) -> OnboardingModel {
        completed = []
        return OnboardingModel(auth: FakeAuthService(), now: { clock.now }) { [self] tokens, profile in
            completed.append((tokens, profile))
        }
    }

    // MARK: The one question

    func testTheIdentifierIsClassified() {
        XCTAssertEqual(OnboardingModel.classify(""), .empty)
        XCTAssertEqual(OnboardingModel.classify("sam@famkind.com"), .email)
        XCTAssertEqual(OnboardingModel.classify("  sam@famkind.com "), .email)
        XCTAssertEqual(OnboardingModel.classify("s.park"), .username)
        XCTAssertEqual(OnboardingModel.classify("@s.park"), .username)
        XCTAssertEqual(OnboardingModel.classify("+1 (555) 010-0199"), .phone)
        XCTAssertEqual(OnboardingModel.classify("5550100199"), .phone)
        for bad in ["sam@", "sam@famkind", "a b@c.com", "ab", "admin", ".dot", "has space"] {
            guard case .invalid = OnboardingModel.classify(bad) else { return XCTFail("\(bad) should be invalid") }
        }
    }

    func testAPhoneNumberIsToldItWillComeLater() {
        let model = makeModel()
        model.start()
        model.identifier = "+1 555 010 0199"
        XCTAssertEqual(model.identifierKind, .phone)
        XCTAssertFalse(model.canSubmitIdentifier, "phone sign-in is not available yet")
        model.identifier = "sam@famkind.com"
        XCTAssertTrue(model.canSubmitIdentifier)
    }

    func testUsernameRulesMatchTheWeb() {
        XCTAssertNil(OnboardingModel.usernameError("ms.park_1"))
        XCTAssertEqual(OnboardingModel.usernameError("ab"), "Use 3 to 20 characters.")
        XCTAssertEqual(OnboardingModel.usernameError("has space"), "Use only letters, numbers, dots and underscores.")
        XCTAssertEqual(OnboardingModel.usernameError("dot."), "A username can't start or end with a dot.")
        XCTAssertEqual(OnboardingModel.usernameError("Admin"), "That username is reserved. Try another.")
    }

    // MARK: Sign up

    func testSignUpGoesEmailCodePasswordProfile() async throws {
        let model = makeModel()
        model.start()
        model.identifier = "new.teacher@example.com"
        await model.submitIdentifier()
        XCTAssertEqual(model.intent, .signUp)
        XCTAssertEqual(model.confirmation?.title, "We'll send a code to:")
        XCTAssertEqual(model.confirmation?.detail, "new.teacher@example.com")
        XCTAssertEqual(model.step, .identifier, "nothing is sent until the person says yes")

        await model.confirmIdentifier()
        XCTAssertEqual(model.step, .code)
        XCTAssertEqual(model.codeDestination, "new.teacher@example.com")

        // A wrong code shows how many tries are left; the right one moves on.
        model.code = "000000"
        await model.submitCode()
        XCTAssertEqual(model.step, .code)
        XCTAssertEqual(model.errorMessage, "That code isn't right. 4 tries left.")
        model.code = FakeAuthService.code
        await model.submitCode()
        XCTAssertEqual(model.step, .password)

        // The password: 10 characters at least, and both fields must match.
        model.password = "short"
        model.confirmPassword = "short"
        XCTAssertFalse(model.canSubmitPassword)
        model.password = "long enough password"
        model.confirmPassword = "something else"
        XCTAssertFalse(model.canSubmitPassword)
        XCTAssertFalse(model.passwordChecks.matches)
        model.confirmPassword = "long enough password"
        XCTAssertTrue(model.canSubmitPassword)
        await model.submitPassword()
        XCTAssertEqual(model.step, .profile)

        // The name is required; the username, when given, must be valid.
        XCTAssertFalse(model.canSubmitProfile)
        model.displayName = "  Ada Lovelace "
        XCTAssertTrue(model.canSubmitProfile)
        model.username = "no"
        XCTAssertFalse(model.canSubmitProfile)
        XCTAssertNotNil(model.usernameProblem)
        model.username = "@ada.l"
        model.school = "Analytical Academy"
        XCTAssertTrue(model.canSubmitProfile)
        await model.submitProfile()
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.1, Profile(displayName: "Ada Lovelace", username: "ada.l", school: "Analytical Academy"))
    }

    func testCodesOfSixToEightDigitsAreAccepted() {
        let model = makeModel()
        model.start()
        for length in 1...9 {
            model.code = String(repeating: "7", count: length)
            XCTAssertEqual(model.canSubmitCode, (6...8).contains(length), "length \(length)")
        }
        model.code = "12345a"
        XCTAssertFalse(model.canSubmitCode)
    }

    func testAnErrorIsClearedWhenTheScreenOrTheFieldChanges() async {
        let model = makeModel()
        model.start()
        model.identifier = "new.teacher@example.com"
        await model.submitIdentifier(); await model.confirmIdentifier()
        model.code = "000000"
        await model.submitCode()
        XCTAssertNotNil(model.errorMessage)
        model.code = "00000"
        XCTAssertNil(model.errorMessage, "editing the field clears its error")
        model.code = "000000"
        await model.submitCode()
        XCTAssertNotNil(model.errorMessage)
        model.code = FakeAuthService.code
        await model.submitCode()
        XCTAssertEqual(model.step, .password)
        XCTAssertNil(model.errorMessage, "an error never follows the person to the next screen")
    }

    func testATakenUsernameIsReportedOnTheProfileScreen() async {
        let model = makeModel()
        model.start()
        model.identifier = "new@example.com"
        await model.submitIdentifier(); await model.confirmIdentifier()
        model.code = FakeAuthService.code
        await model.submitCode()
        model.password = "long enough password"; model.confirmPassword = "long enough password"
        await model.submitPassword()
        model.displayName = "Ada"
        model.username = "taken"
        await model.submitProfile()
        XCTAssertEqual(model.step, .profile)
        XCTAssertEqual(model.errorMessage, "That username is taken. Try another.")
        XCTAssertTrue(completed.isEmpty)
    }

    // MARK: Sign in

    func testSignInByEmailGoesPasswordThenCode() async {
        let model = makeModel()
        model.start()
        model.identifier = "teacher@famkind.com"
        await model.submitIdentifier()
        XCTAssertEqual(model.intent, .signIn)
        XCTAssertEqual(model.confirmation?.title, "Sign in as:")
        await model.confirmIdentifier()
        XCTAssertEqual(model.step, .password)

        // A wrong password says so and stays; the right one sends the code.
        model.password = "not it"
        await model.submitPassword()
        XCTAssertEqual(model.step, .password)
        XCTAssertEqual(model.errorMessage, "That email, username or password isn't right.")
        model.password = FakeAuthService.password
        await model.submitPassword()
        XCTAssertEqual(model.step, .code)
        XCTAssertEqual(model.codeDestination, "s•••@famkind.com", "the code destination is masked")
        XCTAssertTrue(completed.isEmpty, "a password alone does not sign in")

        model.code = FakeAuthService.code
        await model.submitCode()
        XCTAssertEqual(completed.count, 1, "both steps passed")
        XCTAssertEqual(completed.first?.1?.displayName, "Test Teacher")
    }

    func testSignInByUsernameShowsAMaskedHintAndNeverTheEmail() async {
        let model = makeModel()
        model.start()
        model.identifier = "@s.park"
        await model.submitIdentifier()
        XCTAssertEqual(model.confirmation?.title, "Sign in as @s.park")
        XCTAssertEqual(model.confirmation?.detail, "The code goes to s•••@famkind.com")
        await model.confirmIdentifier()
        model.password = FakeAuthService.password
        await model.submitPassword()
        XCTAssertEqual(model.step, .code)
        model.code = FakeAuthService.code
        await model.submitCode()
        XCTAssertEqual(completed.count, 1)
    }

    func testAnUnknownUsernameOffersTheEmailInstead() async {
        let model = makeModel()
        model.start()
        model.identifier = "nobody"
        await model.submitIdentifier()
        XCTAssertEqual(model.confirmation?.isUnknownUsername, true)
        await model.confirmIdentifier()
        XCTAssertEqual(model.step, .identifier, "there is nothing to confirm")
    }

    func testTheCodeIsLockedAfterFiveWrongTries() async {
        let model = makeModel()
        model.start()
        model.identifier = "teacher@famkind.com"
        await model.submitIdentifier(); await model.confirmIdentifier()
        model.password = FakeAuthService.password
        await model.submitPassword()
        for _ in 0..<5 {
            model.code = "000000"
            await model.submitCode()
        }
        model.code = FakeAuthService.code // even the right code is refused now
        await model.submitCode()
        XCTAssertEqual(model.errorMessage, AuthError.locked.message)
        XCTAssertTrue(completed.isEmpty)
    }

    func testTheResendButtonWaitsThirtySeconds() async {
        let clock = TestClock()
        let model = makeModel(clock: clock)
        model.start()
        model.identifier = "new@example.com"
        await model.submitIdentifier(); await model.confirmIdentifier()
        XCTAssertEqual(model.resendSeconds(), 30)
        await model.resendCode()
        XCTAssertEqual(model.resendSeconds(), 30, "too soon: nothing was resent")
        clock.advance(12)
        XCTAssertEqual(model.resendSeconds(), 18)
        clock.advance(20)
        XCTAssertEqual(model.resendSeconds(), 0)
        await model.resendCode()
        XCTAssertEqual(model.resendSeconds(), 30, "a new code starts the wait again")
    }

    // MARK: Forgot password

    func testForgotPasswordGoesCodeThenNewPassword() async {
        let model = makeModel()
        model.start()
        model.identifier = "s.park"
        await model.submitIdentifier(); await model.confirmIdentifier()
        XCTAssertEqual(model.step, .password)
        await model.forgotPassword()
        XCTAssertEqual(model.intent, .reset)
        XCTAssertEqual(model.step, .code)

        model.code = FakeAuthService.code
        await model.submitCode()
        XCTAssertEqual(model.step, .password, "then the new password")
        model.password = "short"
        model.confirmPassword = "short"
        XCTAssertFalse(model.canSubmitPassword)
        model.password = "a brand new password"
        model.confirmPassword = "a brand new password"
        await model.submitPassword()
        XCTAssertEqual(completed.count, 1, "the code and the new password signed the person in")
    }

    // MARK: Moving back

    func testBackMovesThroughTheScreens() async {
        let model = makeModel()
        model.start()
        XCTAssertEqual(model.step, .identifier)
        model.back()
        XCTAssertEqual(model.step, .welcome)
        model.start()
        model.identifier = "teacher@famkind.com"
        await model.submitIdentifier(); await model.confirmIdentifier()
        model.back()
        XCTAssertEqual(model.step, .identifier)
    }

    func testPasswordStrengthHints() {
        XCTAssertEqual(PasswordChecks(password: "", confirmation: "", creating: true).hint, "At least 10 characters.")
        XCTAssertEqual(PasswordChecks(password: "abc", confirmation: "", creating: true).strength, .tooShort)
        XCTAssertEqual(PasswordChecks(password: "abcdefghij", confirmation: "", creating: true).strength, .fair)
        XCTAssertEqual(PasswordChecks(password: "Abcdefghi1", confirmation: "", creating: true).strength, .good)
        XCTAssertEqual(PasswordChecks(password: "a long phrase of random words", confirmation: "", creating: true).strength, .strong)
    }
}

// MARK: Tokens, the Keychain, signing out

final class SessionKeychainTests: XCTestCase {
    func testTokensRoundTripAndAreRemovedOnClear() throws {
        let service = "app.lime.tests.session.\(UUID().uuidString)"
        defer { SessionKeychain.clear(service: service) }
        XCTAssertNil(SessionKeychain.load(service: service))
        let tokens = AuthTokens(accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSince1970: 2_000_000_000), userID: "u")
        try SessionKeychain.save(tokens, service: service)
        XCTAssertEqual(SessionKeychain.load(service: service), tokens)
        var newer = tokens
        newer.accessToken = "b"
        try SessionKeychain.save(newer, service: service)
        XCTAssertEqual(SessionKeychain.load(service: service)?.accessToken, "b", "saving again replaces it")
        SessionKeychain.clear(service: service)
        XCTAssertNil(SessionKeychain.load(service: service))
    }

    func testTokensKnowWhenTheyAreAboutToExpire() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(AuthTokens(accessToken: "", refreshToken: "", expiresAt: now.addingTimeInterval(60), userID: "").isExpiring(at: now))
        XCTAssertFalse(AuthTokens(accessToken: "", refreshToken: "", expiresAt: now.addingTimeInterval(600), userID: "").isExpiring(at: now))
    }
}

@MainActor
final class AccountSessionTests: XCTestCase {
    func testSigningOutClearsTheTokensTheProfileAndTheLocalStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lime-signout-\(UUID().uuidString)", isDirectory: true)
        let keychainService = "app.lime.tests.storage.\(UUID().uuidString)"
        let sessionService = "app.lime.tests.session.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: "lime-tests-\(UUID().uuidString)")!
        addTeardownBlock {
            StorageKeychain.deleteKey(service: keychainService)
            SessionKeychain.clear(service: sessionService)
            try? FileManager.default.removeItem(at: directory)
        }
        let location = StorageBootstrap.Location(directory: directory, keychainService: keychainService)
        let store = ConversationStore(storageLocation: location)
        let session = AccountSession(auth: FakeAuthService(), config: nil, store: store, sessionService: sessionService, defaults: suite)

        let tokens = AuthTokens(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), userID: "u")
        await session.completeSignIn(tokens: tokens, profile: Profile(displayName: "Ada", username: nil, school: nil))
        XCTAssertEqual(session.phase, .signedIn)
        XCTAssertEqual(SessionKeychain.load(service: sessionService), tokens)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.databaseURL.path))
        XCTAssertNotNil(StorageKeychain.existingKey(service: keychainService))
        XCTAssertEqual(store.conversations.count, 0, "a new account's Messages is empty")
        let generation = session.onboardingGeneration

        await session.signOut()
        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertNil(SessionKeychain.load(service: sessionService), "the tokens are gone from the Keychain")
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.databaseURL.path), "the local store is gone")
        XCTAssertNil(StorageKeychain.existingKey(service: keychainService), "and its key")
        XCTAssertNil(session.profile)
        XCTAssertEqual(session.onboardingGeneration, generation + 1, "the onboarding starts fresh")
    }
}

// MARK: The live service, against a stubbed network

final class LiveAuthServiceTests: XCTestCase {
    private func makeService() -> LiveAuthService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return LiveAuthService(config: BackendConfig(url: URL(string: "https://example.invalid")!, apiKey: "public"),
                               session: URLSession(configuration: configuration))
    }

    private func reply(_ status: Int, _ json: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        StubURLProtocol.handler = { _ in (status, data) }
    }

    func testIdentifyMapsTheAnswers() async throws {
        let service = makeService()
        reply(200, ["kind": "email", "exists": true, "hint": "t•••@x.com"])
        let existing = try await service.identify("t@x.com")
        XCTAssertEqual(existing, .existingEmail)
        reply(200, ["kind": "email", "exists": false, "hint": "t•••@x.com"])
        let new = try await service.identify("t@x.com")
        XCTAssertEqual(new, .newEmail)
        reply(200, ["kind": "username", "hint": "s•••@famkind.com"])
        let named = try await service.identify("s.park")
        XCTAssertEqual(named, .existingUsername(hint: "s•••@famkind.com"))
        reply(404, ["error": "not_found"])
        let none = try await service.identify("nobody")
        XCTAssertEqual(none, .unknownUsername)
    }

    func testSignInReturnsTheSessionAndTheMaskedAddress() async throws {
        reply(200, ["access_token": "a", "refresh_token": "r", "expires_in": 3600, "user_id": "u", "masked_email": "s•••@famkind.com"])
        let result = try await makeService().signIn(identifier: "s.park", password: "pw")
        XCTAssertEqual(result.tokens.accessToken, "a")
        XCTAssertEqual(result.tokens.userID, "u")
        XCTAssertEqual(result.maskedEmail, "s•••@famkind.com")
        XCTAssertFalse(result.tokens.isExpiring())
    }

    func testTheServersErrorsBecomeTheAppsErrors() async {
        let service = makeService()
        let cases: [(Int, [String: Any], AuthError)] = [
            (401, ["error": "invalid_credentials"], .invalidCredentials),
            (400, ["error": "bad_code", "message": "That code is not right. 3 tries left."], .badCode(message: "That code is not right. 3 tries left.")),
            (429, ["error": "locked"], .locked),
            (409, ["error": "account_exists"], .accountExists),
            (429, ["error": "rate_limited"], .rateLimited),
            (403, ["error": "not_verified"], .notVerified),
            (502, ["error": "email_failed"], .emailFailed),
            (400, ["error": "weak_password"], .weakPassword),
        ]
        for (status, body, expected) in cases {
            reply(status, body)
            do {
                _ = try await service.signIn(identifier: "x", password: "y")
                XCTFail("\\(expected) should have been thrown")
            } catch {
                XCTAssertEqual(error as? AuthError, expected)
            }
        }
    }

    func testANetworkFailureIsReportedAsOne() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeService().identify("x@y.com")
            XCTFail("expected a network error")
        } catch {
            XCTAssertEqual(error as? AuthError, .network)
        }
    }

    func testRefreshKeepsTheUserAndGetsNewTokens() async throws {
        reply(200, ["access_token": "new", "refresh_token": "newer", "expires_in": 3600, "user": ["id": "u"]])
        let old = AuthTokens(accessToken: "old", refreshToken: "r", expiresAt: Date(), userID: "u")
        let fresh = try await makeService().refresh(old)
        XCTAssertEqual(fresh.accessToken, "new")
        XCTAssertEqual(fresh.refreshToken, "newer")
        XCTAssertEqual(fresh.userID, "u")
    }
}
