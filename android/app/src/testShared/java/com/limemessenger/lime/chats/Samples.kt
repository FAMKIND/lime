package com.limemessenger.lime.chats

import uniffi.lime_core.AttachmentInfo
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.MemberInfo
import uniffi.lime_core.JamInfo
import uniffi.lime_core.JamPostInfo
import uniffi.lime_core.MessageItem
import uniffi.lime_core.ReactionActivity

/** Plain-record builders for tests (the generated records have many fields). */
object Samples {
    fun member(id: String, name: String, tone: Int = 0) = MemberInfo(id, name, name.take(1), tone.toUInt(), null, null)

    fun message(
        id: String, text: String, from: String? = null, at: Long = 1_000L, state: String = "sent", conversation: String = "dm:ben",
        attachments: List<AttachmentInfo> = emptyList(), deleted: Boolean = false, threadRoot: String? = null,
    ) = MessageItem(id, conversation, from, text, at, state, attachments, false, deleted, emptyList(), false, null, threadRoot, null)

    fun attachment(mime: String, name: String = "", durationMs: Int? = null) =
        AttachmentInfo("a", mime, name, 10uL, null, null, durationMs?.toUInt(), ByteArray(0), ByteArray(0), "", "", true, false)

    fun conversation(
        id: String = "dm:ben", title: String = "Ben Android", group: Boolean = false, pinned: Boolean = false, unread: Int = 0,
        marked: Boolean = false, last: MessageItem? = null, members: List<MemberInfo> = listOf(member("ben", "Ben Android", 3)),
        reaction: ReactionActivity? = null, lastIsReply: Boolean = false, request: String = "accepted", activityAt: Long = 0,
    ) = ConversationSummary(
        activityAt, reaction, id, title, group, pinned, unread.toUInt(), request, false, last, members, null, false, null, null, null, marked, lastIsReply,
    )

    fun jam(id: String = "jam1", title: String = "Bell Ringer", mine: Boolean = false, status: String = "active", created: Long = 1_000L, ended: Boolean = false) =
        JamInfo(id, "grp:$id", "writer1", title, "", emptyList(), emptyList(), mine, status, ended, false, null, null, 0u, 0u, created)

    fun jamPost(
        id: String, jamId: String = "jam1", author: String = "writer1", at: Long = 1_000L, kind: String = "quick", title: String = "", subtitle: String = "",
        plain: String = "A short post", markdown: String = plain, coauthors: List<String> = emptyList(), displayAs: String = "person", state: String = "ready", editedAt: Long = 0L,
    ) = JamPostInfo(id, jamId, author, "free", kind, title, subtitle, markdown, plain, "[]", at, coauthors, displayAs, editedAt, "subscribers", null, emptyList(), state)
}
