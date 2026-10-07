#if DEBUG
import Foundation

/// A stand-in backend for UI tests, screenshots and previews (launch with `-lime-fake-auth`). It
/// needs no network: any email starting with "new" is a new account, any other email or any username
/// of 3 or more characters except "nobody" is an existing one, the code is `123456`, and the password
/// is `correct horse battery`.
actor FakeAuthService: AuthService {
    static let code = "123456"
    static let password = "correct horse battery"

    private var attempts = 0
    private var profile: Profile?

    private func tokens(_ user: String = "fake-user") -> AuthTokens {
        AuthTokens(accessToken: "fake-access", refreshToken: "fake-refresh", expiresAt: Date().addingTimeInterval(3600), userID: user)
    }

    func identify(_ identifier: String) async throws -> IdentifyResult {
        let value = identifier.trimmingCharacters(in: .whitespaces)
        if value.contains("@") && !value.hasPrefix("@") {
            return value.lowercased().hasPrefix("new") ? .newEmail : .existingEmail
        }
        let username = value.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if username.lowercased() == "nobody" || username.count < 3 { return .unknownUsername }
        return .existingUsername(hint: "\(username.prefix(1))•••@famkind.com")
    }

    func signIn(identifier: String, password: String) async throws -> PasswordSignIn {
        guard password == Self.password else { throw AuthError.invalidCredentials }
        attempts = 0
        return PasswordSignIn(tokens: tokens(), maskedEmail: "s•••@famkind.com")
    }

    func verifySignInCode(_ code: String, tokens: AuthTokens) async throws {
        try check(code)
    }

    func resendSignInCode(tokens: AuthTokens) async throws { attempts = 0 }

    func startSignUp(email: String) async throws { attempts = 0 }

    func verifySignUpCode(email: String, code: String) async throws -> AuthTokens {
        try check(code)
        return tokens("new-user")
    }

    func setInitialPassword(_ password: String, tokens: AuthTokens) async throws -> AuthTokens {
        guard password.count >= 10 else { throw AuthError.weakPassword }
        return self.tokens("new-user")
    }

    func startReset(identifier: String) async throws { attempts = 0 }

    func finishReset(identifier: String, code: String, newPassword: String) async throws -> AuthTokens {
        try check(code)
        guard newPassword.count >= 10 else { throw AuthError.weakPassword }
        return tokens()
    }

    func startPasswordChange(current: String, tokens: AuthTokens) async throws {
        guard current == Self.password else { throw AuthError.invalidCredentials }
        attempts = 0
    }

    func finishPasswordChange(code: String, newPassword: String, tokens: AuthTokens) async throws -> AuthTokens {
        try check(code)
        guard newPassword.count >= 10 else { throw AuthError.weakPassword }
        return tokens
    }

    func saveProfile(_ draft: ProfileDraft, tokens: AuthTokens) async throws -> Profile {
        if draft.username?.lowercased() == "taken" { throw AuthError.usernameTaken }
        let saved = Profile(displayName: draft.displayName, username: draft.username, school: draft.school,
                            aboutEmoji: draft.aboutEmoji, aboutText: draft.aboutText, hideFromSearch: draft.hideFromSearch ?? false,
                            maskedEmail: "t•••@example.invalid")
        profile = saved
        return saved
    }

    func loadProfile(tokens: AuthTokens) async throws -> Profile? {
        profile ?? (tokens.userID == "new-user" ? nil : Profile(displayName: "Test Teacher", username: "teacher", school: nil, maskedEmail: "t•••@example.invalid"))
    }

    func refresh(_ tokens: AuthTokens) async throws -> AuthTokens { tokens }
    func signOut(tokens: AuthTokens) async {}

    private func check(_ code: String) throws {
        attempts += 1
        if attempts > 5 { throw AuthError.locked }
        guard code == Self.code else {
            throw AuthError.badCode(message: "That code isn't right. \(5 - attempts) tries left.")
        }
    }
}
#endif
