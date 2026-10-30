import Foundation
import UIKit

/// A band's colour and cover (LIME-258): set by its owner from the page's Edit Cover, public with the page like its name and picture. The cover is kept in
/// `AvatarCache` under `jam-cover:<id>`, the colour in `jamTones`; with no colour chosen a band's is worked out from its id, as a person's avatar colour is.
extension ConversationStore {
    static func jamCoverKey(_ jamID: String) -> String { "jam-cover:\(jamID)" }

    private static let jamStyleRecheck: TimeInterval = 10 * 60

    /// The band's colour: the one chosen, else one from its id.
    func jamTone(_ jamID: String) -> Int { jamTones[jamID] ?? AvatarTone.tone(for: jamID) }

    /// Shows what this phone holds at once, then (at most every ten minutes) looks at the server for a new, changed or removed colour or cover.
    func ensureJamStyle(_ jamID: String) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core, let link else { return }
        let key = Self.jamCoverKey(jamID)
        if !AvatarCache.shared.known.contains(key) { await loadHeldJamStyle(jamID, core: core) }
        if let last = jamStyleChecked[jamID], Date().timeIntervalSince(last) < Self.jamStyleRecheck { return }
        jamStyleChecked[jamID] = Date()
        guard let token = try? await link.token() else { jamStyleChecked[jamID] = nil; return }
        let changed = await Task.detached(priority: .utility) { try? core.refreshJamStyle(transport: link.transport, authToken: token, jamId: jamID) }.value
        if changed == nil { jamStyleChecked[jamID] = nil; return }
        if changed == true { await loadHeldJamStyle(jamID, core: core) }
    }

    private func loadHeldJamStyle(_ jamID: String, core: LimeStore) async {
        let (tone, cover) = await Task.detached(priority: .utility) { ((try? core.jamTone(jamId: jamID)) ?? nil, (try? core.jamCover(jamId: jamID)) ?? nil) }.value
        jamTones[jamID] = tone.map { Int($0) }
        AvatarCache.shared.set(cover, for: Self.jamCoverKey(jamID))
    }

    /// Sets my band's colour; nil brings the default back.
    @discardableResult
    func setJamTone(_ jamID: String, tone: Int?) async -> Bool {
        #if DEBUG
        if isDemo { jamTones[jamID] = tone; return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.setJamTone(transport: link.transport, authToken: token, jamId: jamID, tone: tone.map { Int64($0) }) }.value
            jamTones[jamID] = tone
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    /// Puts a cover (an already framed 4:5 JPEG) on my band's page.
    @discardableResult
    func setJamCover(_ jamID: String, jpeg: Data) async -> Bool {
        let key = Self.jamCoverKey(jamID)
        #if DEBUG
        if isDemo { AvatarCache.shared.set(jpeg, for: key); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.setJamCover(transport: link.transport, authToken: token, jamId: jamID, jpeg: jpeg) }.value
            AvatarCache.shared.set(jpeg, for: key)
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    /// Takes the cover off my band's page; the colour's gradient comes back.
    @discardableResult
    func removeJamCover(_ jamID: String) async -> Bool {
        let key = Self.jamCoverKey(jamID)
        #if DEBUG
        if isDemo { AvatarCache.shared.set(nil, for: key); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.removeJamCover(transport: link.transport, authToken: token, jamId: jamID) }.value
            AvatarCache.shared.set(nil, for: key)
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }
}
