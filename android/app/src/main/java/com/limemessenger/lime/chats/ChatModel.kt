package com.limemessenger.lime.chats

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.limemessenger.lime.BuildConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.MessageItem

// ANDROID DEBT: twin of the open-chat parts of ios/Lime/App/ConversationStore.swift (sendNow, resend, the reply state); moves into LimeCore in LIME-133

/** One open chat: its messages from the core, sending (plain text; replies hang from a root), retrying, and marking it read. */
class ChatModel(val conversationId: String, private val chats: ChatsModel, private val accountSignedIn: Boolean = true) {
    var messages by mutableStateOf<List<MessageItem>>(emptyList())
        private set
    /** Replies per root message (thread summaries), for the "N replies" row. */
    var replyCounts by mutableStateOf<Map<String, Int>>(emptyMap())
        private set
    var replyingTo by mutableStateOf<MessageItem?>(null)
    var banner by mutableStateOf<String?>(null)
        private set

    val summary: ConversationSummary? get() = chats.conversations.firstOrNull { it.id == conversationId }

    suspend fun reload() {
        val core = chats.core() ?: return
        try {
            withContext(Dispatchers.IO) {
                messages = core.listMessages(conversationId)
                replyCounts = core.listThreadSummaries(conversationId).associate { it.rootId to it.replyCount.toInt() }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Keep what is shown.
        }
    }

    /** Opening a chat, and anything that arrives while it is open, reads it. */
    suspend fun markRead() {
        if (summary?.let { it.unread > 0u || it.markedUnread } == true) chats.markRead(conversationId)
    }

    /** The text as typed; nothing is sent for blank text. Queued at once (it shows as "Sending…"), then delivered. */
    suspend fun send(text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        val core = chats.core() ?: return
        val root = replyingTo?.id
        val queued = try {
            withContext(Dispatchers.IO) {
                // A signed-in account never makes a local-only message: it is queued (and sent when a link exists). Only a store with no account (tests) keeps one locally.
                if (root != null) core.queueReply(conversationId, root, trimmed)
                else if (accountSignedIn) core.queueText(conversationId, trimmed)
                else core.sendLocalMessage(conversationId, trimmed)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            banner = "Couldn’t queue the message. Try again." + (if (BuildConfig.DEBUG) " (${e::class.simpleName})" else "")
            return
        }
        replyingTo = null
        banner = null
        if (root == null) messages = messages + queued
        chats.deliverNow()
        reload()
    }

    suspend fun resend(messageId: String) {
        val core = chats.core() ?: return
        withContext(Dispatchers.IO) { runCatching { core.retryMessage(messageId) } }
        reload()
        chats.deliverNow()
        reload()
    }

    /** The replies of one thread (read-only tonight). */
    suspend fun thread(rootId: String): List<MessageItem> =
        withContext(Dispatchers.IO) { runCatching { chats.core()?.listThread(rootId) }.getOrNull().orEmpty() }
}
