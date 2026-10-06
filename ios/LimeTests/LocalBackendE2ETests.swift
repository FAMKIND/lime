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
        let mail: URL
    }

    private func stack() throws -> Stack {
        let env = ProcessInfo.processInfo.environment
        guard let api = env["LIME_E2E_API_URL"], let key = env["LIME_E2E_ANON_KEY"], let mail = env["LIME_E2E_MAIL_URL"],
              let apiURL = URL(string: api), let mailURL = URL(string: mail) else {
            throw XCTSkip("Set LIME_E2E_API_URL, LIME_E2E_ANON_KEY and LIME_E2E_MAIL_URL (see ios/run-e2e-local.sh).")
        }
        return Stack(config: BackendConfig(url: apiURL, apiKey: key), mail: mailURL)
    }

    /// The newest 6-digit code emailed to `address` after `since`.
    private func emailedCode(_ stack: Stack, to address: String, since: Date) async throws -> String {
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
}
