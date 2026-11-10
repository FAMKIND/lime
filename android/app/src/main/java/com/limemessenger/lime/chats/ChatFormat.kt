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

// ANDROID DEBT: twin of ios/Lime/Model/MessageFormat.swift (listTime, day, clock), ios/Lime/Features/Attachments/AttachmentModels.swift (AttachmentFormat)
// and ios/Lime/Features/Messages/MessagesView.swift (ListPreview); moves into LimeCore in LIME-133

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

/** What a chat list or a notification says for a message that is only attachments: "Photo", "3 Photos", "Video", "Voice message (0:12)", the file's name. */
object AttachmentFormat {
    private fun isImage(a: AttachmentInfo) = a.mime.startsWith("image/")
    private fun isVideo(a: AttachmentInfo) = a.mime.startsWith("video/")
    private fun isAudio(a: AttachmentInfo) = a.mime.startsWith("audio/")

    /** "0:07", "1:23" (the core's rule, `voice_clock`). */
    fun voiceClock(seconds: Double): String = uniffi.lime_core.voiceClock(seconds)

    fun summary(items: List<AttachmentInfo>): String? {
        val first = items.firstOrNull() ?: return null
        if (items.all(::isImage)) return if (items.size == 1) "Photo" else "${items.size} Photos"
        if (items.size == 1) {
            return when {
                isVideo(first) -> "Video"
                isAudio(first) -> first.durationMs?.let { "Voice message (${voiceClock(it.toLong() / 1000.0)})" } ?: "Voice message"
                else -> first.name.ifEmpty { "File" }
            }
        }
        return "${items.size} attachments"
    }

    enum class Symbol { Camera, Video, Mic, Document, Paperclip }

    fun symbol(items: List<AttachmentInfo>): Symbol? {
        val first = items.firstOrNull() ?: return null
        if (items.size > 1 && !items.all(::isImage)) return Symbol.Paperclip
        return when {
            isImage(first) -> Symbol.Camera
            isVideo(first) -> Symbol.Video
            isAudio(first) -> Symbol.Mic
            else -> Symbol.Document
        }
    }
}

/**
 * What a row of the Messages list says about the newest thing in a conversation (a reply included), in parts so it can be drawn with a
 * small symbol and tested without a screen. `plainText` turns a message's markup into words (the core's `messagePlainText`).
 */
data class ListPreview(
    /** "Jean: " (a group message, or a reply in a group), "You: " (mine in a reply or a group), or nothing. */
    val prefix: String = "",
    val symbol: AttachmentFormat.Symbol? = null,
    val text: String = "",
    /** For reply activity: what it answers, "Reply to Jean · Who can cover recess duty?" (shown above the reply, with a quote bar). */
    val quote: String? = null,
    val isReaction: Boolean = false,
) {
    /** The words of the second line (the reply itself; for a reaction, the whole sentence). */
    val body: String get() = prefix + text
    val plain: String get() = (quote?.let { "$it\n" } ?: "") + body

    companion object {
        private fun firstName(name: String) = name.trim().split(" ").firstOrNull().orEmpty()

        private fun nameOf(message: MessageItem, conversation: ConversationSummary): String? {
            if (message.senderId == null) return "You"
            return conversation.members.firstOrNull { it.id == message.senderId }?.let { firstName(it.name) }
        }

        fun gist(message: MessageItem, plainText: (String) -> String): String {
            if (message.deleted) return "This message was deleted"
            val words = plainText(message.text).replace("\n", " ").trim()
            if (words.isNotEmpty()) return words
            return AttachmentFormat.summary(message.attachments).orEmpty()
        }

        fun make(conversation: ConversationSummary, plainText: (String) -> String, rootOf: (String) -> MessageItem? = { null }): ListPreview {
            // A reaction newer than the last message is the newest thing: "Jean reacted ❤️ to “True that”".
            conversation.lastReaction?.let { reaction ->
                val who = if (reaction.reactorId == null) "You" else firstName(reaction.reactorName)
                val gist = reaction.text.trim()
                val tail = if (gist.isEmpty()) "a message" else "“$gist”"
                return ListPreview(text = "$who reacted ${reaction.emoji} to $tail", isReaction = true)
            }
            val last = conversation.lastMessage ?: return ListPreview()
            if (last.localState == "system") return ListPreview(text = last.text)
            if (last.deleted) return ListPreview(text = "This message was deleted")
            var prefix = ""
            var quote: String? = null
            val sender = nameOf(last, conversation)
            if (conversation.lastIsReply) {
                // Reply activity reads like a quote: what it answers, then the reply.
                val root = last.threadRoot?.let(rootOf)
                val author = root?.let { nameOf(it, conversation) }
                quote = if (root != null && author != null) {
                    val gist = gist(root, plainText)
                    val who = if (author == "You") "you" else author
                    if (gist.isEmpty()) "Reply to $who" else "Reply to $who · $gist"
                } else "Reply in a thread"
                if ((last.senderId == null || conversation.isGroup) && sender != null) prefix = "$sender: "
            } else if (conversation.isGroup && last.senderId != null && sender != null) {
                prefix = "$sender: "
            }
            // The words, without the markup (a list reads as its items).
            val words = plainText(last.text).replace("\n", " ")
            val summary = AttachmentFormat.summary(last.attachments)
            return if (summary != null) {
                ListPreview(prefix, AttachmentFormat.symbol(last.attachments), if (words.isEmpty()) summary else "$summary · $words", quote)
            } else ListPreview(prefix, null, words, quote)
        }
    }
}

/** The offline banner on Messages and what it promises (LIME-142). Pure words. */
object OfflineCopy {
    const val WITH_MESH = "Offline · sending through nearby phones"
    const val WITHOUT_MESH = "Offline · will send when you’re online"
    const val SHEET_TITLE = "No internet"
    fun banner(meshOn: Boolean) = if (meshOn) WITH_MESH else WITHOUT_MESH
}

/** The unread rules are the core's (`list_rules.rs`): a chat marked unread by hand counts as 1. */
val ConversationSummary.isUnread: Boolean get() = uniffi.lime_core.conversationIsUnread(unread, markedUnread)
val ConversationSummary.unreadCount: Int get() = uniffi.lime_core.conversationUnreadCount(unread, markedUnread).toInt()
val ConversationSummary.isRequest: Boolean get() = requestState == "pending"

/** "99+" past 99. */
fun badgeText(count: Int): String = if (count > 99) "99+" else count.toString()

// ANDROID DEBT: twin of ios/Lime/Model/Models.swift `AvatarTone`; moves into LimeCore in LIME-133
/** The one place a person's avatar colour is worked out: from their user id, with the same rule LimeCore uses when it names a conversation's people. */
object AvatarTone {
    fun tone(id: String): Int {
        var hash = 0L
        for (byte in id.toByteArray(Charsets.UTF_8)) hash = (hash * 31 + (byte.toLong() and 0xFF)) and 0xFFFFFFFFL
        return (hash % 8).toInt()
    }
}
