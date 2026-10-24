#if DEBUG
import Foundation
import UIKit

/// Demo mode (UI tests and screenshots): jam with no core, in memory.
extension ConversationStore {
    func demoStartJam(title: String, about: String, topics: [String]) {
        jamsMine = [JamInfo(jamId: "demo-my-jam", conversationId: "jam:demo-my-jam", writer: meProvider().id, title: title, about: about, topics: topics, tiers: ["free", "subscribers"],
                            mine: true, status: "active", ended: false, subscriberCount: 0, postCount: 0, created: Int64(Date().timeIntervalSince1970 * 1000))]
        jamPosts["demo-my-jam"] = []
    }

    func demoEditJam(_ jamID: String, title: String, about: String, topics: [String]) {
        guard let i = jamsMine.firstIndex(where: { $0.jamId == jamID }) else { return }
        let old = jamsMine[i]
        jamsMine[i] = JamInfo(jamId: old.jamId, conversationId: old.conversationId, writer: old.writer, title: title, about: about, topics: topics, tiers: old.tiers, mine: true,
                              status: "active", ended: false, subscriberCount: old.subscriberCount, postCount: old.postCount, created: old.created)
    }

    /// The bytes of demo files that are not pictures (a post's captions), by attachment id.
    nonisolated(unsafe) static var demoJamBlobs: [String: Data] = [:]

    func demoPublish(_ jamID: String, kind: String, title: String, subtitle: String, markdown: String, items: [OutgoingAttachment], coauthors: [String] = [], displayAs: String = "person") {
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
                               attachmentsJson: "[]", created: Int64(Date().timeIntervalSince1970 * 1000), coauthors: coauthors, displayAs: displayAs, editedAt: 0, state: "ready")
        jamPosts[jamID, default: []].append(post)
        if let i = jamsMine.firstIndex(where: { $0.jamId == jamID }) {
            let old = jamsMine[i]
            jamsMine[i] = JamInfo(jamId: old.jamId, conversationId: old.conversationId, writer: old.writer, title: old.title, about: old.about, topics: old.topics, tiers: old.tiers, mine: true,
                                  status: "active", ended: false, subscriberCount: old.subscriberCount, postCount: old.postCount + 1, created: old.created)
        }
    }

    /// Following Sam's demo jam: two posts, the first with bold text, a list and a photo.
    func demoSubscribe(_ page: JamPageInfo) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        jamSubscriptions.removeAll { $0.jamId == page.jamId }
        jamSubscriptions.append(JamInfo(jamId: page.jamId, conversationId: "jam:\(page.jamId)", writer: page.writerId, title: page.title, about: page.about, topics: page.topics, tiers: ["free"],
                                        mine: false, status: "active", ended: false, subscriberCount: 0, postCount: 2, created: now))
        let first = JamPostInfo(postId: "demo-post-1", jamId: page.jamId, author: page.writerId, tier: "free", kind: "article", title: "Equivalent fractions in ten minutes", subtitle: "Fold, cut, compare",
                                markdown: "**Start** with a pizza.\n\n- fold it\n- cut it\n- compare the pieces", plain: "Start with a pizza.\n• fold it\n• cut it\n• compare the pieces",
                                attachmentsJson: "[]", created: now - 3_600_000, coauthors: ["lee"], displayAs: "person", editedAt: 0, state: "ready")
        let second = JamPostInfo(postId: "demo-post-2", jamId: page.jamId, author: page.writerId, tier: "free", kind: "quick", title: "", subtitle: "",
                                 markdown: "A quick exit ticket: ask one question at the door, *which pieces are equal?*", plain: "A quick exit ticket: ask one question at the door, which pieces are equal?",
                                 attachmentsJson: "[]", created: now - 600_000, coauthors: [], displayAs: "person", editedAt: 0, state: "ready")
        let third = JamPostInfo(postId: "demo-post-3", jamId: page.jamId, author: page.writerId, tier: "free", kind: "record", title: "Ten seconds on fraction walls", subtitle: "", markdown: "", plain: "",
                                attachmentsJson: "[]", created: now - 60_000, coauthors: [], displayAs: "person", editedAt: 0, state: "ready")
        let fourth = JamPostInfo(postId: "demo-post-4", jamId: page.jamId, author: page.writerId, tier: "free", kind: "record", title: "Sunday planning, 18 minutes", subtitle: "Week 4 planning with Sam", markdown: "", plain: "",
                                 attachmentsJson: "[]", created: now - 7_200_000, coauthors: [], displayAs: "person", editedAt: 0, state: "ready")
        demoJamAttachments["demo-post-4"] = [JamAttachmentInfo(attachmentId: "demo-audio-1", name: "Recording.m4a", mime: "audio/mp4", kind: "audio", size: 90_000, width: nil, height: nil,
                                                               durationMs: 1_080_000, thumb: Data((0..<64).map { UInt8(40 + (($0 * 37) % 200)) }), poster: Data(), available: true)]
        jamPosts[page.jamId] = [first, second, third, fourth]
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
        jamSubscribers["demo-my-jam"] = [
            JamSubscriberInfo(userId: "sam", name: "Sam Park", since: 1, tier: "free", status: "active"),
            JamSubscriberInfo(userId: "lee", name: "Lee Wong", since: 2, tier: "free", status: "active"),
        ]
        if let i = jamsMine.firstIndex(where: { $0.jamId == "demo-my-jam" }) {
            let old = jamsMine[i]
            jamsMine[i] = JamInfo(jamId: old.jamId, conversationId: old.conversationId, writer: old.writer, title: old.title, about: old.about, topics: old.topics, tiers: old.tiers, mine: true,
                                  status: "active", ended: false, subscriberCount: 2, postCount: old.postCount, created: old.created)
        }
    }

    func demoEdit(_ postID: String, title: String, subtitle: String, markdown: String, displayAs: String = "person") {
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
                                  status: "active", ended: false, subscriberCount: old.subscriberCount, postCount: max(0, old.postCount - 1), created: old.created)
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
                                               plain: "Words", attachmentsJson: "[]", created: request.created, coauthors: [meProvider().id], displayAs: "person", editedAt: 0, state: "ready"), at: 0)
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
}
#endif
