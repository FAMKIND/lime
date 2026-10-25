import Foundation

/// What a person is reporting (LIME-191): the ids the moderators need, the item as this phone holds it, and a line saying what it is.
struct ReportTarget: Identifiable, Equatable {
    let id = UUID()
    /// message, person, group, jam_post, comment, jam, org or profile_item.
    var kind: String
    var ids: [String]
    /// "message", "post", "comment", "profile", "jam"…: the word in "Include this …".
    var noun: String
    var personName: String?
    /// The chat to block with "Also block", when the reported person has one.
    var blockConversationID: String?
    /// The item as held, JSON text; what "Include" sends.
    var included: String
    /// What the sheet shows the reporter will be sent.
    var preview: String
}

enum ReportReason: String, CaseIterable, Identifiable {
    case harassment, spam, impersonation, inappropriate, child_safety, hate_violence, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .harassment: "Harassment or bullying"
        case .spam: "Spam or scam"
        case .impersonation: "Impersonation"
        case .inappropriate: "Inappropriate or sexual content"
        case .child_safety: "A child\u{2019}s safety"
        case .hate_violence: "Hate or violence"
        case .other: "Something else"
        }
    }
}

extension ConversationStore {
    private func jsonText(_ object: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func blockChat(for userID: String) -> String? {
        let id = "dm:\(userID)"
        return conversations.contains { $0.id == id } ? id : nil
    }

    func reportTarget(post: JamPostInfo) -> ReportTarget {
        let who = teacherName(post.author)
        let words = [post.title, post.subtitle, post.plain].filter { !$0.isEmpty }.joined(separator: "\n")
        return ReportTarget(kind: "jam_post", ids: [post.postId, post.jamId, post.author], noun: "post", personName: who, blockConversationID: blockChat(for: post.author),
                            included: jsonText(["post_id": post.postId, "jam_id": post.jamId, "author": post.author, "title": post.title, "subtitle": post.subtitle,
                                                "text": post.markdown, "created": post.created, "kind": post.kind]),
                            preview: String(words.prefix(160)))
    }

    func reportTarget(comment: JamCommentInfo) -> ReportTarget {
        ReportTarget(kind: "comment", ids: [comment.commentId, comment.postId, comment.author], noun: "comment", personName: teacherName(comment.author), blockConversationID: blockChat(for: comment.author),
                     included: jsonText(["comment_id": comment.commentId, "post_id": comment.postId, "author": comment.author, "text": comment.text, "created": comment.created]),
                     preview: String(comment.text.prefix(160)))
    }

    func reportTarget(personID: String, name: String) -> ReportTarget {
        ReportTarget(kind: "person", ids: [personID], noun: "profile", personName: name, blockConversationID: blockChat(for: personID),
                     included: jsonText(["user_id": personID, "name": name]), preview: name)
    }

    func reportTarget(message: Message, conversationID: String, from name: String?) -> ReportTarget {
        let sender = message.senderID ?? ""
        return ReportTarget(kind: "message", ids: [message.id, conversationID, sender], noun: "message", personName: name, blockConversationID: conversationID.hasPrefix("dm:") ? conversationID : nil,
                            included: jsonText(["message_id": message.id, "conversation": conversationID, "sender": sender, "text": message.text, "sent": Int(message.date.timeIntervalSince1970 * 1000),
                                                "attachments": message.attachments.count]),
                            preview: String(message.text.prefix(160)))
    }

    func reportTarget(page: JamPageInfo) -> ReportTarget {
        ReportTarget(kind: "jam", ids: [page.jamId, page.writerId], noun: "jam", personName: teacherName(page.writerId), blockConversationID: blockChat(for: page.writerId),
                     included: jsonText(["jam_id": page.jamId, "writer": page.writerId, "title": page.title, "about": page.about]), preview: page.title)
    }

    /// Sends the report (sealed on this phone, see core `send_report`); with "Also block", blocks the person's chat. True when it was sent.
    func sendReport(_ target: ReportTarget, reason: ReportReason, note: String, include: Bool, alsoBlock: Bool) async -> Bool {
        #if DEBUG
        if isDemo { Self.demoReports.append((target.kind, reason.rawValue, note, include)); if alsoBlock, let chat = target.blockConversationID { await block(chat) }; return true }
        #endif
        guard let core, let link, let token = try? await link.token() else { return false }
        let input = ReportInput(subjectKind: target.kind, subjectIds: target.ids, reason: reason.rawValue, note: String(note.prefix(500)), included: include ? target.included : "")
        let sent = (try? await Task.detached { try core.sendReport(transport: link.transport, authToken: token, report: input); return true }.value) ?? false
        if sent, alsoBlock, let chat = target.blockConversationID { await block(chat) }
        return sent
    }

    #if DEBUG
    nonisolated(unsafe) static var demoReports: [(kind: String, reason: String, note: String, included: Bool)] = []
    #endif
}
