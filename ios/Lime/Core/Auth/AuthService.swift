import Foundation

/// Signing up and in. The server is the authority (a password and an emailed code are both checked
/// by its functions); this is the app's side of it. `LiveAuthService` talks to the backend; a fake
/// stands in for tests and screenshots.
protocol AuthService: Sendable {
    /// The first screen's question: an email (new or existing) or a username.
    func identify(_ identifier: String) async throws -> IdentifyResult

    // Sign in: a password, then an emailed code.
    func signIn(identifier: String, password: String) async throws -> PasswordSignIn
    func verifySignInCode(_ code: String, tokens: AuthTokens) async throws
    func resendSignInCode(tokens: AuthTokens) async throws

    // Sign up: an emailed code, then a password, then a profile.
    func startSignUp(email: String) async throws
    func verifySignUpCode(email: String, code: String) async throws -> AuthTokens
    /// Sets the password; returns a fresh session that has passed both steps (the old one ends).
    func setInitialPassword(_ password: String, tokens: AuthTokens) async throws -> AuthTokens

    // Forgot password: an emailed code and a new password.
    func startReset(identifier: String) async throws
    func finishReset(identifier: String, code: String, newPassword: String) async throws -> AuthTokens

    func saveProfile(_ draft: ProfileDraft, tokens: AuthTokens) async throws -> Profile
    func loadProfile(tokens: AuthTokens) async throws -> Profile?

    func refresh(_ tokens: AuthTokens) async throws -> AuthTokens
    func signOut(tokens: AuthTokens) async
}
