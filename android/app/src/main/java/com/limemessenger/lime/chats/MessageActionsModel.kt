package com.limemessenger.lime.chats

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.MessageItem

// Message actions are the core's (`react`, `edit_message`, delete, `forward_messages`); which ones a message offers and who may edit are the core's rules
// (`message_actions`, `can_edit`, `can_delete_for_everyone`: core/src/client/message_rules.rs). No Kotlin twin of any rule. As iOS's ConversationStore+Actions / +Forward.

/** At most this many chats per forward (iOS `maxForwardChats`; the core rejects more). */
const val MAX_FORWARD_CHATS = 5

/** Puts my emoji on a message, or takes it off when it is already mine. */
suspend fun ChatModel.react(message: MessageItem, emoji: String) {
    val on = !(message.reactions.firstOrNull { it.emoji == emoji }?.mine ?: false)
    mutate { it.react(conversationId, message.id, emoji, on) }
}

/** Replaces the words of one of my messages. False when the core refuses (blank with no files, too old, not mine). */
suspend fun ChatModel.edit(message: MessageItem, text: String): Boolean {
    val trimmed = text.trim()
    if (trimmed.isEmpty() && message.attachments.isEmpty()) return false
    return mutate { it.editMessage(conversationId, message.id, trimmed) }
}

/** Deletes messages for me (they leave this phone) or for everyone (they become "This message was deleted"). */
suspend fun ChatModel.delete(ids: List<String>, everyone: Boolean) {
    mutate { core -> for (id in ids) if (everyone) core.deleteMessageForEveryone(conversationId, id) else core.deleteMessageForMe(conversationId, id) }
}

/** Forwards messages (oldest first) to up to five chats; each is a new message labelled Forwarded. */
suspend fun ChatModel.forward(ids: List<String>, to: List<String>): Boolean {
    if (ids.isEmpty() || to.isEmpty() || to.size > MAX_FORWARD_CHATS) return false
    return mutate { it.forwardMessages(ids, to) }
}

/** The chats a message can be forwarded to: every chat and group I am in (not requests, not an ended group). */
val ChatsModel.forwardTargets: List<uniffi.lime_core.ConversationSummary> get() = conversations.filter { !it.isRequest && it.groupEnded == null }
