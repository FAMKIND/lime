package com.limemessenger.lime.chats

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import uniffi.lime_core.ConversationSummary

/** What a banner says and where tapping it goes. */
data class BannerData(val conversationId: String, val title: String, val body: String)

/**
 * The banner at the top while lime is open (iOS's banner presentation): a new message from someone in another chat than the one on screen, unless notifications
 * are off or the chat is muted. The rule (which message, the first look only learning) and the words are the core's `arrival_check` (LIME-400); this keeps the state
 * between looks. There is no push service yet: this is the only place alerts show.
 */
class ArrivalBanner(
    private val enabled: () -> Boolean,
    private val preview: () -> uniffi.lime_core.NotificationPreview,
    private val muted: (String) -> Boolean,
    private val hideText: () -> Boolean = { false },
) {
    var banner by mutableStateOf<BannerData?>(null)
        private set
    private var state = uniffi.lime_core.ArrivalState(false, emptyList())

    /** Looks at the chats after a read; `viewing` is the chat on screen (its messages only tick, no banner). */
    fun check(conversations: List<ConversationSummary>, viewing: String?) {
        val result = uniffi.lime_core.arrivalCheck(conversations, state, enabled(), preview(), conversations.map { it.id }.filter(muted), hideText(), viewing)
        state = result.state
        result.pick?.let { banner = BannerData(it.conversationId, it.title, it.body) }
    }

    fun dismiss() { banner = null }
}
