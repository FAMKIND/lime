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
        /// How to sign this account in again (a new phone, or this one after signing out).
        let email: String
        let password: String
        let userID: String
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

        return try await signIn(stack, service: service, tokens: verified, profile: profile, name: name, username: username, email: address, password: "a long enough password")
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
        return try await signIn(stack, service: LiveAuthService(config: stack.config), tokens: tokens, profile: profile, name: name, username: username, email: email, password: password)
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

    private func signIn(_ stack: Stack, service: LiveAuthService, tokens: AuthTokens, profile: Profile, name: String, username: String, email: String, password: String) async throws -> Phone {
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
        return Phone(name: name, username: username, store: store, session: session, location: location, email: email, password: password, userID: tokens.userID)
    }

    /// The account signs in again on a phone with NO keys (this one after signing out, or a new one):
    /// its first registration there has new keys, so the server replaces the account's keys.
    private func signInAgain(_ stack: Stack, _ old: Phone) async throws -> Phone {
        let service = LiveAuthService(config: stack.config)
        let profile = Profile(displayName: old.name, username: old.username, school: "Test School")
        if let key = stack.serviceKey {
            func post(_ path: String, key: String, body: [String: Any]) async throws -> [String: Any] {
                var request = URLRequest(url: URL(string: stack.config.url.absoluteString + path)!)
                request.httpMethod = "POST"
                request.setValue(key, forHTTPHeaderField: "apikey")
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, _) = try await URLSession.shared.data(for: request)
                return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            }
            let session = try await post("/auth/v1/token?grant_type=password", key: stack.config.apiKey, body: ["email": old.email, "password": old.password])
            let access = try XCTUnwrap(session["access_token"] as? String)
            let claims = try XCTUnwrap(try JSONSerialization.jsonObject(with: Self.jwtClaims(access)) as? [String: Any])
            _ = try await post("/rest/v1/auth_proofs", key: key, body: ["session_id": try XCTUnwrap(claims["session_id"] as? String), "user_id": old.userID, "password_ok": true, "code_ok": true])
            let tokens = AuthTokens(accessToken: access, refreshToken: try XCTUnwrap(session["refresh_token"] as? String), expiresAt: Date().addingTimeInterval(3000), userID: old.userID)
            return try await signIn(stack, service: service, tokens: tokens, profile: profile, name: old.name, username: old.username, email: old.email, password: old.password)
        }
        try await Task.sleep(for: .milliseconds(1300)) // Auth sends at most one email a second to an address
        let started = Date().addingTimeInterval(-2)
        let step = try await service.signIn(identifier: old.email, password: old.password)
        let code = try await emailedCode(stack, to: old.email, since: started)
        try await service.verifySignInCode(code, tokens: step.tokens)
        return try await signIn(stack, service: service, tokens: step.tokens, profile: profile, name: old.name, username: old.username, email: old.email, password: old.password)
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

    /// Bob signs out (the phone forgets its keys) while Ada writes to him, then signs in again: new
    /// keys replace his old ones, Ada hears her message was not delivered, accepts his new key and
    /// resends, and they chat again. Runs locally (mail catcher) or on staging (admin API).
    private func replacingKeys(_ stack: Stack) async throws {
        let ada = stack.serviceKey != nil ? try await makeAdminPhone(stack, name: "Ada Lovelace") : try await makePhone(stack, name: "Ada Lovelace")
        if stack.serviceKey == nil { try await Task.sleep(for: .milliseconds(1100)) }
        var bob = stack.serviceKey != nil ? try await makeAdminPhone(stack, name: "Bob Brown") : try await makePhone(stack, name: "Bob Brown")

        let found = try await ada.store.find("@\(bob.username)")
        let person = try XCTUnwrap(found)
        await ada.store.startChat(with: person)
        let chat = "dm:\(person.userId)"
        await ada.store.sendNow("hello Bob", in: chat)
        await eventually("Bob gets the request") { bob.store.requests.count == 1 }
        await bob.store.accept(try XCTUnwrap(bob.store.requests.first).id)
        // Accepting gives Ada Bob's delivery key (send it now, so her next message is sealed).
        await bob.store.deliverNow()
        var adaHolds = 0
        for _ in 0..<20 where adaHolds == 0 {
            await ada.store.syncNow()
            adaHolds = await ada.store.sealedContactCount()
            if adaHolds == 0 { try await Task.sleep(for: .milliseconds(300)) }
        }
        XCTAssertEqual(adaHolds, 1, "Ada holds Bob's delivery key")

        // Bob signs out (his keys are wiped). Ada writes; the server holds it for his old phone.
        await bob.session.signOut()
        await ada.store.sendNow("while you are away", in: chat)
        XCTAssertEqual(ada.store.conversation(chat)?.messages.last?.state, .sent)

        // Bob signs in again: a phone with new keys. The server replaces his keys.
        bob = try await signInAgain(stack, bob)
        XCTAssertTrue(bob.session.deviceRegistered, "a signed-in phone with new keys registers instead of being locked out")
        XCTAssertNil(bob.store.problem)

        // The message that was waiting for his old phone was SEALED, so the server cannot say whom to tell: it
        // still reads "Sent". (An identified message would have been marked "Not delivered": the cost of sealed sender.)
        await ada.store.syncNow()
        XCTAssertEqual(ada.store.conversation(chat)?.messages.map(\.state), [.sent, .sent])

        // Ada writes again and meets his new key: she is asked to accept it, does. The delivery key she held for Bob
        // died with his old phone, so the server refuses her sealed send; the app sends it identified at once, silently:
        // it reads "Sent" and reaches his new phone (in Requests: it has no history).
        await ada.store.sendNow("are you there?", in: chat)
        XCTAssertEqual(ada.store.conversation(chat)?.keyChangePending, true, "the chat asks to accept the new key")
        await ada.store.trustKey(chat)
        XCTAssertEqual(ada.store.conversation(chat)?.keyChangePending, false)
        await eventually("Ada's message reaches Bob's new phone") { bob.store.requests.count == 1 }
        XCTAssertEqual(bob.store.requests.first?.messages.map(\.text), ["are you there?"])
        XCTAssertEqual(ada.store.conversation(chat)?.messages.last?.state, .sent, "no \"Not delivered\": the fallback is silent")

        // Bob accepts, replies; Ada (who accepted his new key) receives it live.
        await bob.store.accept(try XCTUnwrap(bob.store.requests.first).id)
        await bob.store.sendNow("I'm back", in: "dm:\(ada.userID)")
        await eventually("Bob's reply reaches Ada live") { ada.store.conversation(chat)?.messages.last?.text == "I'm back" }

        await ada.session.signOut()
        await bob.session.signOut()
    }

    func testAPhoneWithNewKeysReplacesTheAccountKeysLocally() async throws {
        let stack = try stack()
        guard stack.mail != nil, stack.serviceKey == nil else { throw XCTSkip("The local run (mail catcher, no admin key).") }
        try await replacingKeys(stack)
    }

    func testAPhoneWithNewKeysReplacesTheAccountKeysOnStaging() async throws {
        let stack = try stack()
        guard stack.serviceKey != nil else { throw XCTSkip("The staging run (./ios/run-e2e-staging.sh).") }
        try await replacingKeys(stack)
    }

    /// A thread through the real server: a reply shows on the other phone live as "1 reply" under the root (and
    /// not in the timeline), the thread opens with its replies, a reply back arrives live, unread counts
    /// clear when read, and it all survives a restart.
    func testRepliesInAThreadReachTheOtherPhoneLive() async throws {
        let stack = try stack()
        guard stack.mail != nil, stack.serviceKey == nil else { throw XCTSkip("The local run (mail catcher, no admin key).") }
        let ada = try await makePhone(stack, name: "Ada Lovelace")
        try await Task.sleep(for: .milliseconds(1100))
        let bob = try await makePhone(stack, name: "Bob Brown")
        let found = try await ada.store.find("@\(bob.username)")
        let person = try XCTUnwrap(found)
        await ada.store.startChat(with: person)
        let adaChat = "dm:\(person.userId)"
        await ada.store.sendNow("Who has the field trip forms?", in: adaChat)
        await eventually("the question reaches Bob") { bob.store.requests.count == 1 }
        let bobChat = try XCTUnwrap(bob.store.requests.first).id
        await bob.store.accept(bobChat)
        let root = try XCTUnwrap(bob.store.conversation(bobChat)?.messages.first?.id)
        XCTAssertEqual(root, ada.store.conversation(adaChat)?.messages.first?.id, "both phones know the message by the same id")

        // Bob replies in a thread. Ada sees "1 reply" live, not a new message in the timeline.
        await bob.store.openThread(root)
        await bob.store.sendReply("I do, in the staff room", root: root, in: bobChat)
        await eventually("the reply reaches Ada live") { ada.store.conversation(adaChat)?.messages.first?.thread?.replyCount == 1 }
        XCTAssertEqual(ada.store.conversation(adaChat)?.messages.map(\.text), ["Who has the field trip forms?"], "replies are not in the timeline")
        XCTAssertEqual(ada.store.conversation(adaChat)?.messages.first?.thread?.unread, 1)
        XCTAssertEqual(ada.store.conversation(adaChat)?.messages.first?.thread?.repliers.count, 1)
        XCTAssertEqual(bob.store.threads[root]?.map(\.text), ["Who has the field trip forms?", "I do, in the staff room"])
        XCTAssertEqual(bob.store.threads[root]?.last?.state, .sent, "Sent once the server accepted it")

        // Ada opens the thread, reads it, and replies; Bob sees it live inside his open thread.
        await ada.store.openThread(root)
        XCTAssertEqual(ada.store.threads[root]?.map(\.text), ["Who has the field trip forms?", "I do, in the staff room"])
        await ada.store.markThreadRead(root, in: adaChat)
        XCTAssertEqual(ada.store.conversation(adaChat)?.messages.first?.thread?.unread, 0)
        await ada.store.sendReply("thanks, I'll pick them up", root: root, in: adaChat)
        await eventually("Ada's reply reaches Bob's open thread live") { bob.store.threads[root]?.count == 3 }
        XCTAssertEqual(bob.store.threads[root]?.last?.text, "thanks, I'll pick them up")
        XCTAssertEqual(bob.store.conversation(bobChat)?.messages.first?.thread?.replyCount, 2)
        XCTAssertEqual(bob.store.conversation(bobChat)?.messages.count, 1, "still one message in the timeline")
        XCTAssertEqual(bob.store.conversation(bobChat)?.messages.first?.thread?.unread, 1, "Ada's reply is new to Bob")
        await bob.store.markThreadRead(root, in: bobChat)
        XCTAssertEqual(bob.store.conversation(bobChat)?.messages.first?.thread?.unread, 0)

        // Restart both phones: the threads are still there.
        let adaAgain = ConversationStore(storageLocation: ada.location)
        let bobAgain = ConversationStore(storageLocation: bob.location)
        await adaAgain.bootstrap(arguments: [])
        await bobAgain.bootstrap(arguments: [])
        XCTAssertEqual(adaAgain.conversation(adaChat)?.messages.first?.thread?.replyCount, 2)
        XCTAssertEqual(bobAgain.conversation(bobChat)?.messages.first?.thread?.replyCount, 2)
        await adaAgain.openThread(root)
        XCTAssertEqual(adaAgain.threads[root]?.count, 3)

        // A search finds the reply and names its thread.
        let hit = await ada.store.search("staff room")
        XCTAssertEqual(hit.messages.first?.threadRoot, root)

        await ada.session.signOut()
        await bob.session.signOut()
    }

    /// A group of three through the real server and the Realtime nudge: made, chatted in, renamed, someone
    /// removed (who then reads nothing more), added back, and someone leaving.
    func testAGroupOfThreeChatsLiveAndTheOwnerManagesIt() async throws {
        let stack = try stack()
        guard stack.mail != nil, stack.serviceKey == nil else { throw XCTSkip("The local run (mail catcher, no admin key).") }
        let ada = try await makePhone(stack, name: "Ada Lovelace")
        try await Task.sleep(for: .milliseconds(1100))
        let bob = try await makePhone(stack, name: "Bob Brown")
        try await Task.sleep(for: .milliseconds(1100))
        let cy = try await makePhone(stack, name: "Cy Clark")
        let chatLines = { (phone: Phone, chat: String) -> [String] in
            phone.store.conversation(chat)?.messages.filter { !$0.isSystem }.map(\.text) ?? []
        }

        // Ada makes the group: Bob and Cy get it live, in Requests (they do not know her).
        let made = await ada.store.createGroup(name: "Grade 4 Team", emoji: "🍎", members: [bob.userID, cy.userID])
        let chat = try XCTUnwrap(made)
        await eventually("the group reaches Bob and Cy") { bob.store.requests.count == 1 && cy.store.requests.count == 1 }
        XCTAssertEqual(bob.store.requests.first?.title, "Grade 4 Team")
        XCTAssertEqual(bob.store.requests.first?.isGroup, true)
        await bob.store.accept(chat)
        await cy.store.accept(chat)

        // Talk: one message reaches both; Bob's answer reaches Ada and Cy.
        await ada.store.sendNow("hello team", in: chat)
        await eventually("hello reaches Bob and Cy") { chatLines(bob, chat) == ["hello team"] && chatLines(cy, chat) == ["hello team"] }
        await bob.store.sendNow("hi all", in: chat)
        await eventually("Bob's reply reaches Ada and Cy") { chatLines(ada, chat) == ["hello team", "hi all"] && chatLines(cy, chat) == ["hello team", "hi all"] }
        XCTAssertEqual(ada.store.conversation(chat)?.messages.first?.text, "You created the group “Grade 4 Team”", "a system line")

        // Ada renames it: everyone's title follows.
        let renamed = await ada.store.renameGroup(chat, to: "Fourth Grade")
        XCTAssertTrue(renamed)
        await eventually("the new name reaches Bob and Cy") { bob.store.conversation(chat)?.title == "Fourth Grade" && cy.store.conversation(chat)?.title == "Fourth Grade" }

        // Ada removes Cy: Cy's copy is gone, and what Ada says next reaches Bob only.
        await ada.store.removeFromGroup(chat, user: cy.userID)
        await eventually("Cy no longer has the group") { cy.store.conversation(chat) == nil }
        await ada.store.sendNow("after Cy left", in: chat)
        await eventually("Bob reads it") { chatLines(bob, chat).last == "after Cy left" }
        try await Task.sleep(for: .seconds(2))
        await cy.store.syncNow()
        XCTAssertNil(cy.store.conversation(chat), "nothing more is shown to Cy")

        // Ada adds Cy back: Cy has the group again, reads what is said from now on, not what was said before.
        await ada.store.addToGroup(chat, users: [cy.userID])
        await eventually("Cy has the group again") { cy.store.conversation(chat) != nil }
        await ada.store.sendNow("welcome back", in: chat)
        await eventually("Cy reads the new message") { chatLines(cy, chat).contains("welcome back") }
        XCTAssertFalse(chatLines(cy, chat).contains("after Cy left"), "a message from before the return stays unreadable")

        // Bob leaves: his copy goes, and Ada sees a line about it.
        await bob.store.leaveGroup(chat)
        XCTAssertNil(bob.store.conversation(chat))
        await eventually("Ada hears Bob left") { ada.store.conversation(chat)?.messages.contains { $0.isSystem && $0.text.contains("left") } == true }
        let details = await ada.store.groupDetails(chat)
        XCTAssertEqual(details?.members.count, 2)

        await ada.session.signOut()
        await bob.session.signOut()
        await cy.session.signOut()
    }

    /// Notifications through the real server: a stranger's first message is announced without its words, an
    /// accepted chat's message shows its words, the chat on screen only ticks, a muted chat is silent, a
    /// thread reply says so, and with Lime in the background the announcement is a local notification.
    func testArrivalsAreAnnouncedByTheNotificationRules() async throws {
        let stack = try stack()
        guard stack.mail != nil, stack.serviceKey == nil else { throw XCTSkip("The local run (mail catcher, no admin key).") }
        let ada = try await makePhone(stack, name: "Ada Lovelace")
        try await Task.sleep(for: .milliseconds(1100))
        let bob = try await makePhone(stack, name: "Bob Brown")
        let center = FakeCenter()
        let bobNotes = NotificationCoordinator(settings: NotificationSettings(defaults: UserDefaults(suiteName: "lime.e2e.\(UUID().uuidString)")!),
                                               center: center, feedback: center)
        bob.store.notifications = bobNotes
        await bob.store.reload() // the first look only learns what is already here
        await bobNotes.refreshAuthorization()

        let found = try await ada.store.find("@\(bob.username)")
        let person = try XCTUnwrap(found)
        await ada.store.startChat(with: person)
        let adaChat = "dm:\(person.userId)"
        await ada.store.sendNow("Who has the field trip forms?", in: adaChat)
        await eventually("the request reaches Bob") { bob.store.requests.count == 1 }
        XCTAssertEqual(bobNotes.banner?.content.body, "Wants to message you", "a stranger's words are never shown")
        XCTAssertFalse(bobNotes.banner?.content.body.contains("field trip") ?? true)
        let bobChat = try XCTUnwrap(bob.store.requests.first).id
        await bob.store.accept(bobChat)
        bobNotes.dismissBanner()

        await ada.store.sendNow("Second message, with words", in: adaChat)
        await eventually("an accepted chat's message shows its words") { bobNotes.banner?.content.body == "Second message, with words" }
        XCTAssertEqual(bobNotes.banner?.content.title, "Ada Lovelace")
        XCTAssertEqual(center.sounds, 2)

        bobNotes.dismissBanner()
        bobNotes.viewing = ViewingTarget(conversationID: bobChat)
        await ada.store.sendNow("Third, while Bob is in the chat", in: adaChat)
        await eventually("the open chat only ticks") { center.ticks == 1 }
        XCTAssertNil(bobNotes.banner)

        bobNotes.viewing = nil
        bobNotes.settings.mute(bobChat, for: .hour)
        await ada.store.sendNow("Fourth, muted", in: adaChat)
        await eventually("a muted chat is announced as nothing") { bobNotes.log.last == Presentation.none }
        XCTAssertNil(bobNotes.banner)

        bobNotes.settings.unmute(bobChat)
        bobNotes.isActive = false
        let root = try XCTUnwrap(bob.store.conversation(bobChat)?.messages.first?.id)
        await ada.store.openThread(root)
        await ada.store.sendReply("A reply in a thread", root: root, in: adaChat)
        await eventually("in the background the reply becomes a local notification") { center.scheduled.contains { $0.body == "Replied in a thread: A reply in a thread" } }
        let local = try XCTUnwrap(center.scheduled.last)
        XCTAssertEqual(local.threadRoot, root, "tapping it opens the thread")
        XCTAssertEqual(local.threadIdentifier, bobChat, "grouped by chat")
        XCTAssertNil(bobNotes.banner)

        await ada.session.signOut()
        await bob.session.signOut()
    }

    /// A formatted message through the real server: both phones hold the same Markdown, parse it to the same
    /// blocks (so it draws identically), and the receiver finds it by its words, not its markup.
    func testAFormattedMessageRendersTheSameOnTheReceiver() async throws {
        let stack = try stack()
        guard stack.mail != nil, stack.serviceKey == nil else { throw XCTSkip("The local run (mail catcher, no admin key).") }
        let ada = try await makePhone(stack, name: "Ada Lovelace")
        try await Task.sleep(for: .milliseconds(1100))
        let bob = try await makePhone(stack, name: "Bob Brown")
        let found = try await ada.store.find("@\(bob.username)")
        let person = try XCTUnwrap(found)
        await ada.store.startChat(with: person)
        let chat = "dm:\(person.userId)"

        let written = ComposerDocument.markdown(from: ComposerDocument.attributed(fromMarkdown:
            "Plan for **Friday**, see [the policy](https://limechat.org/policy)\n\n- bring *signed* forms\n- check `room 12`\n\n```\nlet a = **raw**\n```\n\n1. copy\n2. sign"))
        await ada.store.sendNow(written, in: chat)
        await eventually("the formatted message reaches Bob") { bob.store.requests.count == 1 }
        let theirs = try XCTUnwrap(bob.store.requests.first?.messages.first)
        let mine = try XCTUnwrap(ada.store.conversation(chat)?.messages.first)
        XCTAssertEqual(mine.text, theirs.text, "both phones hold the same written form")
        XCTAssertEqual(MessageRender.blocks(mine.text), MessageRender.blocks(theirs.text), "so it is drawn identically")
        XCTAssertEqual(MessageRender.blocks(theirs.text).count, 4, "a paragraph, a list, a code block and a numbered list")
        XCTAssertEqual(messagePlainText(text: theirs.text), messagePlainText(text: mine.text))

        let byWord = await bob.store.search("friday")
        XCTAssertEqual(byWord.messages.count, 1, "found by its words")
        let byMarkup = await bob.store.search("limechat")
        XCTAssertTrue(byMarkup.messages.isEmpty, "a link's address is not searched")
        let preview = messagePlainText(text: theirs.text).replacingOccurrences(of: "\n", with: " ")
        XCTAssertTrue(preview.hasPrefix("Plan for Friday, see the policy"), preview)
        XCTAssertFalse(preview.prefix(60).contains("**") || preview.contains("]("), "the list preview has no markup (a code block stays as written)")

        await ada.session.signOut()
        await bob.session.signOut()
    }

    /// Settings against the real local server: the About line and hiding from search reach other
    /// phones, a taken username is refused, the password changes with an emailed code (this phone
    /// carries on, the old password stops working), and unblocking brings a chat back.
    func testSettingsAgainstTheLocalStack() async throws {
        let stack = try stack()
        guard stack.mail != nil, stack.serviceKey == nil else { throw XCTSkip("The local run (mail catcher, no admin key).") }
        let ada = try await makePhone(stack, name: "Ada Lovelace")
        try await Task.sleep(for: .milliseconds(1100))
        let bob = try await makePhone(stack, name: "Bob Brown")

        // The About line is public: Bob sees it when he finds Ada.
        var draft = ProfileDraft(try XCTUnwrap(ada.session.profile))
        draft.aboutEmoji = "👋"
        draft.aboutText = "Happy to help"
        try await ada.session.updateProfile(draft)
        XCTAssertEqual(ada.session.profile?.about, "👋 Happy to help")
        let seen = try await bob.store.find("@\(ada.username)")
        XCTAssertEqual(seen?.aboutText, "Happy to help")
        XCTAssertEqual(seen?.aboutEmoji, "👋")

        // Hide me from search: Bob can no longer find her; un-hiding brings her back.
        draft.hideFromSearch = true
        try await ada.session.updateProfile(draft)
        let hidden = try await bob.store.find("@\(ada.username)")
        XCTAssertNil(hidden, "hidden from search")
        draft.hideFromSearch = false
        try await ada.session.updateProfile(draft)
        let back = try await bob.store.find("@\(ada.username)")
        XCTAssertNotNil(back)

        // A username somebody has is refused, in the app's words.
        var steal = ProfileDraft(try XCTUnwrap(bob.session.profile))
        steal.username = ada.username.uppercased()
        do {
            try await bob.session.updateProfile(steal)
            XCTFail("a taken username must be refused")
        } catch {
            XCTAssertEqual(error as? AuthError, .usernameTaken)
        }

        // Your own masked address comes from the server for the Account screen.
        let service = LiveAuthService(config: stack.config)
        let loaded = try await service.loadProfile(tokens: try await ada.session.debugTokens())
        XCTAssertTrue(loaded?.maskedEmail?.contains("•••") == true)
        XCTAssertFalse(loaded?.maskedEmail?.contains(ada.email) == true, "the full address is never sent")

        // Change the password: the current one, an emailed code, then the new one.
        let newPassword = "an even longer new password"
        try await Task.sleep(for: .milliseconds(1300))
        let started = Date().addingTimeInterval(-1)
        do {
            try await ada.session.startPasswordChange(current: "not the current password")
            XCTFail("a wrong current password must be refused")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }
        try await ada.session.startPasswordChange(current: ada.password)
        let code = try await emailedCode(stack, to: ada.email, since: started)
        try await ada.session.finishPasswordChange(code: code, newPassword: newPassword)
        let still = try await ada.store.find("@\(bob.username)")
        XCTAssertNotNil(still, "this phone carries on with the fresh session")
        XCTAssertNil(ada.store.problem)
        try await Task.sleep(for: .milliseconds(1300))
        do {
            _ = try await service.signIn(identifier: ada.email, password: ada.password)
            XCTFail("the old password must stop working")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }
        _ = try await service.signIn(identifier: ada.email, password: newPassword)

        // Block, then unblock: the chat comes back with what was said before.
        let person = try XCTUnwrap(back)
        await bob.store.startChat(with: person)
        await bob.store.sendNow("hello Ada", in: "dm:\(person.userId)")
        await eventually("the request reaches Ada") { ada.store.requests.count == 1 }
        let request = try XCTUnwrap(ada.store.requests.first)
        await ada.store.block(request.id)
        let blocked = await ada.store.blockedPeople()
        XCTAssertEqual(blocked.map(\.name), ["Bob Brown"])
        XCTAssertTrue(ada.store.conversations.isEmpty)
        await ada.store.unblock(request.id)
        let none = await ada.store.blockedPeople()
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(ada.store.conversation(request.id)?.messages.map(\.text), ["hello Ada"], "unblocking restores the messages")

        await ada.session.signOut()
        await bob.session.signOut()
    }

    private func converse(_ ada: Phone, _ bob: Phone) async throws {

        // An hour later: Ada's access token has expired. Two searches at once refresh it ONCE (a refresh
        // token is single-use) and both work, on the same verified session.
        ada.session.debugExpireAccessToken()
        async let early = ada.store.find(String(bob.username.prefix(5)))
        async let earlier = ada.store.find(String(bob.username.prefix(6)))
        _ = try await (early, earlier)
        XCTAssertNil(ada.store.problem, "a refreshed session is a working session")
        await ada.store.syncNow()
        XCTAssertNil(ada.store.problem)

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

        // Both hold each other's delivery key since Bob accepted (sealed sends, nothing looks different).
        let adaHolds = await ada.store.sealedContactCount(), bobHolds = await bob.store.sealedContactCount()
        XCTAssertEqual(adaHolds, 1)
        XCTAssertEqual(bobHolds, 1)

        // Bob blocks Ada: his delivery key rotates, so her next (sealed) message is refused by the server. The app
        // says nothing: it sends the message identified at once and shows "Sent". Bob never sees it.
        await bob.store.block(request.id)
        await bob.store.deliverNow() // the new key's hash reaches the server
        XCTAssertTrue(bob.store.conversations.isEmpty)
        await ada.store.sendNow("are you there?", in: adaChat)
        XCTAssertEqual(ada.store.conversation(adaChat)?.messages.last?.state, .sent, "a blocked person is not told")
        try await Task.sleep(for: .seconds(2)) // long enough for the nudge and a sync
        await bob.store.syncNow()
        XCTAssertTrue(bob.store.conversations.isEmpty, "a blocked sender's messages stay hidden")
        let refused = await ada.store.sealedContactCount()
        XCTAssertEqual(refused, 0, "Ada's key for Bob was refused: no more sealed sends until he shares a new one")

        // Bob unblocks her: she is given the new key (live), and what she writes next is sealed again.
        await bob.store.unblock(request.id)
        var held = await ada.store.sealedContactCount()
        for _ in 0..<20 where held == 0 {
            try await Task.sleep(for: .milliseconds(500))
            await ada.store.syncNow()
            held = await ada.store.sealedContactCount()
        }
        XCTAssertEqual(held, 1, "Bob's new key arrived")
        await ada.store.sendNow("sealed again", in: adaChat)
        XCTAssertEqual(ada.store.conversation(adaChat)?.messages.last?.state, .sent)
        await eventually("the sealed message reaches Bob live") { texts(bob, request.id).contains("sealed again") }

        await ada.session.signOut()
        await bob.session.signOut()
    }
}
