package com.limemessenger.lime.chats

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.IncomingWords
import uniffi.lime_core.messagePlainText
import uniffi.lime_core.notificationWords

// ANDROID DEBT: twin of the presentation part of ios/Lime/Core/Notifications/NotificationPolicy.swift (which message shows a banner, and the arrival detector);
// the words themselves are the core's `notification_words`. Moves into LimeCore in LIME-133.

/** What a banner says and where tapping it goes. */
data class BannerData(val conversationId: String, val title: String, val body: String)

/**
 * The banner at the top while lime is open (iOS's banner presentation): a new message from someone in another chat than the one on screen, unless
 * notifications are off or the chat is muted. The first look only learns what is already there, so opening the app never announces old history. There is
 * no push service yet: this is the only place alerts show.
 */
class ArrivalBanner(
    private val enabled: () -> Boolean,
    private val preview: () -> uniffi.lime_core.NotificationPreview,
    private val muted: (String) -> Boolean,
    private val hideText: () -> Boolean = { false },
) {
    var banner by mutableStateOf<BannerData?>(null)
        private set
    private val seen = mutableSetOf<String>()
    private var primed = false

    /** Looks at the chats after a read; `viewing` is the chat on screen (its messages only tick, no banner). */
    fun check(conversations: List<ConversationSummary>, viewing: String?) {
        val newest = conversations.mapNotNull { c -> c.lastMessage?.takeIf { it.senderId != null && it.localState != "system" && !it.deleted }?.let { c to it } }
        val fresh = if (primed) newest.filter { (_, m) -> m.id !in seen } else emptyList()
        seen.addAll(newest.map { it.second.id })
        primed = true
        val (chat, message) = fresh.maxByOrNull { it.second.sentAt } ?: return
        if (!enabled() || muted(chat.id) || chat.id == viewing) return
        val sender = chat.members.firstOrNull { it.id == message.senderId }?.name ?: chat.title
        val words = notificationWords(
            IncomingWords(chat.title, sender, messagePlainText(message.text), message.threadRoot != null, chat.isGroup, chat.isRequest),
            preview(), hideText(),
        )
        banner = BannerData(chat.id, words.title, words.body)
    }

    fun dismiss() { banner = null }
}
