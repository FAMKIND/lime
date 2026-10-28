#if DEBUG
import Foundation
import UIKit

/// Demo mode (UI tests and screenshots): jam with no core, in memory.
extension ConversationStore {
    func demoStartJam(title: String, about: String, topics: [String]) {
        jamsMine = [JamInfo(jamId: "demo-my-jam", conversationId: "jam:demo-my-jam", writer: meProvider().id, title: title, about: about, topics: topics, tiers: ["free", "subscribers"],
                            mine: true, status: "active", ended: false, community: false, communityState: nil, communityGroup: nil, subscriberCount: 0, postCount: 0, created: Int64(Date().timeIntervalSince1970 * 1000))]
        jamPosts["demo-my-jam"] = []
    }

    func demoEditJam(_ jamID: String, title: String, about: String, topics: [String]) {
        guard let i = jamsMine.firstIndex(where: { $0.jamId == jamID }) else { return }
        let old = jamsMine[i]
        jamsMine[i] = JamInfo(jamId: old.jamId, conversationId: old.conversationId, writer: old.writer, title: title, about: about, topics: topics, tiers: old.tiers, mine: true,
                              status: "active", ended: false, community: false, communityState: nil, communityGroup: nil, subscriberCount: old.subscriberCount, postCount: old.postCount, created: old.created)
    }

    /// The bytes of demo files that are not pictures (a post's captions), by attachment id.
    nonisolated(unsafe) static var demoJamBlobs: [String: Data] = [:]

    func demoPublish(_ jamID: String, kind: String, title: String, subtitle: String, markdown: String, items: [OutgoingAttachment], coauthors: [String] = [], displayAs: String = "person", audience: String = "subscribers", series: SeriesInfo? = nil, topics: [String] = []) {
        let id = UUID().uuidString.lowercased()
        let info = items.map { item -> JamAttachmentInfo in
            let fileID = UUID().uuidString.lowercased()
            if item.mime == "text/vtt" { Self.demoJamBlobs[fileID] = item.bytes }
            let kind = item.mime.hasPrefix("image/") ? "image" : item.mime.hasPrefix("video/") ? "video" : item.mime.hasPrefix("audio/") ? "audio" : "file"
            return JamAttachmentInfo(attachmentId: fileID, name: item.name, mime: item.mime, kind: kind, size: UInt64(item.bytes.count), width: item.width, height: item.height,
                                     durationMs: item.durationMs, thumb: item.thumb, poster: item.poster, available: true)
        }
        demoJamAttachments[id] = info
        let post = JamPostInfo(postId: id, jamId: jamID, author: meProvider().id, tier: "free", kind: kind, title: title, subtitle: subtitle, markdown: markdown, plain: messagePlainText(text: markdown),
                               attachmentsJson: "[]", created: Int64(Date().timeIntervalSince1970 * 1000), coauthors: coauthors, displayAs: displayAs, editedAt: 0, audience: audience, series: series, topics: topics, state: "ready")
        jamPosts[jamID, default: []].append(post)
        // An Everyone post shows up in Discover (the demo has no server), under its chips or else the jam's topics.
        if audience == "everyone" {
            let chips = topics.isEmpty ? (jamsMine.first { $0.jamId == jamID }?.topics ?? []) : topics
            discoverItems.append(OpenFeedItem(postId: id, authorId: meProvider().id, jamId: jamID, kind: kind, title: title, subtitle: subtitle, excerpt: String(post.plain.prefix(240)), topics: chips, fileIds: [], series: series,
                                              previewOf: nil, hasRest: false, version: 1, created: post.created, seq: Int64(discoverItems.count + 1)))
        }
        if let i = jamsMine.firstIndex(where: { $0.jamId == jamID }) {
            let old = jamsMine[i]
            jamsMine[i] = JamInfo(jamId: old.jamId, conversationId: old.conversationId, writer: old.writer, title: old.title, about: old.about, topics: old.topics, tiers: old.tiers, mine: true,
                                  status: "active", ended: false, community: false, communityState: nil, communityGroup: nil, subscriberCount: old.subscriberCount, postCount: old.postCount + 1, created: old.created)
        }
    }

