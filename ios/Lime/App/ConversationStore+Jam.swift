import Foundation
import SwiftUI

/// jam (LIME-188): a teacher's one-author encrypted channel. The core does the cryptography, the queues and the downloads (`docs/jam.md`); this is the
/// glue the screens use. Nothing here shows a count to anyone but the writer.
extension ConversationStore {
    // MARK: Reading what the core has

    /// Re-reads the jams and their posts from the core (cheap; called after every sync and delivery). A post whose content has not been downloaded
    /// yet makes a quiet delivery pass run (at most every 15 seconds), which is where the downloads happen.
    func refreshJams() {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        let mine = (try? core.listMyJams()) ?? []
        let followed = (try? core.listJamSubscriptions()) ?? []
        var posts: [String: [JamPostInfo]] = [:]
        var progress: [String: JamSendProgress] = [:]
        for jam in mine + followed {
            posts[jam.jamId] = (try? core.listJamPosts(jamId: jam.jamId)) ?? []
            if jam.mine, let p = try? core.jamSendProgress(jamId: jam.jamId), p.pending > 0 { progress[jam.jamId] = p }
        }
        if mine != jamsMine { jamsMine = mine }
        if followed != jamSubscriptions { jamSubscriptions = followed }
        if posts != jamPosts { jamPosts = posts }
        if progress != jamProgress { jamProgress = progress }
        let waiting = posts.values.joined().contains { $0.state == "fetching" } || !progress.isEmpty
        if waiting, link != nil, Date().timeIntervalSince(jamLastKick) > 15 {
            jamLastKick = Date()
            Task { await deliverNow() }
        }
    }

    /// The name this phone shows for a teacher: a chat member, a profile it has seen, else a plain word.
    func teacherName(_ userID: String) -> String {
        if userID == meProvider().id { return meProvider().name }
        for conversation in conversations { if let member = conversation.members.first(where: { $0.id == userID }) { return member.name } }
        if let name = publicProfiles[userID]?.displayName, !name.isEmpty { return name }
        return "A teacher"
    }

    func teacher(_ userID: String) -> Person {
        if userID == meProvider().id { return meProvider() }
        for conversation in conversations { if let member = conversation.members.first(where: { $0.id == userID }) { return member } }
        return Person(id: userID, name: teacherName(userID))
    }

    /// The feed: the posts of every jam I follow and my own, newest first.
    var jamFeed: [JamPostInfo] {
        let live = Set(jamSubscriptions.filter { $0.status == "active" }.map(\.jamId) + jamsMine.map(\.jamId))
        return jamPosts.filter { live.contains($0.key) }.values.flatMap { $0 }.sorted { $0.created > $1.created }
    }

    /// The posts of one writer's jam, newest first (mine, or one I follow).
    func posts(of jamID: String) -> [JamPostInfo] { (jamPosts[jamID] ?? []).sorted { $0.created > $1.created } }

    func jamPost(_ postID: String) -> JamPostInfo? {
        for posts in jamPosts.values { if let post = posts.first(where: { $0.postId == postID }) { return post } }
        return nil
    }

    func jamTitle(_ jamID: String) -> String { (jamsMine + jamSubscriptions).first { $0.jamId == jamID }?.title ?? "jam" }

    /// Whether I follow this jam (asked, or accepted).
    func isFollowing(_ jamID: String) -> Bool {
        jamSubscriptions.contains { $0.jamId == jamID && ["active", "requested"].contains($0.status) }
    }

    // MARK: My jam

    /// My jam, made on my first post: named for me, with my profile's about line; edited later from my profile.
    func myJamID(about: String) async -> String? {
        if let jam = jamsMine.first { return jam.jamId }
        #if DEBUG
        if isDemo { demoStartJam(title: meProvider().name, about: about, topics: []); return jamsMine.first?.jamId }
        #endif
        guard let core else { return nil }
        let name = String(meProvider().name.prefix(60))
        _ = try? await Task.detached { try core.createJam(title: name.isEmpty ? "My jam" : name, about: String(about.prefix(500)), topics: []) }.value
        refreshJams()
        return jamsMine.first?.jamId
    }

