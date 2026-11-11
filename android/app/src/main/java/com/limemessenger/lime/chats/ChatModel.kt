package com.limemessenger.lime.chats

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.limemessenger.lime.BuildConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.AttachmentInfo
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.MessageItem
import uniffi.lime_core.OutgoingAttachment

// ANDROID DEBT: twin of the open-chat parts of ios/Lime/App/ConversationStore.swift (sendNow, resend, the reply state); moves into LimeCore in LIME-133

/** One open chat: its messages from the core, sending (plain text; replies hang from a root), retrying, and marking it read. */
class ChatModel(
    val conversationId: String, val chats: ChatsModel, private val accountSignedIn: Boolean = true,
    /** May this file be fetched by itself (the person's download choices and the network: `MediaPolicy`)? A tap on it fetches it anyway. */
    private val mayAutoDownload: (AttachmentInfo) -> Boolean = { true },
) {
    var messages by mutableStateOf<List<MessageItem>>(emptyList())
        private set
    /** Replies per root message (thread summaries), for the "N replies" row. */
    var replyCounts by mutableStateOf<Map<String, Int>>(emptyMap())
        private set
    var replyingTo by mutableStateOf<MessageItem?>(null)
    var banner by mutableStateOf<String?>(null)
        private set

    /** The picture to draw for each image attachment: its tiny preview at first, the real picture once this phone has it. */
    val images = mutableStateMapOf<String, ImageBitmap>()
    private val full = mutableSetOf<String>()
    private val loading = mutableSetOf<String>()

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

    /** Sends photos (processed by [AttachmentProcessing]) with an optional caption, as a reply in a thread when one is being replied to. */
    /** Tests: sees what the composer hands over instead of the core queueing it (a test store has no account to send from); true = taken. */
    var outgoingHook: ((List<OutgoingAttachment>, String) -> Boolean)? = null

    /** A message with a link card (LIME-407): the card (built on this phone) goes sealed inside the message through the core's `queue_text_with_preview`, never as a separate upload or request. */
    var previewHook: ((String, uniffi.lime_core.OutgoingPreview) -> Boolean)? = null   // tests: what would be queued

    suspend fun sendWithPreview(text: String, preview: uniffi.lime_core.OutgoingPreview) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        if (previewHook?.invoke(trimmed, preview) == true) return
        val core = chats.core() ?: return
        val root = replyingTo?.id
        val queued = try {
            withContext(Dispatchers.IO) { core.queueTextWithPreview(conversationId, trimmed, root, preview) }
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

    suspend fun sendPhotos(items: List<OutgoingAttachment>, caption: String, what: String = "photo") {
        if (items.isEmpty()) return
        if (outgoingHook?.invoke(items, caption) == true) return
        val core = chats.core() ?: return
        val root = replyingTo?.id
        val queued = try {
            withContext(Dispatchers.IO) { core.sendAttachments(conversationId, caption.trim(), items, root) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            banner = "Couldn’t queue the $what. Try again." + (if (BuildConfig.DEBUG) " (${e::class.simpleName})" else "")
            return
        }
        replyingTo = null
        banner = null
        if (root == null) messages = messages + queued
        chats.deliverNow()
        reload()
    }

    /**
     * The picture of an image attachment: the tiny preview straight away, then the real one, downloading and decrypting it first when this
     * phone does not have it yet (iOS `image(for:)`; pictures download by themselves, files wait for a tap).
     */
    suspend fun loadImage(attachment: AttachmentInfo, userRequested: Boolean = false) {
        val id = attachment.id
        if (id in full || !loading.add(id)) return
        try {
            if (id !in images && attachment.thumb.isNotEmpty()) {
                AttachmentProcessing.decodeForDisplay(attachment.thumb, 64)?.let { images[id] = it.asImageBitmap() }
            }
            val core = chats.core() ?: return
            var data = withContext(Dispatchers.IO) { runCatching { core.attachmentData(id) }.getOrNull() }
            if (data == null && !attachment.removed) {
                if (!userRequested && !mayAutoDownload(attachment)) return
                val link = chats.transportOrNull() ?: return
                val bearer = chats.bearer()
                val fetched = withContext(Dispatchers.IO) { runCatching { core.downloadAttachment(link, bearer, id) }.isSuccess }
                if (fetched) data = withContext(Dispatchers.IO) { runCatching { core.attachmentData(id) }.getOrNull() }
            }
            if (data != null) {
                val bitmap = withContext(Dispatchers.Default) { AttachmentProcessing.decodeForDisplay(data, DISPLAY_EDGE) }
                if (bitmap != null) { images[id] = bitmap.asImageBitmap(); full += id }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // The preview stays; it is tried again next time the chat opens.
        } finally {
            loading.remove(id)
        }
    }

    /** Sends a recorded voice message: an m4a with its length, and its 64 loudness bars in the preview slot (as iOS). */
    suspend fun sendVoice(note: VoiceNote) = sendPhotos(
        listOf(OutgoingAttachment(note.bytes, "Voice message.m4a", "audio/mp4", null, null, note.durationMs.toUInt(), note.waveform, ByteArray(0), "")), "", "voice message",
    )

    /** The decrypted bytes of an attachment only if this phone already has them (no download): a GIF that plays in its bubble. */
    suspend fun localBytes(attachment: AttachmentInfo): ByteArray? {
        val core = chats.core() ?: return null
        return withContext(Dispatchers.IO) { runCatching { core.attachmentData(attachment.id) }.getOrNull() }
    }

    /** The decrypted bytes of a file or voice message: what this phone has, else downloaded now (voice always; a tap for the rest). Null when it cannot be had. */
    suspend fun attachmentBytes(attachment: AttachmentInfo): ByteArray? {
        val core = chats.core() ?: return null
        var data = withContext(Dispatchers.IO) { runCatching { core.attachmentData(attachment.id) }.getOrNull() }
        if (data == null && !attachment.removed) {
            val link = chats.transportOrNull() ?: return null
            val bearer = chats.bearer()
            val fetched = withContext(Dispatchers.IO) { runCatching { core.downloadAttachment(link, bearer, attachment.id) }.isSuccess }
            if (fetched) data = withContext(Dispatchers.IO) { runCatching { core.attachmentData(attachment.id) }.getOrNull() }
        }
        reload()
        return data
    }

    /** Runs a core change on this chat (a reaction, an edit, a delete, a forward), then reads everything again and sends what was queued. False when the core refused. */
    internal suspend fun mutate(block: (uniffi.lime_core.LimeStore) -> Unit): Boolean {
        val core = chats.core() ?: return false
        val ok = withContext(Dispatchers.IO) { runCatching { block(core) }.isSuccess }
        chats.reload()
        reload()
        chats.deliverNow()
        reload()
        return ok
    }

    companion object {
        /** Pictures are decoded at most this big for the screen (the original stays in the store). */
        const val DISPLAY_EDGE = 1600
    }
}
