import Foundation

/// `AuthService` against the Supabase backend: the account Edge Functions (`identify`,
/// `signin-password`, `code-verify`, ...) and Supabase Auth's own refresh and logout.
final class LiveAuthService: AuthService, @unchecked Sendable {
    private let config: BackendConfig
    private let session: URLSession

    init(config: BackendConfig, session: URLSession = URLSession(configuration: .ephemeral)) {
        self.config = config
        self.session = session
    }

    // MARK: AuthService

    func identify(_ identifier: String) async throws -> IdentifyResult {
        let result = try await function("identify", ["identifier": identifier])
        switch result.status {
        case 200:
            if result.json["kind"] as? String == "email" {
                return (result.json["exists"] as? Bool ?? false) ? .existingEmail : .newEmail
            }
            return .existingUsername(hint: result.json["hint"] as? String ?? "")
        case 404: return .unknownUsername
        default: throw error(for: result)
        }
    }

    func signIn(identifier: String, password: String) async throws -> PasswordSignIn {
        let result = try await function("signin-password", ["identifier": identifier, "password": password])
        guard result.status == 200 else { throw error(for: result) }
        return PasswordSignIn(tokens: try tokens(from: result.json), maskedEmail: result.json["masked_email"] as? String ?? "")
    }

    func verifySignInCode(_ code: String, tokens: AuthTokens) async throws {
        let result = try await function("code-verify", ["code": code], token: tokens.accessToken)
        guard result.status == 200 else { throw error(for: result) }
    }

    func resendSignInCode(tokens: AuthTokens) async throws {
        let result = try await function("code-resend", [:], token: tokens.accessToken)
        guard result.status == 200 else { throw error(for: result) }
    }

    func startSignUp(email: String) async throws {
        let result = try await function("signup-start", ["email": email])
        guard result.status == 200 else { throw error(for: result) }
    }

    func verifySignUpCode(email: String, code: String) async throws -> AuthTokens {
        let result = try await function("signup-verify", ["email": email, "code": code])
        guard result.status == 200 else { throw error(for: result) }
        return try tokens(from: result.json)
    }

    func setInitialPassword(_ password: String, tokens: AuthTokens) async throws -> AuthTokens {
        let result = try await function("signup-set-password", ["password": password], token: tokens.accessToken)
        guard result.status == 200 else { throw error(for: result) }
        return try self.tokens(from: result.json)
    }

    func startReset(identifier: String) async throws {
        let result = try await function("reset-start", ["identifier": identifier])
        guard result.status == 200 else { throw error(for: result) }
    }

    func finishReset(identifier: String, code: String, newPassword: String) async throws -> AuthTokens {
        let result = try await function("reset-verify", ["identifier": identifier, "code": code, "new_password": newPassword])
        guard result.status == 200 else { throw error(for: result) }
        return try tokens(from: result.json)
    }

    func startPasswordChange(current: String, tokens: AuthTokens) async throws {
        let result = try await function("password-change-start", ["current_password": current], token: tokens.accessToken)
        guard result.status == 200 else { throw error(for: result) }
    }

    func finishPasswordChange(code: String, newPassword: String, tokens: AuthTokens) async throws -> AuthTokens {
        let result = try await function("password-change-verify", ["code": code, "new_password": newPassword], token: tokens.accessToken)
        guard result.status == 200 else { throw error(for: result) }
        return try self.tokens(from: result.json)
    }

    func saveProfile(_ draft: ProfileDraft, tokens: AuthTokens) async throws -> Profile {
        var body: [String: Any] = ["display_name": draft.displayName]
        if let username = draft.username { body["username"] = username }
        if let school = draft.school { body["school"] = school }
        if let emoji = draft.aboutEmoji { body["about_emoji"] = emoji }
        if let text = draft.aboutText { body["about_text"] = text }
        if let hide = draft.hideFromSearch { body["hide_from_search"] = hide }
        let result = try await function("profile-set", body, token: tokens.accessToken)
        guard result.status == 200 else { throw error(for: result) }
        return profile(from: result.json) ?? Profile(displayName: draft.displayName, username: draft.username, school: draft.school)
    }

