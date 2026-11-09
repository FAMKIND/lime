package com.limemessenger.lime.chats

import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import uniffi.lime_core.MessageItem

// ANDROID DEBT: twin of ios/Lime/Model/ChatRows.swift and the delivery words of ios/Lime/Model/Models.swift (DeliveryState) and
// ios/Lime/Features/Chat/MessageSpeech.swift; moves into LimeCore in LIME-133

/** A message as the chat reads it: the core's `local_state` mapped to what the bubble says. */
enum class DeliveryState(val raw: String) {
    Sending("sending"), Sent("sent"), Failed("failed"), Undelivered("undelivered"), Received("received"),
    Waiting("waiting"), Passed("passed"), Offline("offline"), System("system");

    /** Not sent to the server yet, and nothing wrong: the message is on its way by itself. */
    val isInFlight: Boolean get() = this == Sending || this == Waiting || this == Passed || this == Offline

    /** The words under the bubble for the nearby-phone states (colour is never the only signal). */
    val statusWords: String? get() = when (this) {
        Waiting -> "Waiting for a phone nearby"
        Passed -> "Passed to a nearby phone"
        Offline -> "Waiting for internet"
        else -> null
    }

    companion object {
        /** LimeCore's `local_state`; the older local-only states count as sent. */
        fun of(localState: String): DeliveryState = entries.firstOrNull { it.raw == localState } ?: Sent
    }
}

val MessageItem.state: DeliveryState get() = DeliveryState.of(localState)
val MessageItem.isOwn: Boolean get() = senderId == null
val MessageItem.isSystem: Boolean get() = state == DeliveryState.System

/** A chat's day separators and messages, in order. `showAvatar` is true for the first of a run of incoming messages from one sender. */
sealed class ChatRow {
    abstract val id: String

    data class Day(override val id: String, val text: String) : ChatRow()

    /** `endsRun`: the last message of a run, where its time shows (LIME-278). */
    data class Message(val item: MessageItem, val showAvatar: Boolean, val endsRun: Boolean = true) : ChatRow() { override val id: String get() = item.id }

    /** "Jean added Lee": a line about the group, centred. */
    data class System(val item: MessageItem) : ChatRow() { override val id: String get() = item.id }

    /** Two or more deleted messages in a row, as one line: "3 messages deleted". */
    data class DeletedRun(override val id: String, val count: Int) : ChatRow()

    companion object {
        /** Messages from one sender this close together are one run. */
        const val RUN_GAP_MS = 5 * 60 * 1000L

        fun rows(messages: List<MessageItem>, nowMs: Long = java.lang.System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): List<ChatRow> {
            val result = mutableListOf<ChatRow>()
            var lastDay: java.time.LocalDate? = null
            var lastSender: Pair<Boolean, String?>? = null   // (has one, who): null = no run in progress
            for (message in messages) {
                val day = Instant.ofEpochMilli(message.sentAt).atZone(zone).toLocalDate()
                if (lastDay == null || lastDay != day) {
                    result += Day("day-${message.id}", MessageFormat.day(message.sentAt, nowMs, zone, locale))
                    lastSender = null
                }
                lastDay = day
                if (message.isSystem) {
                    result += System(message)
                    lastSender = null
                    continue
                }
                val showAvatar = !message.isOwn && lastSender != (true to message.senderId)
                result += Message(message, showAvatar)
                lastSender = true to message.senderId
            }
            return markingRunEnds(collapsingDeletedRuns(result))
        }

        /** Sets `endsRun` on every message row (a message ends its run unless the next row is a message by the same sender less than five minutes later). */
        fun markingRunEnds(rows: List<ChatRow>): List<ChatRow> = rows.mapIndexed { index, row ->
            if (row !is Message) return@mapIndexed row
            val next = rows.getOrNull(index + 1) as? Message
            if (next != null && next.item.senderId == row.item.senderId && next.item.sentAt - row.item.sentAt < RUN_GAP_MS) row.copy(endsRun = false) else row
        }

        /** Runs of two or more consecutive "This message was deleted" placeholders become one line. */
        fun collapsingDeletedRuns(rows: List<ChatRow>): List<ChatRow> {
            val out = mutableListOf<ChatRow>()
            var run = mutableListOf<ChatRow>()
            fun flush() {
                if (run.size >= 2) out += DeletedRun("deleted-run-${run.first().id}", run.size) else out += run
                run = mutableListOf()
            }
            for (row in rows) if (row is Message && row.item.deleted) run += row else { flush(); out += row }
            flush()
            return out
        }
    }
}

