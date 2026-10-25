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
        // The blob that holds the post now: "Hide post" in the moderators' tool hides that (an edit makes a new one).
        let blob = ((try? core?.jamPostBlobId(postId: post.postId)) ?? nil) ?? ""
        return ReportTarget(kind: "jam_post", ids: [post.postId, post.jamId, post.author] + (blob.isEmpty ? [] : [blob]), noun: "post", personName: who, blockConversationID: blockChat(for: post.author),
                            included: jsonText(["post_id": post.postId, "blob_id": blob, "jam_id": post.jamId, "author": post.author, "title": post.title, "subtitle": post.subtitle,
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

// MARK: The moderators' tool (LIME-191)

/// One line of the queue.
struct ModerationItem: Identifiable, Hashable {
    let id: String
    let kind: String
    let reason: String
    let urgent: Bool
    let status: String
    let created: Date
}

/// An opened report: what the reporter's phone sent, and what has been done since.
struct ModerationDetail {
    var item: ModerationItem
    var reporter: String
    var note: String
    var subjectIDs: [String]
    var included: String
    var readable: Bool
    var history: [(action: String, note: String, date: Date)]
}

extension ConversationStore {
    /// Calls a moderation function; nil when the phone is offline or signed out. (403 = not on the server's allow-list.)
    func moderationCall(_ function: String, _ body: [String: Any]) async -> (status: Int, json: [String: Any])? {
        guard let core, let link, let token = try? await link.token(),
              let data = try? JSONSerialization.data(withJSONObject: body), let text = String(data: data, encoding: .utf8) else { return nil }
        guard let answer = try? await Task.detached(operation: { try core.moderationRequest(transport: link.transport, authToken: token, function: function, body: text) }).value else { return nil }
        let parsed = (try? JSONSerialization.jsonObject(with: Data(answer.body.utf8))) as? [String: Any] ?? [:]
        return (Int(answer.status), parsed)
    }

    /// Whether this account is on the server's moderator list (asked once when Settings opens). Demo: only with `-lime-demo-moderator`.
    func isModerator() async -> Bool {
        #if DEBUG
        if isDemo { return ProcessInfo.processInfo.arguments.contains("-lime-demo-moderator") }
        #endif
        // Asked once per launch (not every time Settings opens): the server learns nothing more than it does from any other call.
        if let known = Self.moderatorAnswer { return known }
        let answer = await moderationCall("moderation-list", ["status": "open"])
        if let status = answer?.status { Self.moderatorAnswer = (status == 200) }
        return answer?.status == 200
    }

    nonisolated(unsafe) private static var moderatorAnswer: Bool?

    private static func date(_ text: Any?) -> Date {
        guard let text = text as? String else { return Date() }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text) ?? ISO8601DateFormatter().date(from: text) ?? Date()
    }

    private func item(_ row: [String: Any]) -> ModerationItem? {
        guard let id = row["id"] as? String, let kind = row["kind"] as? String, let reason = row["reason"] as? String else { return nil }
        return ModerationItem(id: id, kind: kind, reason: reason, urgent: row["urgent"] as? Bool ?? false, status: row["status"] as? String ?? "open", created: Self.date(row["created_at"]))
    }

    func moderationQueue(status: String) async -> [ModerationItem] {
        #if DEBUG
        if isDemo { return status == "open" ? Self.demoQueue.sorted { ($0.urgent ? 0 : 1, $0.created) < ($1.urgent ? 0 : 1, $1.created) } : [] }   // urgent first, as the server does
        #endif
        let answer = await moderationCall("moderation-list", ["status": status])
        return (answer?.json["reports"] as? [[String: Any]] ?? []).compactMap(item)
    }

    func moderationOpen(_ id: String) async -> ModerationDetail? {
        #if DEBUG
        if isDemo { return Self.demoQueue.first { $0.id == id }.map { ModerationDetail(item: $0, reporter: "demo-reporter", note: "Selling things in the comments.", subjectIDs: ["demo-post", "demo-jam", "demo-writer", "demo-blob"], included: "{\"text\": \"Buy my worksheets!\"}", readable: true, history: []) } }
        #endif
        guard let answer = await moderationCall("moderation-open", ["id": id]), answer.status == 200, let report = answer.json["report"] as? [String: Any], let row = item(report) else { return nil }
        let payload = report["payload"] as? [String: Any] ?? [:]
        var included = ""
        if let value = payload["included"], !(value is NSNull) {
            if let text = value as? String { included = text }
            else if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) { included = String(data: data, encoding: .utf8) ?? "" }
        }
        let history = (answer.json["actions"] as? [[String: Any]] ?? []).map { (action: $0["action"] as? String ?? "", note: $0["note"] as? String ?? "", date: Self.date($0["created_at"])) }
        return ModerationDetail(item: row, reporter: report["reporter"] as? String ?? "", note: payload["note"] as? String ?? "", subjectIDs: payload["subject_ids"] as? [String] ?? [],
                                included: included, readable: report["readable"] as? Bool ?? false, history: history)
    }

    /// Dismiss, Hide post, Take page down, Remove public picture, Suspend, Unsuspend. True when the server did it.
    func moderationAct(reportID: String?, action: String, target: String? = nil, slot: String? = nil, reason: String? = nil, note: String = "") async -> Bool {
        #if DEBUG
        if isDemo { Self.demoQueue.removeAll { $0.id == reportID }; return true }
        #endif
        var body: [String: Any] = ["action": action, "note": note]
        if let reportID { body["report_id"] = reportID }
        if let target { body["target"] = target }
        if let slot { body["slot"] = slot }
        if let reason { body["reason"] = reason }
        return await moderationCall("moderation-act", body)?.status == 200
    }

    #if DEBUG
    nonisolated(unsafe) static var demoQueue: [ModerationItem] = [
        ModerationItem(id: "demo-report-1", kind: "jam_post", reason: "spam", urgent: false, status: "open", created: Date().addingTimeInterval(-3600)),
        ModerationItem(id: "demo-report-2", kind: "message", reason: "child_safety", urgent: true, status: "open", created: Date().addingTimeInterval(-600)),
    ]
    #endif
}
