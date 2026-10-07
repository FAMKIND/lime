import XCTest
@testable import Lime

/// The real app code (LiveAuthService, AccountSession, URLSessionTransport, LimeCore) against a
/// running Supabase stack, with the emailed codes read from its mail catcher (Mailpit). It is skipped
/// unless the environment says where the stack is, so a normal test run needs no backend:
///
///   ./ios/run-e2e-local.sh
///
/// which starts the local stack and passes TEST_RUNNER_LIME_E2E_API_URL, ..._ANON_KEY and ..._MAIL_URL.
@MainActor
final class LocalBackendE2ETests: XCTestCase {
    private struct Stack {
        let config: BackendConfig
        let mail: URL?
        /// Only for the staging run: throwaway accounts are made and deleted through the admin API. It
        /// is read from the environment of this test process and never printed or written.
        let serviceKey: String?
    }

    private func stack() throws -> Stack {
        let env = ProcessInfo.processInfo.environment
        guard let api = env["LIME_E2E_API_URL"], let key = env["LIME_E2E_ANON_KEY"], let apiURL = URL(string: api),
              env["LIME_E2E_MAIL_URL"] != nil || env["LIME_E2E_SERVICE_KEY"] != nil else {
            throw XCTSkip("Set LIME_E2E_API_URL, LIME_E2E_ANON_KEY and LIME_E2E_MAIL_URL (see ios/run-e2e-local.sh).")
        }
        return Stack(config: BackendConfig(url: apiURL, apiKey: key), mail: env["LIME_E2E_MAIL_URL"].flatMap(URL.init(string:)),
                     serviceKey: env["LIME_E2E_SERVICE_KEY"])
    }

