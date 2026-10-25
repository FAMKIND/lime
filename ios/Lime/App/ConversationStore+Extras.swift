import Foundation

/// A profile's links and background image (LIME-214, LIME-217): the photo's scheme again. Mine are stored on this phone and mirrored to the server as
/// Everyone's (a public copy) or contacts-only (ciphertext); other people's are fetched with their photo. The bytes and keys live in LimeCore.
extension ConversationStore {
    enum ExtraSlot: String, Sendable { case links, background, backgroundVideo = "background_video" }

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
        if isDemo {
            demoExtras[slot.rawValue] = data
            if slot == .background, data == nil { demoExtras[ExtraSlot.backgroundVideo.rawValue] = nil }   // no video without its still
            extrasVersion += 1; return true
        }
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
        if isDemo { return await demoPeerExtra(userID, slot) }
        #endif
        guard let core else { return nil }
        // A background video is only downloaded on Wi-Fi (not on cellular or in Low Data Mode); then the profile offers a tap (LIME-226b).
        core.setBackgroundVideoFetching(allowed: VideoFetchPolicy.shared.allowed)
        await refreshPhotos(of: [userID])
        return (try? await Task.detached(priority: .userInitiated) { try core.peerExtra(userId: userID, slot: slot.rawValue) }.value) ?? nil
    }

    /// True when someone's background video is known but was not downloaded (cellular, Low Data Mode).
    func peerExtraPending(_ userID: String, _ slot: ExtraSlot) async -> Bool {
        #if DEBUG
        if isDemo { return ProcessInfo.processInfo.arguments.contains("-lime-demo-video-pending") && userID == "sam" && slot == .backgroundVideo && !demoFetchedPending }
        #endif
        guard let core, userID != meProvider().id else { return false }
        return (try? await Task.detached { try core.peerExtraPending(userId: userID, slot: slot.rawValue) }.value) ?? false
    }

    /// The person tapped "Play background": download it now, whatever the network.
    func fetchPeerExtra(_ userID: String, _ slot: ExtraSlot) async {
        #if DEBUG
        if isDemo { demoFetchedPending = true; extrasVersion += 1; return }
        #endif
        guard let core, let link, let token = try? await link.token() else { return }
        _ = try? await Task.detached(priority: .userInitiated) { try core.fetchPeerExtra(transport: link.transport, authToken: token, userId: userID, slot: slot.rawValue) }.value
        extrasVersion += 1
    }

    #if DEBUG
    /// Demo: Sam's links are contacts-only, so they show only while he is one of my contacts.
    private func demoPeerExtra(_ userID: String, _ slot: ExtraSlot) async -> Data? {
        guard userID == "sam", let chat = conversation("dm:sam"), !chat.isRequest else { return nil }
        if slot == .background { return ProfilePhotoScreen.demoPicture.jpegData(compressionQuality: 0.6) }
        if slot == .backgroundVideo {
            // Sam has a short clip behind his name only with `-lime-demo-video` (with `-lime-demo-video-pending` it also waits for a tap first).
            let args = ProcessInfo.processInfo.arguments
            guard args.contains("-lime-demo-video") || args.contains("-lime-demo-video-pending") else { return nil }
            if args.contains("-lime-demo-video-pending") && !demoFetchedPending { return nil }
            return await DemoClip.data()
        }
        return ProfileLinks.encode([ProfileLink(title: "Fractions that stick", url: "https://example.com/fractions"), ProfileLink(title: "My class blog", url: "https://example.org/blog")])
    }
    #endif
}
