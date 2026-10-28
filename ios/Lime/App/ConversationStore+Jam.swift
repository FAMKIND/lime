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
        let requests = (try? core.listCoauthorRequests()) ?? []
        let credited = (try? core.listCoauthoredPosts()) ?? []
        if requests != jamRequests { jamRequests = requests }
        if credited != coauthoredPosts { coauthoredPosts = credited }
        if mine != jamsMine { jamsMine = mine }
        if followed != jamSubscriptions { jamSubscriptions = followed }
        if posts != jamPosts { jamPosts = posts }
        jamEngagement += 1
        if progress != jamProgress { jamProgress = progress }
        let waiting = posts.values.joined().contains { $0.state == "fetching" } || credited.contains { $0.state == "fetching" } || !progress.isEmpty
        if waiting, link != nil, Date().timeIntervalSince(jamLastKick) > 15 {
            jamLastKick = Date()
            Task { await deliverNow() }
        }
    }

    /// The name this phone shows for a teacher: a chat member, a profile it has seen, else a plain word.
    /// Who a post is shown as written by (LIME-201): the jam's title when it was posted as the jam, else its writer. One rule for every card, player,
    /// the lock screen and the share text.
    func authorName(_ post: JamPostInfo?) -> String {
        guard let post else { return "" }
        return post.displayAs == "jam" ? jamTitle(post.jamId) : teacherName(post.author)
    }

    /// The jam's title when the post is shown as the jam (for the tile in place of a face), else nil.
    func orgName(_ post: JamPostInfo?) -> String? { post?.displayAs == "jam" ? jamTitle(post?.jamId ?? "") : nil }

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
        let hidden = hiddenJamPosts
        return jamPosts.filter { live.contains($0.key) }.values.flatMap { $0 }.filter { !hidden.contains($0.postId) }.sorted { $0.created > $1.created }
    }

    /// Posts hidden from my feed on this phone (never sent anywhere).
    var hiddenJamPosts: Set<String> {
        #if DEBUG
        if isDemo { return Self.demoHidden }   // the demo's posts have fixed ids: never remembered between runs
        #endif
        return Set(UserDefaults.standard.stringArray(forKey: VideoPrefs.hiddenKey) ?? [])
    }

    #if DEBUG
    nonisolated(unsafe) static var demoHidden: Set<String> = []
    #endif

    func hideJamPost(_ postID: String) {
        var now = hiddenJamPosts
        now.insert(postID)
        #if DEBUG
        if isDemo { Self.demoHidden = now } else { UserDefaults.standard.set(Array(now), forKey: VideoPrefs.hiddenKey) }
        #else
        UserDefaults.standard.set(Array(now), forKey: VideoPrefs.hiddenKey)
        #endif
        jamHiddenChanged += 1
        showBanner("Post hidden")
    }

    func unhideJamPosts() {
        UserDefaults.standard.removeObject(forKey: VideoPrefs.hiddenKey)
        jamHiddenChanged += 1
    }

    /// "with Jean Chung and Lee Wong" for the co-authors who accepted, or nil.
    func byline(_ post: JamPostInfo) -> String? {
        let names = post.coauthors.map { teacherName($0) }
        switch names.count {
        case 0: return nil
        case 1: return "with \(names[0])"
        default: return "with \(names.dropLast().joined(separator: ", ")) and \(names.last ?? "")"
        }
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

    /// Why a post did not go: said in words the writer can act on, in the compose screen (a banner would sit behind it).
    /// The most one jam file can be (24 MiB), inside the 25 MiB a blob may hold.
    static let jamFileLimit = 24 * 1024 * 1024

    enum JamPostFailure: Error, Equatable {
        case noSpace, tooManyFiles, fileTooLarge, rejected, couldNotMake
        var message: String {
            switch self {
            case .noSpace: "Not enough space on your iPhone for these photos."
            case .tooManyFiles: "A post can have up to 10 photos and files."
            case .fileTooLarge: "A photo or file is too large for a post (24 MB each)."
            case .rejected: "Something in this post isn\u{2019}t allowed. Check the title and subtitle lengths."
            case .couldNotMake: "Couldn\u{2019}t make your jam. Try again."
            }
        }
    }

    /// Publishes a post (a quick post, an article or a recording) to my jam, making the jam first if this is my first post: the core seals it, and
    /// the next delivery sends it. Every post is free (payments are off). The photos go up afterwards in the background, each on its own and retried
    /// by itself; nothing here waits for the network.
    func publishJamPost(kind: String, title: String, subtitle: String, markdown: String, items: [OutgoingAttachment], coauthors: [String] = [], displayAs: String = "person", audience: String = "subscribers", about: String) async -> Result<Void, JamPostFailure> {
        guard items.count <= 10 else { return .failure(.tooManyFiles) }
        guard items.allSatisfy({ $0.bytes.count <= Self.jamFileLimit }) else { return .failure(.fileTooLarge) }
        guard let jamID = await myJamID(about: about) else { return .failure(.couldNotMake) }
        #if DEBUG
        if isDemo { demoPublish(jamID, kind: kind, title: title, subtitle: subtitle, markdown: markdown, items: items, coauthors: coauthors, displayAs: displayAs, audience: audience); return .success(()) }
        #endif
        guard let core else { return .failure(.couldNotMake) }
        guard StorageGuard.shared.allows(items.reduce(0) { $0 + Int64($1.bytes.count) }) else { return .failure(.noSpace) }
        do {
            lastPublishedPostID = try await Task.detached(priority: .userInitiated) {
                try core.publishJamPostWith(jamId: jamID, kind: kind, title: title, subtitle: subtitle, markdown: markdown, tier: "free", attachments: items, coauthors: coauthors, displayAs: displayAs, options: PostOptions(audience: audience, series: nil))
            }.value
        } catch {
            CallDiagnostics.shared.log("jam post failed: \(error)")
            return .failure(.rejected)
        }
        refreshJams()
        await deliverNow()
        return .success(())
    }

    /// Edits a post of mine in place (LIME-195): its words, title and subtitle; the subscribers get the new text and see "Edited".
    func editJamPost(_ post: JamPostInfo, title: String, subtitle: String, markdown: String, added: [OutgoingAttachment] = [], displayAs: String? = nil, removeCover: Bool = false, coauthors: [String]? = nil) async -> Bool {
        let displayAs = displayAs ?? post.displayAs
        #if DEBUG
        if isDemo { demoEdit(post.postId, title: title, subtitle: subtitle, markdown: markdown, displayAs: displayAs, added: added, removeCover: removeCover); jamEngagement += 1; return true }
        #endif
        guard let core else { return false }
        do { try await Task.detached(priority: .userInitiated) { try core.editJamPost(postId: post.postId, title: title, subtitle: subtitle, markdown: markdown, added: added, displayAs: displayAs, removeCover: removeCover, coauthors: coauthors) }.value }
        catch { CallDiagnostics.shared.log("jam edit failed: \(error)"); return false }
        refreshJams()
        await deliverNow()
        return true
    }

    /// Deletes a post of mine: it goes from my jam and, a little later, from my subscribers' phones.
    func deleteJamPost(_ postID: String) async -> Bool {
        #if DEBUG
        if isDemo { demoDelete(postID); return true }
        #endif
        guard let core else { return false }
        do { try await Task.detached(priority: .userInitiated) { try core.deleteJamPost(postId: postID) }.value }
        catch { CallDiagnostics.shared.log("jam delete failed: \(error)"); return false }
        refreshJams()
        await deliverNow()
        return true
    }

    /// Answers a request to be credited: the writer is told, and an accepted post is kept with the ones I am credited on.
    func answerCoauthorRequest(_ request: CoauthorRequest, accept: Bool) async {
        #if DEBUG
        if isDemo { demoAnswer(request, accept: accept); return }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.answerCoauthorRequest(postId: request.postId, accept: accept) }.value
        refreshJams()
        await deliverNow()
    }

    /// The people a post could be shared with as co-author: the contacts I have accepted.
    var coauthorChoices: [Person] {
        conversations.filter { $0.id.hasPrefix("dm:") && !$0.isRequest && $0.id != selfChatID }.compactMap(\.members.first).filter { $0.id != meProvider().id }
    }

    /// "Message me" in a post: the chat with its writer (a contact request when they are not yet a contact).
    func messageWriter(_ userID: String) async {
        if conversation("dm:\(userID)") != nil { openFromNotification("dm:\(userID)", thread: nil); return }
        await startChat(with: FoundUser(userId: userID, displayName: teacherName(userID), username: nil, school: nil, aboutEmoji: nil, aboutText: nil, isSelf: false))
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

extension ConversationStore {
    /// The jam posts a search finds (LIME-223): what the phone's index found by title, subtitle and text (`core`: post and marked snippet), then the posts
    /// whose writer or org name matches. Only posts I can read, none hidden.
    func jamResults(_ query: String, core hits: [(String, String)]) -> [JamHit] {
        let readable = Dictionary(jamFeed.map { ($0.postId, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [JamHit] = []
        var seen = Set<String>()
        func add(_ post: JamPostInfo, marked: String) {
            guard seen.insert(post.postId).inserted else { return }
            out.append(JamHit(postID: post.postId, title: post.title.isEmpty ? post.plain.prefix(60).description : post.title, from: authorName(post), marked: marked, date: Date(timeIntervalSince1970: Double(post.created) / 1000), kind: post.kind))
        }
        #if DEBUG
        if isDemo {
            for post in jamFeed where SearchText.matches([post.title, post.subtitle, post.plain].joined(separator: " "), query: query) {
                add(post, marked: SearchText.mark(post.title.isEmpty ? post.plain : post.title, query: query))
            }
        }
        #endif
        for (id, snippet) in hits { if let post = readable[id] { add(post, marked: snippet) } }
        for post in jamFeed where SearchText.matches(authorName(post) + " " + teacherName(post.author), query: query) {
            add(post, marked: post.title.isEmpty ? String(post.plain.prefix(80)) : post.title)
        }
        return out
    }
}
