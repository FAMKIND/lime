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

/// The offline banner on Messages and what it promises (LIME-142). Pure words, so they are tested. The mesh promise is the honest one from the
/// Bluetooth spike: delivery when phones meet and at least one is awake; nothing after lime is swiped away.
enum OfflineCopy {
    static let withMesh = "Offline \u{00B7} sending through nearby phones"
    static let withoutMesh = "Offline \u{00B7} will send when you\u{2019}re online"

    static func banner(meshOn: Bool) -> String { meshOn ? withMesh : withoutMesh }

    static let sheetTitle = "No internet"
    /// The whole first screen: one short paragraph. The honest limits are behind "Learn more".
    static let sheetBody = "Messages hop phone to phone, sealed. They go when phones meet or anyone gets online. Photos wait for internet."
    static let learnMore = "Learn more"
    /// Behind "Learn more": the honest promise and its limits.
    static let promise = [
        "Messages you write while offline stay sealed on your phone. If other phones running lime are nearby, lime passes them along; those phones can\u{2019}t read them.",
        "A message moves when phones meet and at least one of them is awake. It does not move if lime has been swiped away. When any phone carrying it, or yours, reaches the internet, it goes through.",
        "Pictures, files and messages to people who haven\u{2019}t accepted you yet wait for the internet.",
    ]
}
