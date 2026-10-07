import Foundation
import os

#if DEBUG
/// Debug builds only: every request's method, path (no query, no body, no headers) and HTTP status,
/// so "Couldn't search" can be told apart from a 401, a 429 or a 5xx in Console.app / Xcode.
/// Tokens, keys and message content never go through here. Status 0 means no response arrived.
enum NetworkLog {
    private static let logger = Logger(subsystem: "app.lime", category: "network")

    static func record(method: String, path: String, status: Int) {
        let clean = path.split(separator: "?").first.map(String.init) ?? path
        logger.notice("\(method, privacy: .public) \(clean, privacy: .public) -> \(status, privacy: .public)")
    }
}
#endif