    @discardableResult
    func editJam(_ jamID: String, title: String, about: String, topics: [String]) async -> Bool {
        #if DEBUG
        if isDemo { demoEditJam(jamID, title: title, about: about, topics: topics); return true }
        #endif
        guard let core else { return false }
        let ok = (try? await Task.detached { try core.updateJam(jamId: jamID, title: title, about: about, topics: topics) }.value) != nil
        refreshJams()
        if ok { await deliverNow() }
        return ok
    }

    func endJam(_ jamID: String) async {
        #if DEBUG
        if isDemo { jamsMine.removeAll { $0.jamId == jamID }; return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.endJam(jamId: jamID) }.value
        refreshJams()
        await deliverNow()
    }

    /// Publishes a post (a quick post, an article or a recording) to my jam, making the jam first if this is my first post: the core seals it, and
    /// the next delivery sends it. Every post is free (payments are off).
    @discardableResult
    func publishJamPost(kind: String, title: String, subtitle: String, markdown: String, items: [OutgoingAttachment], about: String) async -> Bool {
        guard let jamID = await myJamID(about: about) else { return false }
        #if DEBUG
        if isDemo { demoPublish(jamID, kind: kind, title: title, subtitle: subtitle, markdown: markdown, items: items); return true }
        #endif
        guard let core else { return false }
        guard StorageGuard.shared.allows(items.reduce(0) { $0 + Int64($1.bytes.count) }) else {
            lowStorage = true
            showBanner("Not enough space on your iPhone to send this.")
            return false
        }
        let ok = (try? await Task.detached(priority: .userInitiated) {
            try core.publishJamPost(jamId: jamID, kind: kind, title: title, subtitle: subtitle, markdown: markdown, tier: "free", attachments: items)
        }.value) != nil
        refreshJams()
        if ok { await deliverNow() }
        return ok
    }

    func loadJamSubscribers(_ jamID: String) {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core else { return }
        jamSubscribers[jamID] = (try? core.listJamSubscribers(jamId: jamID)) ?? []
    }

    func removeJamSubscriber(_ jamID: String, user: String) async {
        #if DEBUG
        if isDemo { jamSubscribers[jamID]?.removeAll { $0.userId == user }; return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.removeJamSubscriber(jamId: jamID, userId: user) }.value
        loadJamSubscribers(jamID)
        refreshJams()
        await deliverNow()
    }

    // MARK: Following

    /// A teacher's live jam page, if they have one (the server learns that this account looked, as it does for a profile).
    func jamPage(of userID: String) async -> JamPageInfo? {
        #if DEBUG
        if isDemo { return demoJamPages[userID] }
        #endif
        guard let core, let link else { return nil }
        guard let token = try? await link.token() else { return nil }
        let page = try? await Task.detached { try core.fetchJamPage(transport: link.transport, authToken: token, writerUserId: userID) }.value
        return page ?? nil
    }

    func subscribe(to page: JamPageInfo) async {
        #if DEBUG
        if isDemo { demoSubscribe(page); return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.subscribeToJam(jamId: page.jamId, writerUserId: page.writerId) }.value
        refreshJams()
        await deliverNow()
    }

    func unsubscribe(_ jamID: String) async {
        #if DEBUG
        if isDemo { jamSubscriptions.removeAll { $0.jamId == jamID }; jamPosts[jamID] = nil; return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.unsubscribeFromJam(jamId: jamID) }.value
        refreshJams()
        await deliverNow()
    }

    // MARK: A post's files

    func jamAttachments(_ postID: String) -> [JamAttachmentInfo] {
        #if DEBUG
        if isDemo { return demoJamAttachments[postID] ?? [] }
        #endif
        return (try? core?.listJamAttachments(postId: postID)) ?? []
    }

    /// A file's bytes: what the phone has, else downloaded now with no session.
    func jamAttachmentData(_ postID: String, _ attachmentID: String) async -> Data? {
        #if DEBUG
        if isDemo { return demoJamImage(attachmentID) }
        #endif
        guard let core, let link else { return nil }
        let bytes = try? await Task.detached(priority: .userInitiated) { try core.jamAttachmentData(transport: link.transport, postId: postID, attachmentId: attachmentID) }.value
        return bytes
    }
}
