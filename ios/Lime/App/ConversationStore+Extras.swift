import Foundation

/// A profile's links and background image (LIME-214, LIME-217): the photo's scheme again. Mine are stored on this phone and mirrored to the server as
/// Everyone's (a public copy) or contacts-only (ciphertext); other people's are fetched with their photo. The bytes and keys live in LimeCore.
extension ConversationStore {
    enum ExtraSlot: String, Sendable { case links, background }

    /// What I hold for a slot, and who may see it (contacts only until I choose).
    func myExtra(_ slot: ExtraSlot) async -> (data: Data?, visibility: PhotoVisibility) {
        #if DEBUG
        if isDemo { return (demoExtras[slot.rawValue], PhotoVisibility(rawValue: demoExtraVisibility[slot.rawValue] ?? "") ?? .contacts) }
        #endif
        guard let core else { return (nil, .contacts) }
        let mine = try? await Task.detached(priority: .userInitiated) { try core.myExtra(slot: slot.rawValue) }.value
        return (mine?.data, PhotoVisibility(rawValue: mine?.visibility ?? "") ?? .contacts)
    }

    /// Saves and uploads a slot. `false` when it could not be sent.
    func setMyExtra(_ slot: ExtraSlot, _ data: Data?) async -> Bool {
        #if DEBUG
        if isDemo { demoExtras[slot.rawValue] = data; extrasVersion += 1; return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) {
                if let data { try core.setMyExtra(transport: link.transport, authToken: token, slot: slot.rawValue, data: data) }
                else { try core.removeMyExtra(transport: link.transport, authToken: token, slot: slot.rawValue) }
            }.value
            extrasVersion += 1
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    func setExtraVisibility(_ slot: ExtraSlot, _ visibility: PhotoVisibility) async -> Bool {
        #if DEBUG
        if isDemo { demoExtraVisibility[slot.rawValue] = visibility.rawValue; extrasVersion += 1; return true }
        #endif
        guard let core, let link else { return false }
        do {
            let token = try await link.token()
            try await Task.detached(priority: .userInitiated) {
                try core.setExtraVisibility(transport: link.transport, authToken: token, slot: slot.rawValue, visibility: visibility.rawValue)
            }.value
            extrasVersion += 1
            return true
        } catch {
            report(ConnectionProblem.from(error))
            return false
        }
    }

    /// Another person's links or background as this phone holds it, after a look for a newer one (at most once a minute each).
    func peerExtra(_ userID: String, _ slot: ExtraSlot) async -> Data? {
        if userID == meProvider().id { return await myExtra(slot).data }
        #if DEBUG
        if isDemo { return demoPeerExtra(userID, slot) }
        #endif
        guard let core else { return nil }
        await refreshPhotos(of: [userID])
        return (try? await Task.detached(priority: .userInitiated) { try core.peerExtra(userId: userID, slot: slot.rawValue) }.value) ?? nil
    }

    #if DEBUG
    /// Demo: Sam's links are contacts-only, so they show only while he is one of my contacts.
    private func demoPeerExtra(_ userID: String, _ slot: ExtraSlot) -> Data? {
        guard userID == "sam", let chat = conversation("dm:sam"), !chat.isRequest else { return nil }
        if slot == .background { return ProfilePhotoScreen.demoPicture.jpegData(compressionQuality: 0.6) }
        return ProfileLinks.encode([ProfileLink(title: "Fractions that stick", url: "https://example.com/fractions"), ProfileLink(title: "My class blog", url: "https://example.org/blog")])
    }
    #endif
}
