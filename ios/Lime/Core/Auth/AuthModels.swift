import Foundation

/// The tokens of a signed-in session. They live in the Keychain, this device only.
struct AuthTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String

    /// Refresh a little early so a call never goes out with a token about to expire.
    func isExpiring(at now: Date = Date(), margin: TimeInterval = 120) -> Bool {
        expiresAt.timeIntervalSince(now) < margin
    }
}

/// What the first screen's one question turned out to be.
enum IdentifyResult: Equatable, Sendable {
    case existingEmail
    case newEmail
    /// A username with an account; `hint` is the masked email the code goes to ("s•••@famkind.com").
    case existingUsername(hint: String)
    case unknownUsername
}

/// The result of the password step of signing in: the session (which can do nothing until the code is
/// verified) and where the code was sent.
struct PasswordSignIn: Equatable, Sendable {
    var tokens: AuthTokens
    var maskedEmail: String
}

struct Profile: Equatable, Sendable {
    var displayName: String
    var username: String?
    var school: String?
}

struct ProfileDraft: Equatable, Sendable {
    var displayName: String
    var username: String?
    var school: String?
}

/// Everything that can go wrong, in the words the screens show.
enum AuthError: Error, Equatable, Sendable {
    case invalidCredentials
    case badCode(message: String)
    case locked
    case tooSoon(message: String)
    case accountExists
    case notFound
    case weakPassword
    case usernameTaken
    case badUsername(message: String)
    case rateLimited
    case emailFailed
    case network
    case notVerified
    case server(String)

    var message: String {
        switch self {
        case .invalidCredentials: "That email, username or password isn't right."
        case .badCode(let message): message
        case .locked: "Too many wrong codes. Go back and start again to get a new one."
        case .tooSoon(let message): message
        case .accountExists: "That email already has an account. Sign in instead."
        case .notFound: "No account with that username."
        case .weakPassword: "Use at least 10 characters."
        case .usernameTaken: "That username is taken. Try another."
        case .badUsername(let message): message
        case .rateLimited: "Too many tries. Wait a moment and try again."
        case .emailFailed: "We couldn't send the code. Try again in a moment."
        case .network: "Couldn't reach Lime. Check your connection and try again."
        case .notVerified: "Finish signing in first."
        case .server(let message): message
        }
    }
}
