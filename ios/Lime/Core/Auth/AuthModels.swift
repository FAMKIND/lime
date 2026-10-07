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
    /// The About line: an optional leading emoji, then a few words (140 characters in all).
    var aboutEmoji: String?
    var aboutText: String?
    /// "Hide me from search": nobody finds you by username or email.
    var hideFromSearch: Bool = false
    /// Your own address, masked ("s•••@famkind.com"), for the Account screen. Not editable.
    var maskedEmail: String?

    static let maxNameLength = 40
    static let maxAboutLength = 140

    /// The About line as one string for a list or a card ("👋 Happy to help"), or nil when empty.
    var about: String? {
        let parts = [aboutEmoji, aboutText].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

struct ProfileDraft: Equatable, Sendable {
    var displayName: String
    var username: String?
    var school: String?
    var aboutEmoji: String?
    var aboutText: String?
    var hideFromSearch: Bool?

    init(displayName: String, username: String? = nil, school: String? = nil, aboutEmoji: String? = nil,
         aboutText: String? = nil, hideFromSearch: Bool? = nil) {
        self.displayName = displayName
        self.username = username
        self.school = school
        self.aboutEmoji = aboutEmoji
        self.aboutText = aboutText
        self.hideFromSearch = hideFromSearch
    }

    /// Every editable field as it is now: an editor changes one and sends all (the server replaces the profile).
    init(_ profile: Profile) {
        self.init(displayName: profile.displayName, username: profile.username, school: profile.school,
                  aboutEmoji: profile.aboutEmoji, aboutText: profile.aboutText, hideFromSearch: profile.hideFromSearch)
    }
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
    /// The server answered with a 5xx: it, not the phone's connection, is the problem.
    case unavailable
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
        case .unavailable: "Lime's server had a problem. Try again in a moment."
        case .notVerified: "Finish signing in first."
        case .server(let message): message
        }
    }
}