    /// Following Sam's demo jam: two posts, the first with bold text, a list and a photo.
    func demoSubscribe(_ page: JamPageInfo) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        jamSubscriptions.removeAll { $0.jamId == page.jamId }
        jamSubscriptions.append(JamInfo(jamId: page.jamId, conversationId: "jam:\(page.jamId)", writer: page.writerId, title: page.title, about: page.about, topics: page.topics, tiers: ["free"],
                                        mine: false, status: "active", ended: false, community: false, communityState: nil, communityGroup: nil, subscriberCount: 0, postCount: 2, created: now))
        let first = JamPostInfo(postId: "demo-post-1", jamId: page.jamId, author: page.writerId, tier: "free", kind: "article", title: "Equivalent fractions in ten minutes", subtitle: "Fold, cut, compare",
                                markdown: "**Start** with a pizza.\n\n- fold it\n- cut it\n- compare the pieces", plain: "Start with a pizza.\n• fold it\n• cut it\n• compare the pieces",
                                attachmentsJson: "[]", created: now - 3_600_000, coauthors: ["lee"], displayAs: "person", editedAt: 0, audience: "subscribers", series: nil, topics: [], state: "ready")
        let second = JamPostInfo(postId: "demo-post-2", jamId: page.jamId, author: page.writerId, tier: "free", kind: "quick", title: "", subtitle: "",
                                 markdown: "A quick exit ticket: ask one question at the door, *which pieces are equal?*", plain: "A quick exit ticket: ask one question at the door, which pieces are equal?",
                                 attachmentsJson: "[]", created: now - 600_000, coauthors: [], displayAs: "person", editedAt: 0, audience: "subscribers", series: nil, topics: [], state: "ready")
        let third = JamPostInfo(postId: "demo-post-3", jamId: page.jamId, author: page.writerId, tier: "free", kind: "record", title: "Ten seconds on fraction walls", subtitle: "", markdown: "", plain: "",
                                attachmentsJson: "[]", created: now - 60_000, coauthors: [], displayAs: "person", editedAt: 0, audience: "subscribers", series: nil, topics: [], state: "ready")
        let fourth = JamPostInfo(postId: "demo-post-4", jamId: page.jamId, author: page.writerId, tier: "free", kind: "record", title: "Sunday planning, 18 minutes", subtitle: "Week 4 planning with Sam", markdown: "", plain: "",
                                 attachmentsJson: "[]", created: now - 7_200_000, coauthors: [], displayAs: "person", editedAt: 0, audience: "subscribers", series: nil, topics: [], state: "ready")
        demoJamAttachments["demo-post-4"] = [JamAttachmentInfo(attachmentId: "demo-audio-1", name: "Recording.m4a", mime: "audio/mp4", kind: "audio", size: 90_000, width: nil, height: nil,
                                                               durationMs: 1_080_000, thumb: Data((0..<64).map { UInt8(40 + (($0 * 37) % 200)) }), poster: Data(), available: true)]
        jamPosts[page.jamId] = [first, second, third, fourth]
        // Hearts and a comment from people I know (LIME-189c).
        demoEngagement.likers["demo-post-2"] = ["lee", "sam"]
        demoEngagement.comments["demo-post-2"] = [JamCommentInfo(commentId: "demo-comment-1", postId: "demo-post-2", parentId: nil, author: "lee", text: "Love this", created: now - 300_000, state: "published", mine: false)]
        demoJamAttachments["demo-post-3"] = [JamAttachmentInfo(attachmentId: "demo-video-1", name: "wall.mp4", mime: "video/mp4", kind: "video", size: 90_000, width: 480, height: 270,
                                                               durationMs: 10_000, thumb: Data(), poster: Data(), available: true),
                                                 JamAttachmentInfo(attachmentId: "demo-captions-1", name: "captions-0.vtt", mime: "text/vtt", kind: "file", size: 200, width: nil, height: nil,
                                                                   durationMs: nil, thumb: Data(), poster: Data(), available: true)]
        demoJamAttachments["demo-post-1"] = [JamAttachmentInfo(attachmentId: "demo-photo-1", name: "pizza.jpg", mime: "image/jpeg", kind: "image", size: 40_000, width: 600, height: 400,
                                                               durationMs: nil, thumb: Data(), poster: Data(), available: true)]
    }

    /// A jam of my own with one post and two subscribers (to remove one).
    func demoMineWithPost() {
        demoStartJam(title: "Reading circles", about: "What worked in my room", topics: ["Reading", "Grade 2"])
        demoPublish("demo-my-jam", kind: "article", title: "Our first circle", subtitle: "", markdown: "We read **aloud** together.", items: [])
        if let mine = jamPosts["demo-my-jam"]?.last {
            demoEngagement.likers[mine.postId] = ["sam"]
            demoEngagement.comments[mine.postId] = [JamCommentInfo(commentId: "demo-comment-2", postId: mine.postId, parentId: nil, author: "sam", text: "Great circle", created: Int64(Date().timeIntervalSince1970 * 1000) - 60_000, state: "published", mine: false)]
            demoEngagement.unseen.insert(mine.postId)
        }
        jamSubscribers["demo-my-jam"] = [
            JamSubscriberInfo(userId: "sam", name: "Sam Park", since: 1, tier: "free", status: "active"),
            JamSubscriberInfo(userId: "lee", name: "Lee Wong", since: 2, tier: "free", status: "active"),
        ]
        if let i = jamsMine.firstIndex(where: { $0.jamId == "demo-my-jam" }) {
            let old = jamsMine[i]
            jamsMine[i] = JamInfo(jamId: old.jamId, conversationId: old.conversationId, writer: old.writer, title: old.title, about: old.about, topics: old.topics, tiers: old.tiers, mine: true,
                                  status: "active", ended: false, community: false, communityState: nil, communityGroup: nil, subscriberCount: 2, postCount: old.postCount, created: old.created)
        }
    }

    func demoEdit(_ postID: String, title: String, subtitle: String, markdown: String, displayAs: String = "person", added: [OutgoingAttachment] = [], removeCover: Bool = false) {
        if removeCover || added.contains(where: { $0.name == "cover.jpg" }) { demoJamAttachments[postID]?.removeAll { $0.name == "cover.jpg" } }
        for file in added where file.name == "cover.jpg" {
            demoJamAttachments[postID, default: []].append(JamAttachmentInfo(attachmentId: UUID().uuidString.lowercased(), name: "cover.jpg", mime: "image/jpeg", kind: "image", size: UInt64(file.bytes.count), width: file.width, height: file.height, durationMs: nil, thumb: file.thumb, poster: Data(), available: true))
        }
        for (jam, posts) in jamPosts {
            guard let i = posts.firstIndex(where: { $0.postId == postID }) else { continue }
            var post = posts[i]
            post.title = title; post.subtitle = subtitle; post.markdown = markdown; post.plain = messagePlainText(text: markdown)
            post.editedAt = Int64(Date().timeIntervalSince1970 * 1000); post.displayAs = displayAs == "jam" ? "jam" : "person"
            jamPosts[jam]?[i] = post
        }
    }

    func demoDelete(_ postID: String) {
        for jam in jamPosts.keys { jamPosts[jam]?.removeAll { $0.postId == postID } }
        demoJamAttachments[postID] = nil
        if let i = jamsMine.firstIndex(where: { $0.postCount > 0 && jamPosts[$0.jamId] != nil }) {
            let old = jamsMine[i]
            jamsMine[i] = JamInfo(jamId: old.jamId, conversationId: old.conversationId, writer: old.writer, title: old.title, about: old.about, topics: old.topics, tiers: old.tiers, mine: true,
                                  status: "active", ended: false, community: false, communityState: nil, communityGroup: nil, subscriberCount: old.subscriberCount, postCount: max(0, old.postCount - 1), created: old.created)
        }
    }

    /// A made-up request to be credited, and what answering does.
    func demoRequest() {
        jamRequests = [CoauthorRequest(postId: "demo-request-post", jamId: "demo-sam-jam", writer: "sam", title: "What is liming?", kind: "article", created: Int64(Date().timeIntervalSince1970 * 1000))]
    }

    func demoAnswer(_ request: CoauthorRequest, accept: Bool) {
        jamRequests.removeAll { $0.postId == request.postId }
        if accept {
            coauthoredPosts.insert(JamPostInfo(postId: request.postId, jamId: request.jamId, author: request.writer, tier: "free", kind: request.kind, title: request.title, subtitle: "", markdown: "Words",
                                               plain: "Words", attachmentsJson: "[]", created: request.created, coauthors: [meProvider().id], displayAs: "person", editedAt: 0, audience: "subscribers", series: nil, topics: [], state: "ready"), at: 0)
        }
    }

    /// A made-up picture for any demo file.
    func demoJamImage(_ id: String) -> Data? {
        if let blob = Self.demoJamBlobs[id] { return blob }
        if id == "demo-captions-1" { return Data("WEBVTT\n\n00:00.000 --> 00:04.000\nA fraction wall in ten seconds.\n\n00:04.000 --> 00:10.000\nFold it, cut it, compare the pieces.\n".utf8) }
        let size = CGSize(width: 600, height: 400)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor(hue: 0.08, saturation: 0.35, brightness: 0.95, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.6).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 150, y: 50, width: 300, height: 300))
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    // MARK: Open posts and Discover (LIME-210c)

    /// Discover with made-up open posts: four of Sam's (the first is a Preview of the post you get by subscribing), one of Lee's, one of Priya's.
    func demoDiscover() {
        openPostsEnabled = true
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        func page(_ id: String, _ title: String, _ topics: [String]) -> JamPageInfo { JamPageInfo(jamId: "demo-\(id)-jam", writerId: id, title: title, about: "", topics: topics, postCount: 3, subscriberCount: 12, hasCommunity: false) }
        openWriterPages = ["sam": demoJamPages["sam"] ?? page("sam", "Fractions that stick", ["Maths", "Grade 4"]), "lee": page("lee", "Reading circles", ["Reading", "Grade 3"]), "priya.nair": page("priya.nair", "Practice, not homework", ["Practice"])]
        var items: [OpenFeedItem] = []
        func add(_ id: String, _ author: String, _ title: String, _ subtitle: String, _ body: String, _ topics: [String], preview: Bool = false, ago: Int64) {
            let jam = openWriterPages[author]?.jamId ?? "demo-\(author)-jam"
            items.append(OpenFeedItem(postId: id, authorId: author, jamId: jam, kind: "article", title: title, subtitle: subtitle, excerpt: String(body.prefix(240)), topics: topics, fileIds: [], series: nil,
                                      previewOf: preview ? id : nil, hasRest: preview, version: 1, created: now - ago * 60_000, seq: Int64(items.count + 1)))
            demoOpenPosts[id] = OpenPostInfo(postId: id, authorId: author, jamId: jam, kind: "article", title: title, subtitle: subtitle, markdown: body, plain: messagePlainText(text: body), topics: topics, files: [],
                                             series: nil, previewOf: preview ? id : nil, hasRest: preview, version: 1, created: now - ago * 60_000, pinned: false)
        }
        add("demo-post-1", "sam", "Equivalent fractions in ten minutes", "Fold, cut, compare", "Fold a strip of paper in half, then in half again. **Equal parts** are the whole idea.", ["Maths", "Grade 4"], preview: true, ago: 400)
        add("demo-open-sam-2", "sam", "Fraction walls", "", "Build a wall of bricks, one row for each fraction.", ["Maths", "Grade 4"], ago: 300)
        add("demo-open-sam-3", "sam", "Comparing with benchmarks", "", "Is it more or less than a half? Start there.", ["Maths", "Grade 4"], ago: 200)
        add("demo-open-sam-4", "sam", "Mixed numbers, gently", "", "Show three pizzas and a quarter before any rule.", ["Maths", "Grade 5"], ago: 100)
        add("demo-open-lee-1", "lee", "Setting up reading circles", "A first week", "Four chairs, one book each, and a job for everyone.", ["Reading", "Grade 3"], ago: 50)
        add("demo-open-priya-1", "priya.nair", "Why we stopped giving homework", "", "We swapped it for ten minutes of practice a child chooses.", ["Practice"], ago: 20)
        discoverItems = items
        jamSegment = .discover
    }

    func demoSetCommunity(_ jamID: String, on: Bool) {
        if let i = jamsMine.firstIndex(where: { $0.jamId == jamID }) { jamsMine[i] = demoWithCommunity(jamsMine[i], on: on, state: nil) }
        if let i = jamSubscriptions.firstIndex(where: { $0.jamId == jamID }) { jamSubscriptions[i] = demoWithCommunity(jamSubscriptions[i], on: on, state: nil) }
    }

    func demoJoinCommunity(_ jamID: String) {
        if let i = jamSubscriptions.firstIndex(where: { $0.jamId == jamID }) { jamSubscriptions[i] = demoWithCommunity(jamSubscriptions[i], on: true, state: "asked") }
    }

    private func demoWithCommunity(_ old: JamInfo, on: Bool, state: String?) -> JamInfo {
        JamInfo(jamId: old.jamId, conversationId: old.conversationId, writer: old.writer, title: old.title, about: old.about, topics: old.topics, tiers: old.tiers, mine: old.mine, status: old.status,
                ended: old.ended, community: on, communityState: state, communityGroup: old.communityGroup, subscriberCount: old.subscriberCount, postCount: old.postCount, created: old.created)
    }

    func demoSetSeries(_ post: JamPostInfo, _ series: SeriesInfo?) {
        guard var list = jamPosts[post.jamId], let i = list.firstIndex(where: { $0.postId == post.postId }) else { return }
        let old = list[i]
        list[i] = JamPostInfo(postId: old.postId, jamId: old.jamId, author: old.author, tier: old.tier, kind: old.kind, title: old.title, subtitle: old.subtitle, markdown: old.markdown, plain: old.plain,
                              attachmentsJson: old.attachmentsJson, created: old.created, coauthors: old.coauthors, displayAs: old.displayAs, editedAt: old.editedAt, audience: old.audience, series: series, topics: old.topics, state: old.state)
        jamPosts[post.jamId] = list
    }

    /// A followed jam (Sam's) with a series: Part 1 and Part 3 are here, Part 2 is an open Preview in Discover. Part 1 is read.
    func demoSeriesScreen() {
        guard let page = demoJamPages["sam"] else { return }
        demoSubscribe(page)
        openPostsEnabled = true
        func series(_ part: UInt32) -> SeriesInfo { SeriesInfo(id: "demo-series-fractions", title: "Fractions that stick", part: part, of: 3) }
        for post in jamPosts[page.jamId] ?? [] where post.postId == "demo-post-1" || post.postId == "demo-post-2" { demoSetSeries(post, series(post.postId == "demo-post-1" ? 1 : 3)) }
        JamRead.mark("demo-post-1")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        discoverItems = [OpenFeedItem(postId: "demo-open-sam-part2", authorId: "sam", jamId: page.jamId, kind: "article", title: "Fraction walls", subtitle: "", excerpt: "Build a wall of bricks.", topics: ["Maths"], fileIds: [],
                                      series: series(2), previewOf: "demo-open-sam-part2", hasRest: true, version: 1, created: now - 600_000, seq: 1)]
    }

    func demoSetTopics(_ post: JamPostInfo, _ topics: [String]) {
        guard var list = jamPosts[post.jamId], let i = list.firstIndex(where: { $0.postId == post.postId }) else { return }
        let old = list[i]
        list[i] = JamPostInfo(postId: old.postId, jamId: old.jamId, author: old.author, tier: old.tier, kind: old.kind, title: old.title, subtitle: old.subtitle, markdown: old.markdown, plain: old.plain,
                              attachmentsJson: old.attachmentsJson, created: old.created, coauthors: old.coauthors, displayAs: old.displayAs, editedAt: old.editedAt, audience: old.audience, series: old.series, topics: topics, state: old.state)
        jamPosts[post.jamId] = list
    }

    func demoSetAudience(_ post: JamPostInfo, _ audience: String) {
        guard var list = jamPosts[post.jamId], let i = list.firstIndex(where: { $0.postId == post.postId }) else { return }
        let old = list[i]
        list[i] = JamPostInfo(postId: old.postId, jamId: old.jamId, author: old.author, tier: old.tier, kind: old.kind, title: old.title, subtitle: old.subtitle, markdown: old.markdown, plain: old.plain,
                              attachmentsJson: old.attachmentsJson, created: old.created, coauthors: old.coauthors, displayAs: old.displayAs, editedAt: old.editedAt, audience: audience, series: old.series, topics: old.topics, state: old.state)
        jamPosts[post.jamId] = list
    }
}
#endif
