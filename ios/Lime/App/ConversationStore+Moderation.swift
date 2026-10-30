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
    /// A group report (LIME-256): what the reporter may choose to include.
    var group: GroupReportDraft?
}

/// One message of a group, as the report sheet lists it.
struct GroupReportMessage: Identifiable, Equatable {
    let id: String
    let senderID: String
    let senderName: String
    let text: String
    let sent: Int
    let attachments: Int
}

struct GroupReportMember: Equatable {
    let userID: String
    let name: String
    let role: String
}

/// What a group report can carry (LIME-256, DESIGN-24): the last 20 messages the reporter can see (each can be left out), the group's name and photo, and, only
/// if asked, who is in it.
struct GroupReportDraft: Equatable {
    let conversationID: String
    let name: String
    let hasPhoto: Bool
    let messages: [GroupReportMessage]
    let members: [GroupReportMember]

    /// The report's `ids` and `included` for the choices made. The sealed report stays under the server's 96 KB cap: when the messages are too long the oldest
    /// ones are cut short and the report says `trimmed`.
    func payload(sending ticked: Set<String>, nameAndPhoto: Bool, withMembers: Bool) -> (ids: [String], included: String) {
        let chosen = messages.filter { ticked.contains($0.id) }
        var limit = 2_000
        var rows: [[String: Any]] = []
        var trimmed = false
        var text = ""
        repeat {
            rows = chosen.map { m in
                let cut = m.text.count > limit
                if cut { trimmed = true }
                return ["id": m.id, "sender": m.senderID, "sender_name": m.senderName, "text": cut ? String(m.text.prefix(limit)) : m.text, "sent": m.sent, "attachments": m.attachments]
            }
            var object: [String: Any] = ["conversation": conversationID, "messages": rows]
            if nameAndPhoto { object["name"] = name; object["photo"] = hasPhoto ? "has a photo" : "none" }
            if withMembers { object["members"] = members.map { ["user_id": $0.userID, "name": $0.name, "role": $0.role] } }
            if trimmed { object["trimmed"] = true }
            text = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if text.utf8.count <= 90_000 { break }
            limit /= 2
        } while limit >= 50
        var senders: [String] = []
        for m in chosen where !m.senderID.isEmpty && !senders.contains(m.senderID) { senders.append(m.senderID) }
        // The core takes at most 8 ids: the group and its first seven senders (all of them are in the included text).
        return ([conversationID] + senders.prefix(7), text)
    }
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
        // A post that is open to everyone (or has a Preview) also has a public copy: "open" in the ids lets the moderators hide that too (LIME-210h).
        let hasOpenCopy = post.audience == "everyone" || post.markdown.contains("[[freewall]]")
        return ReportTarget(kind: "jam_post", ids: [post.postId, post.jamId, post.author] + (blob.isEmpty ? [] : [blob]) + (hasOpenCopy ? ["open"] : []), noun: "post", personName: who, blockConversationID: blockChat(for: post.author),
                            included: jsonText(["post_id": post.postId, "blob_id": blob, "jam_id": post.jamId, "author": post.author, "title": post.title, "subtitle": post.subtitle,
                                                "text": post.markdown, "created": post.created, "kind": post.kind]),
                            preview: String(words.prefix(160)), group: nil)
    }

    /// An open post (LIME-210h): the same kind as any jam post, the post's id first (the id the server's `hide_open_post` acts on) and "open" in the place of the
    /// blob, so the moderators' tool offers "Hide open post". "Include" sends the open row as this phone fetched and verified it.
    func reportTarget(openPost post: OpenPostInfo) -> ReportTarget {
        let who = teacherName(post.authorId)
        let words = [post.title, post.subtitle, post.plain].filter { !$0.isEmpty }.joined(separator: "\n")
        return ReportTarget(kind: "jam_post", ids: [post.postId, post.jamId, post.authorId, "open"], noun: "post", personName: who, blockConversationID: blockChat(for: post.authorId),
                            included: jsonText(["post_id": post.postId, "open": true, "jam_id": post.jamId, "author": post.authorId, "title": post.title, "subtitle": post.subtitle,
                                                "text": post.markdown, "created": post.created, "kind": post.kind, "version": Int(post.version), "preview": post.previewOf != nil]),
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

    /// Report a group (LIME-256): the last 20 messages with text that I can see, the name and photo, and the people (off by default).
    func reportTarget(group conversationID: String, name: String, hasPhoto: Bool, members: [GroupMemberInfo]) -> ReportTarget {
        let me = meProvider().id
        let messages = (conversation(conversationID)?.messages ?? []).filter { $0.state != .system && !$0.deleted && !$0.text.isEmpty }.suffix(20).map { m -> GroupReportMessage in
            let sender = m.senderID ?? me
            return GroupReportMessage(id: m.id, senderID: sender, senderName: sender == me ? meProvider().name : teacherName(sender), text: m.text, sent: Int(m.date.timeIntervalSince1970 * 1000), attachments: m.attachments.count)
        }
        let draft = GroupReportDraft(conversationID: conversationID, name: name, hasPhoto: hasPhoto, messages: Array(messages),
                                     members: members.map { GroupReportMember(userID: $0.userId, name: $0.isMe ? meProvider().name : $0.name, role: $0.role) })
        return ReportTarget(kind: "group", ids: [conversationID], noun: "group", personName: nil, blockConversationID: nil, included: "", preview: name, group: draft)
    }

    func reportTarget(page: JamPageInfo) -> ReportTarget {
        ReportTarget(kind: "jam", ids: [page.jamId, page.writerId], noun: "jam", personName: teacherName(page.writerId), blockConversationID: blockChat(for: page.writerId),
                     included: jsonText(["jam_id": page.jamId, "writer": page.writerId, "title": page.title, "about": page.about]), preview: page.title)
    }

    /// Sends the report (sealed on this phone, see core `send_report`); with "Also block", blocks the person's chat. True when it was sent.
    func sendReport(_ target: ReportTarget, reason: ReportReason, note: String, include: Bool, alsoBlock: Bool) async -> Bool {
        #if DEBUG
        if isDemo { Self.demoLastIncluded = include ? target.included : ""; Self.demoReports.append((target.kind, reason.rawValue, note, include, target.ids)); if alsoBlock, let chat = target.blockConversationID { await block(chat) }; return true }
        #endif
        guard let core, let link, let token = try? await link.token() else { return false }
        let input = ReportInput(subjectKind: target.kind, subjectIds: target.ids, reason: reason.rawValue, note: String(note.prefix(500)), included: include ? target.included : "")
        let sent = (try? await Task.detached { try core.sendReport(transport: link.transport, authToken: token, report: input); return true }.value) ?? false
        if sent, alsoBlock, let chat = target.blockConversationID { await block(chat) }
        return sent
    }

    #if DEBUG
    nonisolated(unsafe) static var demoLastIncluded = ""
    nonisolated(unsafe) static var demoReports: [(kind: String, reason: String, note: String, included: Bool, ids: [String])] = []
    #endif
}

// MARK: Deleting my account (LIME-113)

extension ConversationStore {
    /// After the server marked the account "deleting": one quiet notice to contacts, group members and jam subscribers; groups are left. Best effort.
    func sendAccountDeletedNotices() async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core, let link, let token = try? await link.token() else { return }
        _ = try? await Task.detached { try core.sendAccountDeletedNotices(transport: link.transport, authToken: token) }.value
    }

    /// Reads the people who deleted their account (their chats are read-only).
    func refreshDeletedPeers() {
        #if DEBUG
        if isDemo { return }
        #endif
        deletedPeers = Set((try? core?.deletedPeers()) ?? [])
    }
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
