import Foundation
import SwiftUI

/// Profile photos (LIME-98b): mine (public by default, or only for my contacts, encrypted) and other people's, cached on
/// this phone. The bytes and the keys live in LimeCore; this shows them and drives the screens.
extension ConversationStore {
    /// Who may see my photo: `everyone` or `contacts`.
    enum PhotoVisibility: String, Sendable { case everyone, contacts }

    /// My photo and who may see it, as stored on this phone.
    func myPhoto() async -> (jpeg: Data?, visibility: PhotoVisibility) {
        #if DEBUG
        if isDemo { return (demoMyPhoto, demoPhotoVisibility) }
        #endif
        guard let core else { return (nil, .everyone) }
        let mine = try? await Task.detached(priority: .userInitiated) { try core.myPhoto() }.value
        return (mine?.jpeg, PhotoVisibility(rawValue: mine?.visibility ?? "") ?? .everyone)
    }

    /// Saves and uploads my photo (a processed JPEG). `false` when it could not be sent (offline, over the limit).
    func setMyPhoto(_ jpeg: Data) async -> Bool {
        let me = meProvider().id
        #if DEBUG
        if isDemo { demoMyPhoto = jpeg; AvatarCache.shared.set(jpeg, for: me); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.setMyPhoto(transport: link.transport, authToken: token, jpeg: jpeg) }.value
            AvatarCache.shared.set(jpeg, for: me)
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    func removeMyPhoto() async -> Bool {
        let me = meProvider().id
        #if DEBUG
        if isDemo { demoMyPhoto = nil; AvatarCache.shared.set(nil, for: me); return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) { try core.removeMyPhoto(transport: link.transport, authToken: token) }.value
            AvatarCache.shared.set(nil, for: me)
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    func setPhotoVisibility(_ visibility: PhotoVisibility) async -> Bool {
        #if DEBUG
        if isDemo { demoPhotoVisibility = visibility; return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) {
                try core.setPhotoVisibility(transport: link.transport, authToken: token, visibility: visibility.rawValue)
            }.value
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    /// Reads the cached photos of everyone on screen (once each) and my own, into `AvatarCache`.
    func loadCachedPhotos() async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let cache = AvatarCache.shared
        let me = meProvider().id
        let wanted = Set(conversations.flatMap { $0.members.map(\.id) } + conversations.filter(\.isGroupChat).map(\.id) + [me]).subtracting(cache.known)
        guard !wanted.isEmpty else { return }
        let loaded = await Task.detached(priority: .utility) { () -> [String: Data?] in
            var out: [String: Data?] = [:]
            for id in wanted {
                out[id] = id == me ? ((try? core.myPhoto())?.jpeg)
                    : id.hasPrefix("grp:") ? ((try? core.groupPhoto(conversationId: id)) ?? nil)
                    : ((try? core.peerPhoto(userId: id)) ?? nil)
            }
            return out
        }.value
        for (id, data) in loaded { cache.set(data, for: id) }
    }

    /// Pull-to-refresh: the messages, then a photo check for everyone shown (each at most once a minute).
    func pullToRefresh() async {
        await syncNow()
        await refreshPhotos(of: Array(Set(conversations.flatMap { $0.members.map(\.id) })))
    }

    /// Looks for new photos of these people now (not more than once a minute each).
    func refreshPhotos(of ids: [String]) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard !ids.isEmpty, let core, let link, let token = try? await link.token() else { return }
        let changed = (try? await Task.detached(priority: .utility) {
            try core.refreshPhotosOf(transport: link.transport, authToken: token, userIds: ids)
        }.value) ?? []
        guard !changed.isEmpty else { return }
        let loaded = await Task.detached(priority: .utility) { changed.map { ($0, (try? core.peerPhoto(userId: $0)) ?? nil) } }.value
        for (id, data) in loaded { AvatarCache.shared.set(data, for: id) }
    }

    /// Fetches the photos that may have changed (each person at most hourly unless `force`).
    func refreshPhotos(force: Bool = false) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core, let link else { return }
        guard let token = try? await link.token() else { return }
        let changed = (try? await Task.detached(priority: .utility) {
            try core.refreshPhotos(transport: link.transport, authToken: token, force: force)
        }.value) ?? []
        guard !changed.isEmpty else { return }
        let loaded = await Task.detached(priority: .utility) { changed.map { ($0, (try? core.peerPhoto(userId: $0)) ?? nil) } }.value
        for (id, data) in loaded { AvatarCache.shared.set(data, for: id) }
    }
}