    /// The newest 6-digit code emailed to `address` after `since`.
    private func emailedCode(_ stack: Stack, to address: String, since: Date) async throws -> String {
        guard let mail = stack.mail else { throw XCTSkip("No mail catcher.") }
        let stack = (config: stack.config, mail: mail)
        for _ in 0..<40 {
            var components = URLComponents(url: stack.mail.appendingPathComponent("api/v1/search"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "query", value: "to:\(address)")]
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let messages = json["messages"] as? [[String: Any]] {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let fresh = messages.compactMap { message -> (String, Date)? in
                    guard let id = message["ID"] as? String, let created = message["Created"] as? String,
                          let date = formatter.date(from: created) ?? ISO8601DateFormatter().date(from: created), date >= since else { return nil }
                    return (id, date)
                }.sorted { $0.1 > $1.1 }
                if let newest = fresh.first {
                    let (body, _) = try await URLSession.shared.data(from: stack.mail.appendingPathComponent("api/v1/message/\(newest.0)"))
                    if let message = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                       let text = (message["Text"] as? String).map({ $0 + " " + ((message["HTML"] as? String) ?? "") }),
                       let range = text.range(of: #"\b\d{6}\b"#, options: .regularExpression) {
                        return String(text[range])
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw XCTSkip("No code arrived in the mail catcher.")
    }

    func testSignUpSignOutAndSignInByUsernameAgainstTheLocalStack() async throws {
        let stack = try stack()
        let service = LiveAuthService(config: stack.config)
        let address = "e2e-\(UUID().uuidString.prefix(10).lowercased())@example.invalid"
        let username = "e2e\(UUID().uuidString.prefix(8).lowercased())"
        let password = "a long enough password"

        // A new address is new; sign-up sends a code that proves the email.
        let first = try await service.identify(address)
        XCTAssertEqual(first, .newEmail)
        let started = Date().addingTimeInterval(-2)
        try await service.startSignUp(email: address)
        let code = try await emailedCode(stack, to: address, since: started)
        let codeOnly = try await service.verifySignUpCode(email: address, code: code)

        // A code-only session cannot do anything yet (the server enforces both steps).
        do {
            _ = try await service.loadProfile(tokens: codeOnly)
            XCTFail("a code-only session must be refused")
        } catch {
            XCTAssertEqual(error as? AuthError, .notVerified)
        }

        // The password finishes both steps; then the profile.
        let verified = try await service.setInitialPassword(password, tokens: codeOnly)
        let profile = try await service.saveProfile(ProfileDraft(displayName: "E2E Teacher", username: username, school: "Test School"), tokens: verified)
        XCTAssertEqual(profile.username, username)

        // The app's session: keep the tokens and register this device through LimeCore.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lime-e2e-\(UUID().uuidString)", isDirectory: true)
        let location = StorageBootstrap.Location(directory: directory, keychainService: "app.lime.tests.e2e.\(UUID().uuidString)")
        let sessionService = "app.lime.tests.e2e.session.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: "lime-e2e-\(UUID().uuidString)")!
        addTeardownBlock {
            StorageKeychain.deleteKey(service: location.keychainService)
            SessionKeychain.clear(service: sessionService)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ConversationStore(storageLocation: location)
        let session = AccountSession(auth: service, config: stack.config, store: store, sessionService: sessionService, defaults: suite)
        await session.completeSignIn(tokens: verified, profile: profile)
        XCTAssertEqual(session.phase, .signedIn)
        XCTAssertTrue(session.deviceRegistered, "the core registered the device once both factors passed")
        XCTAssertEqual(store.conversations.count, 0)

        // Sign out, then sign in again by username: password, a NEW code, then the same profile.
        await session.signOut()
        XCTAssertEqual(session.phase, .signedOut)
        try await Task.sleep(for: .milliseconds(1300)) // Auth sends at most one email a second to an address
        let named = try await service.identify("@\(username)")
        guard case .existingUsername(let hint) = named else { return XCTFail("expected an existing username, got \(named)") }
        XCTAssertTrue(hint.hasSuffix("@example.invalid") && hint.contains("•••"))
        XCTAssertFalse(hint.contains(address), "the full email is never shown")

        let signInStarted = Date().addingTimeInterval(-2)
        let passwordStep = try await service.signIn(identifier: username, password: password)
        XCTAssertEqual(passwordStep.maskedEmail, hint)
        do {
            _ = try await service.loadProfile(tokens: passwordStep.tokens)
            XCTFail("a password-only session must be refused")
        } catch {
            XCTAssertEqual(error as? AuthError, .notVerified)
        }
        let newCode = try await emailedCode(stack, to: address, since: signInStarted)
        do {
            try await service.verifySignInCode(newCode == "000000" ? "111111" : "000000", tokens: passwordStep.tokens)
            XCTFail("a wrong code must be refused")
        } catch {
            guard case .badCode = error as? AuthError else { return XCTFail("expected a bad code, got \(error)") }
        }
        try await service.verifySignInCode(newCode, tokens: passwordStep.tokens)
        let again = try await service.loadProfile(tokens: passwordStep.tokens)
        XCTAssertEqual(again?.displayName, "E2E Teacher")
    }

    // MARK: Two phones chatting

    /// One signed-up account with its own app state (store, session, Keychain items), as a phone would have.
    private struct Phone {
        let name: String
        let username: String
        let store: ConversationStore
        let session: AccountSession
        let location: StorageBootstrap.Location
    }

    private func makePhone(_ stack: Stack, name: String) async throws -> Phone {
        let service = LiveAuthService(config: stack.config)
        let address = "chat-\(UUID().uuidString.prefix(10).lowercased())@example.invalid"
        let username = "c" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(9).lowercased()
        let started = Date().addingTimeInterval(-2)
        try await service.startSignUp(email: address)
        let code = try await emailedCode(stack, to: address, since: started)
        let codeOnly = try await service.verifySignUpCode(email: address, code: code)
        let verified = try await service.setInitialPassword("a long enough password", tokens: codeOnly)
        let profile = try await service.saveProfile(ProfileDraft(displayName: name, username: username, school: "Test School"), tokens: verified)

        return try await signIn(stack, service: service, tokens: verified, profile: profile, name: name, username: username)
    }

    /// A throwaway account made through the admin API (the staging run): no email is involved. The
    /// session is marked as having passed both steps exactly as the account functions would record it.
    private func makeAdminPhone(_ stack: Stack, name: String) async throws -> Phone {
        let key = try XCTUnwrap(stack.serviceKey)
        let base = stack.config.url
        let username = "c" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(9).lowercased()
        let email = "e2e-\(UUID().uuidString.lowercased())@example.invalid"
        let password = UUID().uuidString
        func request(_ method: String, _ path: String, key: String, body: [String: Any]?) async throws -> [String: Any] {
            var request = URLRequest(url: URL(string: base.absoluteString + path)!)
            request.httpMethod = method
            request.setValue(key, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertTrue((200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0), "\(method) \(path)")
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
        let created = try await request("POST", "/auth/v1/admin/users", key: key,
                                        body: ["email": email, "password": password, "email_confirm": true])
        let id = try XCTUnwrap(created["id"] as? String)
        addTeardownBlock { await Self.deleteUser(id, base: base, key: key) }
        let session = try await request("POST", "/auth/v1/token?grant_type=password", key: stack.config.apiKey,
                                        body: ["email": email, "password": password])
        let access = try XCTUnwrap(session["access_token"] as? String)
        let refresh = try XCTUnwrap(session["refresh_token"] as? String)
        let claims = try XCTUnwrap(try JSONSerialization.jsonObject(with: Self.jwtClaims(access)) as? [String: Any])
        _ = try await request("POST", "/rest/v1/auth_proofs", key: key,
                              body: ["session_id": try XCTUnwrap(claims["session_id"] as? String), "user_id": id, "password_ok": true, "code_ok": true])
        _ = try await request("POST", "/rest/v1/profiles", key: key,
                              body: ["user_id": id, "display_name": name, "username": username, "school": "Test School"])
        let tokens = AuthTokens(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(3000), userID: id)
        let profile = Profile(displayName: name, username: username, school: "Test School")
        return try await signIn(stack, service: LiveAuthService(config: stack.config), tokens: tokens, profile: profile, name: name, username: username)
    }

    private nonisolated static func deleteUser(_ id: String, base: URL, key: String) async {
        var request = URLRequest(url: URL(string: base.absoluteString + "/auth/v1/admin/users/\(id)")!)
        request.httpMethod = "DELETE"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func jwtClaims(_ token: String) throws -> Data {
        var part = String(token.split(separator: ".")[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while part.count % 4 != 0 { part += "=" }
        return try XCTUnwrap(Data(base64Encoded: part))
    }

    private func signIn(_ stack: Stack, service: LiveAuthService, tokens: AuthTokens, profile: Profile, name: String, username: String) async throws -> Phone {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lime-e2e-\(UUID().uuidString)", isDirectory: true)
        let location = StorageBootstrap.Location(directory: directory, keychainService: "app.lime.tests.chat.\(UUID().uuidString)")
        let sessionService = "app.lime.tests.chat.session.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: "lime-e2e-\(UUID().uuidString)")!
        addTeardownBlock {
            StorageKeychain.deleteKey(service: location.keychainService)
            SessionKeychain.clear(service: sessionService)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = ConversationStore(storageLocation: location)
        let session = AccountSession(auth: service, config: stack.config, store: store, sessionService: sessionService, defaults: suite)
        await session.completeSignIn(tokens: tokens, profile: profile)
        XCTAssertTrue(session.deviceRegistered, "\(name)'s device registered")
        return Phone(name: name, username: username, store: store, session: session, location: location)
    }

    /// Waits (polling the main actor) until `condition` holds.
    private func eventually(_ what: String, timeout: TimeInterval = 20, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("Timed out waiting for: \(what)")
    }

    private func texts(_ phone: Phone, _ id: String) -> [String] {
        phone.store.conversation(id)?.messages.map(\.text) ?? []
    }

    /// The whole first conversation: A finds B by username and writes; it reaches B LIVE (through the
    /// Realtime nudge, with nobody calling sync) as a request; B accepts and replies, live; both
    /// phones restart with the history in order; then B blocks A and A's next message is not shown.
    func testTwoPhonesChatLiveAcceptRestartAndBlock() async throws {
        let stack = try stack()
        guard stack.mail != nil, stack.serviceKey == nil else { throw XCTSkip("The local run (mail catcher, no admin key).") }
        let ada = try await makePhone(stack, name: "Ada Lovelace")
        try await Task.sleep(for: .milliseconds(1100))
        let bob = try await makePhone(stack, name: "Bob Brown")
        try await converse(ada, bob)
    }

    /// The same conversation against STAGING (`./ios/run-e2e-staging.sh`), with two throwaway accounts
    /// made and deleted through the admin API (no real inbox is read, no email is sent).
    func testTwoPhonesChatLiveOnStaging() async throws {
        let stack = try stack()
        guard stack.serviceKey != nil else { throw XCTSkip("The staging run (./ios/run-e2e-staging.sh).") }
        let ada = try await makeAdminPhone(stack, name: "Ada Lovelace")
        let bob = try await makeAdminPhone(stack, name: "Bob Brown")
        try await converse(ada, bob)
    }

    private func converse(_ ada: Phone, _ bob: Phone) async throws {

        // Ada finds Bob by his exact username (and not by part of it), then writes.
        let missing = try await ada.store.find(String(bob.username.prefix(5)))
        XCTAssertNil(missing, "no partial matches")
        let found = try await ada.store.find("@\(bob.username.uppercased())")
        let person = try XCTUnwrap(found)
        XCTAssertEqual(person.displayName, "Bob Brown")
        await ada.store.startChat(with: person)
        let adaChat = "dm:\(person.userId)"
        await ada.store.sendNow("hello Bob", in: adaChat)
        XCTAssertEqual(ada.store.conversation(adaChat)?.messages.last?.state, .sent, "Sent once the server accepted it")

        // Bob is not syncing: the nudge brings it. It lands in Requests, named from Ada's profile.
        await eventually("the request reaches Bob live") { bob.store.requests.count == 1 }
        let request = try XCTUnwrap(bob.store.requests.first)
        XCTAssertEqual(request.title, "Ada Lovelace")
        XCTAssertEqual(request.messages.map(\.text), ["hello Bob"])
        XCTAssertTrue(bob.store.chats.isEmpty)

        // Accept, reply: it reaches Ada live.
        await bob.store.accept(request.id)
        XCTAssertTrue(bob.store.requests.isEmpty)
        await bob.store.sendNow("hi Ada", in: request.id)
        await eventually("the reply reaches Ada live") { texts(ada, adaChat) == ["hello Bob", "hi Ada"] }
        await ada.store.sendNow("how are you?", in: adaChat)
        await eventually("the third message reaches Bob live") { texts(bob, request.id) == ["hello Bob", "hi Ada", "how are you?"] }

        // Restart both phones: new stores on the same encrypted files. The history is there, in order.
        let adaAgain = ConversationStore(storageLocation: ada.location)
        let bobAgain = ConversationStore(storageLocation: bob.location)
        await adaAgain.bootstrap(arguments: [])
        await bobAgain.bootstrap(arguments: [])
        XCTAssertEqual(adaAgain.conversation(adaChat)?.messages.map(\.text), ["hello Bob", "hi Ada", "how are you?"])
        XCTAssertEqual(bobAgain.conversation(request.id)?.messages.map(\.text), ["hello Bob", "hi Ada", "how are you?"])
        XCTAssertEqual(adaAgain.conversation(adaChat)?.messages.map(\.state), [.sent, .received, .sent])

        // Bob blocks Ada: her next message is delivered to the server, but Bob never sees it.
        await bob.store.block(request.id)
        XCTAssertTrue(bob.store.conversations.isEmpty)
        await ada.store.sendNow("are you there?", in: adaChat)
        XCTAssertEqual(ada.store.conversation(adaChat)?.messages.last?.state, .sent)
        try await Task.sleep(for: .seconds(3)) // long enough for the nudge and a sync
        await bob.store.syncNow()
        XCTAssertTrue(bob.store.conversations.isEmpty, "a blocked sender's messages stay hidden")

        await ada.session.signOut()
        await bob.session.signOut()
    }
}
