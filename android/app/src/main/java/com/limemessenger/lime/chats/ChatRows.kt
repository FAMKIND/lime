package com.limemessenger.lime.chats

import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import uniffi.lime_core.MessageItem

// ANDROID DEBT: twin of ios/Lime/Model/ChatRows.swift (the grouping: it draws the day separators with the phone's locale, so it stays here);
// the words of a message's delivery state and what TalkBack says for a message are the core's (LIME-400: message_speech_rules.rs)

/** A message as the chat reads it: the core's `local_state` mapped to what the bubble says. */
enum class DeliveryState(val raw: String) {
    Sending("sending"), Sent("sent"), Failed("failed"), Undelivered("undelivered"), Received("received"),
    Waiting("waiting"), Passed("passed"), Offline("offline"), System("system");

    /** Not sent to the server yet, and nothing wrong: the message is on its way by itself. */
    val isInFlight: Boolean get() = this == Sending || this == Waiting || this == Passed || this == Offline

    /** The words under the bubble for the nearby-phone states (colour is never the only signal): the core's. */
    val statusWords: String? get() = uniffi.lime_core.deliveryStateStatusWords(raw)

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

/** What TalkBack says for one message as one element (LIME-130-3a): "<Sender or You>, <text or kind>, <time>, <edited>, <delivery state>, <reactions>, <replies>": the core's `message_speech_label`. */
object MessageSpeech {
    /** `senderName` is the other person's name (null for my own messages, who read as "You"). `plainText` is kept for the callers' sake (the core reads the markup itself). */
    @Suppress("UNUSED_PARAMETER")
    fun label(
        message: MessageItem, senderName: String?, replyCount: Int = 0, unreplied: Int = 0, plainText: (String) -> String = { it },
        clock: (Long) -> String = { MessageFormat.clock(it) },
    ): String = uniffi.lime_core.messageSpeechLabel(message, senderName, replyCount.toUInt(), unreplied.toUInt(), clock(message.sentAt))

    /** "Photo", "Photo: <description>", "3 photos", "Voice message", "File: report.pdf" … (a photo reads with its description). */
    fun attachments(message: MessageItem): String = uniffi.lime_core.messageSpeechAttachments(message)
}