/** What TalkBack says for one message as one element (LIME-130-3a): "<Sender or You>, <text or kind>, <time>, <edited>, <delivery state>, <reactions>, <replies>". */
object MessageSpeech {
    /** `senderName` is the other person's name (null for my own messages, who read as "You"). */
    fun label(
        message: MessageItem, senderName: String?, replyCount: Int = 0, unreplied: Int = 0, plainText: (String) -> String,
        clock: (Long) -> String = { MessageFormat.clock(it) },
    ): String {
        val parts = mutableListOf(if (message.isOwn) "You" else (senderName ?: "Someone"))
        parts += body(message, plainText)
        if (!message.deleted) {
            parts += clock(message.sentAt)
            if (message.edited) parts += "edited"
            if (message.isOwn) stateWords(message.state)?.let { parts += it }
            if (message.reactions.isNotEmpty()) {
                val total = message.reactions.sumOf { it.count.toInt() }
                parts += "$total ${if (total == 1) "reaction" else "reactions"}: " + message.reactions.joinToString(", ") { "${it.emoji} ${it.count}${if (it.mine) " (you)" else ""}" }
            }
            if (replyCount > 0) parts += "$replyCount ${if (replyCount == 1) "reply" else "replies"}" + (if (unreplied > 0) ", $unreplied unread" else "")
        }
        return parts.joinToString(", ")
    }

    /** The words of the message, or what kind of thing it is. */
    fun body(message: MessageItem, plainText: (String) -> String): String {
        if (message.deleted) return "This message was deleted"
        if (message.emergency != null) return "Emergency status"
        val pieces = mutableListOf<String>()
        if (message.forwarded) pieces += "Forwarded"
        val text = plainText(message.text)
        if (text.isNotEmpty()) pieces += text
        if (message.attachments.isNotEmpty()) pieces += attachments(message)
        message.linkPreview?.let { pieces += "Link: ${it.title}" }
        return if (pieces.isEmpty()) "Message" else pieces.joinToString(", ")
    }

    /** "Photo", "3 photos", "Voice message", "File: report.pdf" … */
    fun attachments(message: MessageItem): String {
        val items = message.attachments
        val images = items.filter { it.mime.startsWith("image/") }
        val out = mutableListOf<String>()
        if (images.size == 1) out += if (images[0].mime == "image/gif") "GIF" else "Photo" else if (images.size > 1) out += "${images.size} photos"
        for (item in items.filter { !it.mime.startsWith("image/") }) out += when {
            item.mime.startsWith("audio/") -> "Voice message"
            item.mime.startsWith("video/") -> "Video"
            else -> if (item.name.isEmpty()) "File" else "File: ${item.name}"
        }
        return out.joinToString(", ")
    }

    /** The delivery state as words (null when it says nothing). */
    fun stateWords(state: DeliveryState): String? = when (state) {
        DeliveryState.Sending -> "sending"
        DeliveryState.Sent -> "sent"
        DeliveryState.Failed -> "not sent, retry available"
        DeliveryState.Undelivered -> "not delivered, resend available"
        DeliveryState.Waiting, DeliveryState.Passed, DeliveryState.Offline -> state.statusWords?.lowercase()
        DeliveryState.Received, DeliveryState.System -> null
    }
}
