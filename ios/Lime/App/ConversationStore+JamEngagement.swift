import Foundation

/// What the demo (and the UI tests) keep in place of the core for hearts and comments (LIME-189c).
struct DemoEngagement {
    var likers: [String: [String]] = [:]
    var comments: [String: [JamCommentInfo]] = [:]
    var unseen: Set<String> = []
}

extension ConversationStore {
    /// A post's numbers: the writer's latest tally (mine are counted live), my own heart at once.
    func jamCounts(_ postID: String) -> JamCountsInfo {
        _ = jamEngagement   // a heart or a comment redraws what shows it
        #if DEBUG
        if isDemo {
            let likers = demoEngagement.likers[postID] ?? []
            let comments = (demoEngagement.comments[postID] ?? []).filter { $0.state == "published" }.count
            return JamCountsInfo(postId: postID, likes: UInt32(likers.count), comments: UInt32(comments), remixes: 0, likers: likers, likedByMe: likers.contains(meProvider().id), unseen: demoEngagement.unseen.contains(postID))
        }
        #endif
        return (try? core?.jamPostCounts(postId: postID)) ?? JamCountsInfo(postId: postID, likes: 0, comments: 0, remixes: 0, likers: [], likedByMe: false, unseen: false)
    }

    /// ♥ or un-♥ (a light tap).
    func jamToggleLike(_ postID: String) {
        let on = !jamCounts(postID).likedByMe
        #if DEBUG
        if isDemo {
            var list = demoEngagement.likers[postID] ?? []
            list.removeAll { $0 == meProvider().id }
            if on { list.insert(meProvider().id, at: 0) }
            demoEngagement.likers[postID] = list
            jamEngagement += 1
            return
        }
        #endif
        _ = try? core?.reactToJamPost(postId: postID, on: on)
        jamEngagement += 1
        Task { await deliverNow() }
    }

    func jamComments(_ postID: String) -> [JamCommentInfo] {
        _ = jamEngagement
        #if DEBUG
        if isDemo { return demoEngagement.comments[postID] ?? [] }
        #endif
        return (try? core?.listJamComments(postId: postID)) ?? []
    }

    /// Writes a comment (or a reply): on someone else's post it waits as **pending** until the writer's phone publishes it.
    func jamComment(_ postID: String, text: String, parent: String?) async -> Bool {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, words.count <= 2000 else { return false }
        #if DEBUG
        if isDemo {
            let mineJam = jamPost(postID).map { post in jamsMine.contains { $0.jamId == post.jamId } } ?? false
            let top = parent.flatMap { id in demoEngagement.comments[postID]?.first { $0.commentId == id } }.map { $0.parentId ?? $0.commentId }
            demoEngagement.comments[postID, default: []].append(JamCommentInfo(commentId: UUID().uuidString.lowercased(), postId: postID, parentId: top, author: meProvider().id, text: words,
                                                                              created: Int64(Date().timeIntervalSince1970 * 1000), state: mineJam ? "published" : "pending", mine: true))
            jamEngagement += 1
            return true
        }
        #endif
        guard let core else { return false }
        let ok = (try? await Task.detached { try core.commentOnJamPost(postId: postID, text: words, parentId: parent) }.value) != nil
        jamEngagement += 1
        await deliverNow()
        return ok
    }

    func jamDeleteComment(_ commentID: String, postID: String) async {
        #if DEBUG
        if isDemo {
            demoEngagement.comments[postID]?.removeAll { $0.commentId == commentID || $0.parentId == commentID }
            jamEngagement += 1
            return
        }
        #endif
        guard let core else { return }
        _ = try? await Task.detached { try core.deleteJamComment(commentId: commentID) }.value
        jamEngagement += 1
        await deliverNow()
    }

    /// The writer has looked at the comments on a post.
    func jamMarkSeen(_ postID: String) {
        #if DEBUG
        if isDemo { demoEngagement.unseen.remove(postID); jamEngagement += 1; return }
        #endif
        _ = try? core?.markJamPostSeen(postId: postID)
        jamEngagement += 1
    }

    /// Is this post one of mine (its jam is)?
    func isMyJamPost(_ post: JamPostInfo) -> Bool { jamsMine.contains { $0.jamId == post.jamId } }

    /// People among my contacts who liked a post (their faces show; others do not).
    func contactLikers(_ counts: JamCountsInfo) -> [Person] {
        let contacts = Dictionary(coauthorChoices.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return counts.likers.compactMap { contacts[$0] }
    }

    /// Activity of a person, from what this phone already has (LIME-189d): on **my own** profile all of mine (comments others made on my posts, and my
    /// own likes, comments and replies); on **someone else's**, only what my own access lets me see: their comments and replies and their likes (from
    /// the likers lists) on posts I can read (my own and the jams I follow). Newest first; computed here, nothing fetched.
    func jamActivity(of userID: String? = nil) -> [JamActivityItem] {
        let me = meProvider().id
        let who = userID ?? me
        let known = Dictionary(((jamsMine + jamSubscriptions).flatMap { posts(of: $0.jamId) } + coauthoredPosts).map { ($0.postId, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [JamActivityItem] = []
        for post in known.values {
            let counts = jamCounts(post.postId)
            for comment in jamComments(post.postId) {
                if comment.author == who {
                    out.append(JamActivityItem(id: "c-" + comment.commentId, post: post, who: who, kind: comment.parentId == nil ? .commented : .replied, text: comment.text, date: comment.created))
                } else if who == me && comment.state == "published" && isMyJamPost(post) {
                    out.append(JamActivityItem(id: "n-" + comment.commentId, post: post, who: comment.author, kind: .commentedOnMine, text: comment.text, date: comment.created))
                }
            }
            let liked = who == me ? counts.likedByMe : counts.likers.contains(who)
            if liked { out.append(JamActivityItem(id: "l-" + post.postId, post: post, who: who, kind: .liked, text: "", date: post.created)) }
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(60))
    }

    func jamHasUnseen() -> Bool { jamsMine.flatMap { posts(of: $0.jamId) }.contains { jamCounts($0.postId).unseen } }
}

/// One line of Activity.
struct JamActivityItem: Identifiable {
    enum Kind { case commentedOnMine, commented, replied, liked }
    let id: String
    let post: JamPostInfo
    let who: String
    let kind: Kind
    let text: String
    let date: Int64
}
