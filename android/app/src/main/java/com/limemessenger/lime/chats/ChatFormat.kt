package com.limemessenger.lime.chats

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import uniffi.lime_core.AttachmentInfo
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.MessageItem

// ANDROID DEBT: twin of ios/Lime/Model/MessageFormat.swift (listTime, day, clock: they follow the phone's locale and time zone, so they stay here);
// the words of attachments, the list-row preview, the offline copy, the badge and the avatar tone are the core's (LIME-400: chat_words_rules.rs)

/** Times as the lists and chats show them. */
object MessageFormat {
    fun clock(ms: Long, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String =
        DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).format(Instant.ofEpochMilli(ms).atZone(zone))

    /** Messages list: the time today, "Yesterday", else the date ("Nov 8"). Empty when there is no time. */
    fun listTime(ms: Long?, nowMs: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        if (ms == null || ms <= 0) return ""
        val date = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
        val today = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
        return when (date) {
            today -> clock(ms, zone, locale)
            today.minusDays(1) -> "Yesterday"
            else -> DateTimeFormatter.ofPattern("MMM d", locale).format(date)
        }
    }

    /** Chat date separators: "Today", "Yesterday", else "Tuesday, Nov 3". */
    fun day(ms: Long, nowMs: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        val date: LocalDate = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
        val today = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
        return when (date) {
            today -> "Today"
            today.minusDays(1) -> "Yesterday"
            else -> DateTimeFormatter.ofPattern("EEEE, MMM d", locale).format(date)
        }
    }
}

/** What a chat list or a notification says for a message that is only attachments: the core's `attachment_summary` / `attachment_symbol` (LIME-400). */
object AttachmentFormat {
    /** "0:07", "1:23" (the core's rule, `voice_clock`). */
    fun voiceClock(seconds: Double): String = uniffi.lime_core.voiceClock(seconds)

    fun summary(items: List<AttachmentInfo>): String? = uniffi.lime_core.attachmentSummary(items)

    fun symbol(items: List<AttachmentInfo>): uniffi.lime_core.AttachmentSymbol? = uniffi.lime_core.attachmentSymbol(items)
}

/**
 * What a row of the Messages list says about the newest thing in a conversation (a reply included), in parts so it can be drawn with a small symbol: the core's
 * `list_preview_parts` (LIME-400). `rootOf` finds the message the newest reply answers.
 */
data class ListPreview(
    /** "Jean: " (a group message, or a reply in a group), "You: " (mine in a reply or a group), or nothing. */
    val prefix: String = "",
    val symbol: uniffi.lime_core.AttachmentSymbol? = null,
    val text: String = "",
    /** For reply activity: what it answers, "Reply to Jean · Who can cover recess duty?" (shown above the reply, with a quote bar). */
    val quote: String? = null,
    val isReaction: Boolean = false,
) {
    /** The words of the second line (the reply itself; for a reaction, the whole sentence). */
    val body: String get() = prefix + text
    val plain: String get() = (quote?.let { "$it\n" } ?: "") + body

    companion object {
        /** (`plainText` is kept for the callers' sake: the core turns the markup into words itself.) */
        @Suppress("UNUSED_PARAMETER")
        fun make(conversation: ConversationSummary, plainText: (String) -> String = { it }, rootOf: (String) -> MessageItem? = { null }): ListPreview {
            val root = if (conversation.lastIsReply) conversation.lastMessage?.threadRoot?.let(rootOf) else null
            val parts = uniffi.lime_core.listPreviewParts(conversation, root)
            // A call is a message whose body is JSON: the row says what the chat's bubble says ("Voice call · 4:12", "Missed voice call").
            val last = conversation.lastMessage
            val call = if (last != null && last.id.startsWith("call:") && !conversation.lastIsReply) uniffi.lime_core.callBubbleFromBody(last.text, last.isOwn) else null
            if (call != null) return ListPreview("", null, call.summary, null, false)
            return ListPreview(parts.prefix, parts.symbol, parts.text, parts.quote, parts.isReaction)
        }
    }
}

/** The offline banner on Messages and what it promises (LIME-142): the core's words. */
object OfflineCopy {
    val SHEET_TITLE: String get() = uniffi.lime_core.offlineSheetTitle()
    fun banner(meshOn: Boolean) = uniffi.lime_core.offlineBannerWords(meshOn)
}

/** The unread rules are the core's (`list_rules.rs`): a chat marked unread by hand counts as 1. */
val ConversationSummary.isUnread: Boolean get() = uniffi.lime_core.conversationIsUnread(unread, markedUnread)
val ConversationSummary.unreadCount: Int get() = uniffi.lime_core.conversationUnreadCount(unread, markedUnread).toInt()
val ConversationSummary.isRequest: Boolean get() = requestState == "pending"

/** "99+" past 99 (the core's words). */
fun badgeText(count: Int): String = uniffi.lime_core.badgeWords(count.toUInt())

/** The one place a person's avatar colour is worked out: from their user id (the core's `avatar_tone_of`, the rule it uses when it names a conversation's people). */
object AvatarTone {
    fun tone(id: String): Int = uniffi.lime_core.avatarToneOf(id).toInt()
}
