package com.limemessenger.lime.chats

import com.limemessenger.lime.ui.common.NewestRead
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.GroupDetails
import uniffi.lime_core.defaultGroupName

// Group changes are made by the core (a signed op in its log) and go out with the next delivery, as iOS's ConversationStore+Groups. No Kotlin twin of any rule.

/** The most characters of a group's name (the core rejects more). */
const val GROUP_NAME_LIMIT = 50

/** The name a new group starts with, from the picked people's first names (the core's rule, shared with iOS). */
fun suggestedGroupName(people: List<KnownTeacher>): String = defaultGroupName(people.map { it.name.trim().split(" ").firstOrNull().orEmpty() })

/** Makes a group of the chosen people (not counting me) and returns its conversation id; null when it could not be made. */
suspend fun ChatsModel.createGroup(name: String, emoji: String?, members: List<String>): String? {
    val core = core() ?: return null
    val id = withContext(Dispatchers.IO) { runCatching { core.createGroup(name, emoji, members) }.getOrNull() } ?: return null
    reload()
    deliverNow()
    return id
}

/** Removes a chat from my list (an ended group's "Remove from my list"); nothing is told to anyone. */
suspend fun ChatsModel.removeChat(conversationId: String) {
    val core = core() ?: return
    withContext(Dispatchers.IO) { runCatching { core.deleteChat(conversationId) } }
    reload()
}

/** One group's details screen: who is in it and what I may do, and the changes (rename, add, remove, leave). */
class GroupModel(private val chats: ChatsModel, val conversationId: String) {
    var details by mutableStateOf<GroupDetails?>(null)
        private set
    var failed by mutableStateOf(false)
        private set

    private val detailReads = NewestRead()

    /** Tests: how the details are read. */
    internal var detailsHook: (suspend (uniffi.lime_core.LimeStore) -> GroupDetails)? = null

    /** The newest read wins ([NewestRead]): a slow read begun before a rename or a removal must not put the old member list back. */
    suspend fun refresh() {
        val core = chats.core() ?: return
        try {
            detailReads.read({ withContext(Dispatchers.IO) { detailsHook?.invoke(core) ?: core.groupDetails(conversationId) } }) { found -> details = found }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // keep what is shown
        }
    }

    private suspend fun change(block: (uniffi.lime_core.LimeStore) -> Unit): Boolean {
        val core = chats.core() ?: return false
        val ok = withContext(Dispatchers.IO) { runCatching { block(core) }.isSuccess }
        failed = !ok
        chats.reload()
        chats.deliverNow()
        refresh()
        return ok
    }

    /** False when the name is not allowed (empty, over 50 characters) or I may not rename. */
    suspend fun rename(name: String): Boolean = change { it.renameGroup(conversationId, name) }
    suspend fun add(userIds: List<String>): Boolean = change { it.addGroupMembers(conversationId, userIds) }
    suspend fun remove(userId: String): Boolean = change { it.removeGroupMember(conversationId, userId) }
    suspend fun leave(): Boolean = change { it.leaveGroup(conversationId) }
}
