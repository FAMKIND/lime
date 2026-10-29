import Foundation
import UIKit

/// A jam's public picture (LIME-194): set by its writer from Edit jam page, fetched like a profile photo, and shown in the jam's tile everywhere.
/// It is kept in `AvatarCache` under `jam:<id>`; the server and any signed-in teacher can see it, as they can the jam's title.
extension ConversationStore {
    static func jamPictureKey(_ jamID: String) -> String { "jam:\(jamID)" }

    /// How long a look at the server is trusted before the next one.
    private static let jamPictureRecheck: TimeInterval = 10 * 60

    /// Shows what this phone holds for the jam at once, then (at most every ten minutes) looks at the server for a new, changed or removed picture.
    func ensureJamPicture(_ jamID: String) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core, let link else { return }
        let key = Self.jamPictureKey(jamID)
        if !AvatarCache.shared.known.contains(key) {
            let held = await Task.detached(priority: .utility) { (try? core.jamPicture(jamId: jamID)) ?? nil }.value
            AvatarCache.shared.set(held, for: key)
        }
        if let last = jamPictureChecked[jamID], Date().timeIntervalSince(last) < Self.jamPictureRecheck { return }
        jamPictureChecked[jamID] = Date()
        guard let token = try? await link.token() else { jamPictureChecked[jamID] = nil; return }
        let changed = await Task.detached(priority: .utility) { try? core.refreshJamPicture(transport: link.transport, authToken: token, jamId: jamID) }.value
        if changed == nil { jamPictureChecked[jamID] = nil; return }
        if changed == true {
            let held = await Task.detached(priority: .utility) { (try? core.jamPicture(jamId: jamID)) ?? nil }.value
            AvatarCache.shared.set(held, for: key)
        }
    }

    /// Puts a picture (an already cropped 512 px JPEG) on my jam's page.
    func setJamPicture(_ jamID: String, jpeg: Data) async -> Bool {
        let key = Self.jamPictureKey(jamID)
        #if DEBUG
        if isDemo { AvatarCache.shared.set(jpeg, for: key); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.setJamPicture(transport: link.transport, authToken: token, jamId: jamID, jpeg: jpeg) }.value
            AvatarCache.shared.set(jpeg, for: key)
            jamPictureChecked[jamID] = Date()
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    /// Takes the picture off my jam's page; the first letter comes back.
    func removeJamPicture(_ jamID: String) async -> Bool {
        let key = Self.jamPictureKey(jamID)
        #if DEBUG
        if isDemo { AvatarCache.shared.set(nil, for: key); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.removeJamPicture(transport: link.transport, authToken: token, jamId: jamID) }.value
            AvatarCache.shared.set(nil, for: key)
            jamPictureChecked[jamID] = Date()
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }
}
