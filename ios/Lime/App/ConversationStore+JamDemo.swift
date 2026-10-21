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

    func demoPublish(_ jamID: String, kind: String, title: String, subtitle: String, markdown: String, items: [OutgoingAttachment], coauthors: [String] = []) {
        let id = UUID().uuidString.lowercased()
        let info = items.map {
            JamAttachmentInfo(attachmentId: UUID().uuidString.lowercased(), name: $0.name, mime: $0.mime, kind: $0.mime.hasPrefix("image/") ? "image" : $0.mime.hasPrefix("video/") ? "video" : $0.mime.hasPrefix("audio/") ? "audio" : "file",
                              size: UInt64($0.bytes.count), width: $0.width, height: $0.height, durationMs: $0.durationMs, thumb: $0.thumb, poster: $0.poster, available: true)
        }
        demoJamAttachments[id] = info
        let post = JamPostInfo(postId: id, jamId: jamID, author: meProvider().id, tier: "free", kind: kind, title: title, subtitle: subtitle, markdown: markdown, plain: messagePlainText(text: markdown),
                               attachmentsJson: "[]", created: Int64(Date().timeIntervalSince1970 * 1000), coauthors: coauthors, state: "ready")
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
                                attachmentsJson: "[]", created: now - 3_600_000, coauthors: ["lee"], state: "ready")
        let second = JamPostInfo(postId: "demo-post-2", jamId: page.jamId, author: page.writerId, tier: "free", kind: "quick", title: "", subtitle: "",
                                 markdown: "A quick exit ticket: ask one question at the door, *which pieces are equal?*", plain: "A quick exit ticket: ask one question at the door, which pieces are equal?",
                                 attachmentsJson: "[]", created: now - 600_000, coauthors: [], state: "ready")
        let third = JamPostInfo(postId: "demo-post-3", jamId: page.jamId, author: page.writerId, tier: "free", kind: "record", title: "Ten seconds on fraction walls", subtitle: "", markdown: "", plain: "",
                                attachmentsJson: "[]", created: now - 60_000, coauthors: [], state: "ready")
        let fourth = JamPostInfo(postId: "demo-post-4", jamId: page.jamId, author: page.writerId, tier: "free", kind: "record", title: "Sunday planning, 18 minutes", subtitle: "", markdown: "", plain: "",
                                 attachmentsJson: "[]", created: now - 7_200_000, coauthors: [], state: "ready")
        demoJamAttachments["demo-post-4"] = [JamAttachmentInfo(attachmentId: "demo-audio-1", name: "Recording.m4a", mime: "audio/mp4", kind: "audio", size: 90_000, width: nil, height: nil,
                                                               durationMs: 1_080_000, thumb: Data((0..<64).map { UInt8(40 + (($0 * 37) % 200)) }), poster: Data(), available: true)]
        jamPosts[page.jamId] = [first, second, third, fourth]
        demoJamAttachments["demo-post-3"] = [JamAttachmentInfo(attachmentId: "demo-video-1", name: "wall.mp4", mime: "video/mp4", kind: "video", size: 90_000, width: 480, height: 270,
                                                               durationMs: 10_000, thumb: Data(), poster: Data(), available: true)]
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

    /// A made-up request to be credited, and what answering does.
    func demoRequest() {
        jamRequests = [CoauthorRequest(postId: "demo-request-post", jamId: "demo-sam-jam", writer: "sam", title: "What is liming?", kind: "article", created: Int64(Date().timeIntervalSince1970 * 1000))]
    }

    func demoAnswer(_ request: CoauthorRequest, accept: Bool) {
        jamRequests.removeAll { $0.postId == request.postId }
        if accept {
            coauthoredPosts.insert(JamPostInfo(postId: request.postId, jamId: request.jamId, author: request.writer, tier: "free", kind: request.kind, title: request.title, subtitle: "", markdown: "Words",
                                               plain: "Words", attachmentsJson: "[]", created: request.created, coauthors: [meProvider().id], state: "ready"), at: 0)
        }
    }

    /// A made-up picture for any demo file.
    func demoJamImage(_ id: String) -> Data? {
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
