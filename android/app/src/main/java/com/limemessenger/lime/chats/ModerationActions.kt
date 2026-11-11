package com.limemessenger.lime.chats

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.BlockedPerson
import uniffi.lime_core.ReportInput
import uniffi.lime_core.ReportTargetInfo

// Report and Block (LIME-401), as iOS's ConversationStore.block / unblock / blockedPeople / sendReport. The core decides everything: blocking hides the chat, drops their
// new messages and rotates my delivery key; a report is sealed on this phone to the moderation key. Here: the calls, then the list and the delivery are read again.

/** Blocks a person by their chat ("dm:<user>"). Blocking rotates my delivery key, so the server has to hear the new one: deliver. */
suspend fun ChatsModel.block(conversationId: String): Boolean {
    val core = core() ?: return false
    val ok = withContext(Dispatchers.IO) { runCatching { core.blockSender(conversationId) }.isSuccess }
    reload()
    deliverNow()
    return ok
}

/** Unblocks: the chat and what was stored before the block come back. */
suspend fun ChatsModel.unblock(conversationId: String): Boolean {
    val core = core() ?: return false
    val ok = withContext(Dispatchers.IO) { runCatching { core.unblock(conversationId) }.isSuccess }
    reload()
    deliverNow()
    return ok
}

suspend fun ChatsModel.blockedPeople(): List<BlockedPerson> {
    val core = core() ?: return emptyList()
    return withContext(Dispatchers.IO) { runCatching { core.listBlocked() }.getOrDefault(emptyList()) }
}

/** Sends the report (sealed on this phone, see core `send_report`); with "Also block", blocks the person's chat. True when it was sent. */
suspend fun ChatsModel.sendReport(target: ReportTargetInfo, reason: String, note: String, include: Boolean, alsoBlock: Boolean): Boolean {
    val core = core() ?: return false
    val link = transportOrNull() ?: return false
    val token = runCatching { bearer() }.getOrNull() ?: return false
    val input = ReportInput(target.kind, target.ids, reason, note.take(500), if (include) target.included else "")
    val sent = withContext(Dispatchers.IO) { runCatching { core.sendReport(link, token, input) }.isSuccess }
    if (sent) Log.i("lime-report", "sent ${target.kind} ${target.ids.joinToString(",")} reason=$reason note=${note.take(60)}")
    if (sent && alsoBlock) target.blockConversationId?.let { block(it) }
    return sent
}
