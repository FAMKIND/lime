package com.limemessenger.lime.chats

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.limemessenger.lime.auth.ConnectionProblem
import com.limemessenger.lime.net.HttpTransport
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.LimeStore

// ANDROID DEBT: twin of the sync + reload parts of ios/Lime/App/ConversationStore.swift (syncNow, reload, chats/requests); moves into LimeCore in LIME-133

/**
 * The Messages list's state: the conversations from the core, kept fresh from the backend (as iOS's `ConversationStore`). The core orders the
 * list (pinned first, then newest activity); this only reads it, syncs, and says why a sync failed.
 */
class ChatsModel(
    private val store: () -> LimeStore?,
    private val transport: () -> HttpTransport?,
    /** A fresh access token (refreshes when due); throws when the session cannot refresh. */
    private val token: suspend () -> String,
    /** The token held now, expired or not (sending with no internet). */
    private val staleToken: () -> String,
    /** Registers this device again when it is not linked (a phone that started offline). */
    private val registrar: suspend () -> Unit = {},
    private val isRegistered: () -> Boolean = { true },
) {
    var conversations by mutableStateOf<List<ConversationSummary>>(emptyList())
        private set
    var isLoaded by mutableStateOf(false)
        private set
    var problem by mutableStateOf<ConnectionProblem?>(null)
        private set
    var unreadOnly by mutableStateOf(false)

    /** Bumped every time the conversations are read again: an open chat reads its messages again when it changes. */
    var revision by mutableStateOf(0)
        private set

    /** The link and a bearer token for screens that talk to the backend themselves (a lookup, a photo download). */
    fun transportOrNull(): HttpTransport? = transport()
    suspend fun bearer(): String = try { token() } catch (e: CancellationException) { throw e } catch (e: Exception) { staleToken() }

    /** The open store, for the chat screens that read their own messages. */
    fun core(): LimeStore? = store()

    private var syncing = false
    private var syncAgain = false

    /** Accepted conversations (the Messages list) and strangers' first messages (the Requests list). */
    val chats: List<ConversationSummary> get() = conversations.filter { !it.isRequest }
    val requests: List<ConversationSummary> get() = conversations.filter { it.isRequest }

    /** The chats after the All | Unread segment. */
    val shownChats: List<ConversationSummary> get() = if (unreadOnly) chats.filter { it.isUnread } else chats

    val unreadChatCount: Int get() = chats.count { it.isUnread }

    suspend fun reload() {
        val core = store() ?: return
        try {
            conversations = withContext(Dispatchers.IO) { core.listConversations() }
            revision++
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Storage could not be read: keep what is shown.
        }
        isLoaded = true
    }

    /** Sends what is queued, fetches the mailbox, and reads the list again. A second call while one runs makes it run once more. */
    suspend fun syncNow() {
        if (!isRegistered()) registrar()
        val core = store()
        val link = transport()
        if (core == null || link == null) { reload(); return }
        if (syncing) { syncAgain = true; return }
        syncing = true
        try {
            do {
                syncAgain = false
                try {
                    // With no internet the token cannot be refreshed: a message that can travel through nearby phones does not need one.
                    val bearer = try { token() } catch (e: CancellationException) { throw e } catch (e: Exception) { staleToken() }
                    // Sends first (they keep their order); a failure leaves them "Not sent" for a retry.
                    withContext(Dispatchers.IO) { runCatching { core.deliverQueued(link, bearer) } }
                    withContext(Dispatchers.IO) { core.sync(link, bearer) }
                    problem = null
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    problem = ConnectionProblem.from(e)
                }
                reload()
            } while (syncAgain)
        } finally {
            syncing = false
        }
    }

    suspend fun pullToRefresh() = syncNow()

    /** Sends what is queued (a message that failed is retried here). */
    suspend fun deliverNow() {
        val core = store() ?: return
        val link = transport() ?: run { reload(); return }
        try {
            val bearer = try { token() } catch (e: CancellationException) { throw e } catch (e: Exception) { staleToken() }
            withContext(Dispatchers.IO) { core.deliverQueued(link, bearer) }
            problem = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // A key change is shown in the chat itself; everything else on Messages.
            if (e !is uniffi.lime_core.StoreException.KeyMismatch) problem = ConnectionProblem.from(e)
        }
        reload()
    }

    /** "Accept" on a stranger's first message: it moves from Requests to the list. */
    suspend fun acceptRequest(conversationId: String) {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.acceptRequest(conversationId) } }
        reload()
    }

    /** Opening a chat reads it (iOS marks it read in `open`): the unread badge clears when the list is read again. */
    suspend fun markRead(conversationId: String) {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.markRead(conversationId) } }
        reload()
    }

    /** While the app is in front: sync now and then every [intervalMs] (iOS listens for a realtime nudge; Android polls until push exists). */
    suspend fun runWhileForeground(intervalMs: Long = FOREGROUND_INTERVAL_MS) {
        while (true) {
            syncNow()
            delay(intervalMs)
        }
    }

    companion object {
        const val FOREGROUND_INTERVAL_MS = 5_000L
    }
}
