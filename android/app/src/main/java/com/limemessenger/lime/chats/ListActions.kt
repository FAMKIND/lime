package com.limemessenger.lime.chats

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.LimeStore

// Chat list changes are the core's (pin, unread mark, label, leave, delete); which chats show, unread and mute are its rules (core/src/client/list_rules.rs).
// As iOS's ConversationStore (setPinned, setMarkedUnread) and ConversationStore+Groups.

private suspend fun ChatsModel.change(block: (LimeStore) -> Unit) {
    val core = core() ?: return
    withContext(Dispatchers.IO) { runCatching { block(core) } }
    reload()
    deliverNow()
}

suspend fun ChatsModel.setPinned(conversationId: String, pinned: Boolean) = change { it.setPinned(conversationId, pinned) }

/** Unread: marks the chat by hand. Read: reads it (as iOS: the unread count clears too). */
suspend fun ChatsModel.setMarkedUnread(conversationId: String, unread: Boolean) = change { if (unread) it.setMarkedUnread(conversationId, true) else it.markRead(conversationId) }

/** My private label for a person ("Grade 4"); null or blank takes it off. */
suspend fun ChatsModel.setLabel(userId: String, label: String?) = change { it.setContactLabel(userId, label?.trim()?.ifEmpty { null }) }

suspend fun ChatsModel.leaveGroup(conversationId: String) = change { it.leaveGroup(conversationId) }

suspend fun ChatsModel.deleteGroupForEveryone(conversationId: String) = change { it.deleteGroup(conversationId) }

/** Clears the messages from this phone only; in a group I stay in it. */
suspend fun ChatsModel.clearMessages(conversationId: String) = change { it.clearMessages(conversationId) }

/** What a swipe or a long-press on a row can do (iOS's row actions), in the menu's order. */
enum class RowAction { MarkRead, MarkUnread, Pin, Unpin, Mute, Unmute, Label, Leave, DeleteForEveryone, Clear, DeleteChat }

/** A group that is still going: not a request, not left or deleted. */
val ConversationSummary.isLiveGroup: Boolean get() = isGroup && !isRequest && groupEnded == null

fun rowActions(chat: ConversationSummary, muted: Boolean): List<RowAction> = buildList {
    add(if (chat.isUnread) RowAction.MarkRead else RowAction.MarkUnread)
    add(if (chat.isPinned) RowAction.Unpin else RowAction.Pin)
    add(if (muted) RowAction.Unmute else RowAction.Mute)
    if (!chat.isGroup && chat.members.isNotEmpty()) add(RowAction.Label)
    if (chat.isLiveGroup) {
        add(RowAction.Leave)
        add(if (chat.myRole == "owner") RowAction.DeleteForEveryone else RowAction.Clear)
    } else add(RowAction.DeleteChat)
}
