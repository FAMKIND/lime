import Foundation

/// Why talking to the backend failed, in words that are true. "Check your connection" is for a real
/// connection failure only; an ended session, a rate limit and a server fault each say so.
enum ConnectionProblem: Equatable, Sendable {
    case sessionEnded
    case offline
    case busy
    case server
    case other

    var message: String {
        switch self {
        case .sessionEnded: "Your session has ended. Please sign in again."
        case .offline: "You're offline. Check your connection and try again."
        case .busy: "Too many requests. Wait a minute and try again."
        case .server: "Lime's server had a problem. Try again in a moment."
        case .other: "Something went wrong. Try again."
        }
    }

    /// Only an ended session needs the person to do something (sign in again).
    var needsSignIn: Bool { self == .sessionEnded }

    static func from(_ error: Error) -> ConnectionProblem {
        switch error {
        case StoreError.Unauthorized: .sessionEnded
        case StoreError.Network: .offline
        case StoreError.RateLimited: .busy
        case StoreError.Unavailable: .server
        case let auth as AuthError:
            switch auth {
            case .notVerified: .sessionEnded
            case .network: .offline
            case .rateLimited, .tooSoon: .busy
            case .unavailable: .server
            default: .other
            }
        default: .other
        }
    }
}