    func loadProfile(tokens: AuthTokens) async throws -> Profile? {
        let result = try await function("profile-get", [:], token: tokens.accessToken)
        guard result.status == 200 else { throw error(for: result) }
        guard let profile = result.json["profile"] as? [String: Any] else { return nil }
        var loaded = self.profile(from: profile)
        loaded?.maskedEmail = result.json["masked_email"] as? String
        return loaded
    }

    /// Supabase Auth's own refresh. The session (and so its verified state) is the same afterwards.
    func refresh(_ tokens: AuthTokens) async throws -> AuthTokens {
        let result = try await post(path: "/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": tokens.refreshToken], token: nil)
        guard result.status == 200 else { throw result.status >= 500 ? AuthError.unavailable : AuthError.notVerified }
        var json = result.json
        json["user_id"] = (result.json["user"] as? [String: Any])?["id"] as? String ?? tokens.userID
        return try self.tokens(from: json)
    }

    func signOut(tokens: AuthTokens) async {
        _ = try? await post(path: "/auth/v1/logout", body: [:], token: tokens.accessToken)
    }

    // MARK: Plumbing

    private struct Reply {
        var status: Int
        var json: [String: Any]
    }

    private func function(_ name: String, _ body: [String: Any], token: String? = nil) async throws -> Reply {
        try await post(path: "/functions/v1/\(name)", body: body, token: token)
    }

    private func post(path: String, body: [String: Any], token: String?) async throws -> Reply {
        guard let url = URL(string: config.url.absoluteString + path) else { throw AuthError.network }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            NetworkLog.record(method: "POST", path: path, status: status)
            #endif
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            return Reply(status: status, json: json)
        } catch {
            #if DEBUG
            NetworkLog.record(method: "POST", path: path, status: 0)
            #endif
            throw AuthError.network
        }
    }

    private func tokens(from json: [String: Any]) throws -> AuthTokens {
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let user = json["user_id"] as? String else { throw AuthError.server("The server's answer was not understood.") }
        let lifetime = (json["expires_in"] as? Double) ?? (json["expires_in"] as? Int).map(Double.init) ?? 3600
        return AuthTokens(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(lifetime), userID: user)
    }

    private func profile(from json: [String: Any]) -> Profile? {
        guard let name = json["display_name"] as? String else { return nil }
        return Profile(displayName: name, username: json["username"] as? String, school: json["school"] as? String,
                       aboutEmoji: json["about_emoji"] as? String, aboutText: json["about_text"] as? String,
                       hideFromSearch: json["hide_from_search"] as? Bool ?? false)
    }

    /// Turns the server's `{ error, message }` into one of the app's errors.
    private func error(for reply: Reply) -> AuthError {
        let code = reply.json["error"] as? String ?? ""
        let message = reply.json["message"] as? String ?? ""
        switch (reply.status, code) {
        case (401, "invalid_credentials"): return .invalidCredentials
        case (_, "bad_code"): return .badCode(message: message.isEmpty ? "That code isn't right." : message)
        case (_, "locked"): return .locked
        case (_, "too_soon"): return .tooSoon(message: message)
        case (_, "account_exists"): return .accountExists
        case (_, "not_found"): return .notFound
        case (_, "weak_password"): return .weakPassword
        case (_, "username_taken"): return .usernameTaken
        case (_, "bad_username"): return .badUsername(message: message)
        case (429, _): return .rateLimited
        case (_, "email_failed"): return .emailFailed
        case (403, "not_verified"), (401, _): return .notVerified
        case (500...599, _): return .unavailable
        default: return .server(message.isEmpty ? "Something went wrong." : message)
        }
    }
}
