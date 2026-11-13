package com.limemessenger.lime.jam

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.LimeStore
import uniffi.lime_core.OrgGroupInfo
import uniffi.lime_core.OrgInfo
import uniffi.lime_core.OrgInvite
import uniffi.lime_core.OrgMemberInfo

/**
 * What the band screens need from the core (LIME-315b), as one small interface so the screens can be tested with made-up members and invites: the real one ([CoreBandBackend]) is only the core's
 * `org.rs` calls, so **who may do what is decided by the core** (`OrgMemberInfo.can_manage`, the owner-only rules inside `set_org_role` and `org_invite_code`), never by a Kotlin copy.
 */
interface BandBackend {
    suspend fun members(jamId: String): List<OrgMemberInfo>
    suspend fun inviteCode(jamId: String): String?
    suspend fun resetInvite(jamId: String, on: Boolean): String?
    suspend fun setRole(jamId: String, userId: String, role: String): Boolean
    suspend fun remove(jamId: String, userId: String): Boolean
    /** Reads a code the core accepts (`jam.writer.token`), or null when it is not one. */
    suspend fun parse(code: String): OrgInvite?
    suspend fun join(code: String): Boolean
    /** My own join of a band: `asked`, `joined`, `full`, `refused`, or none (the core's `org_join_state`). */
    suspend fun joinState(jamId: String): String?
    /** The bands I belong to (as a member of their members group) with my role: owner, writer or member (the core's `my_orgs`). */
    suspend fun mine(): List<OrgInfo>
    /** The band's groups (`org_groups`); `joinedState` is my own join of one (`asked`, `joined`, `full`, `refused`, or none). */
    suspend fun groups(jamId: String): List<OrgGroupInfo>
    suspend fun groupJoinState(jamId: String, conversationId: String): String?
    suspend fun joinGroup(jamId: String, conversationId: String): Boolean
    /** Makes a group inside the band (an owner's: the core refuses anyone else); the new group's conversation id, or null. */
    suspend fun createGroup(jamId: String, name: String, open: Boolean, members: List<String>): String?
    suspend fun leave(jamId: String): Boolean
}

class CoreBandBackend(private val store: () -> LimeStore?, private val deliver: suspend () -> Unit) : BandBackend {
    private suspend fun <T> core(block: (LimeStore) -> T): Result<T> {
        val s = store() ?: return Result.failure(IllegalStateException("no store"))
        return withContext(Dispatchers.IO) { runCatching { block(s) } }
    }

    override suspend fun members(jamId: String) = core { it.orgMembers(jamId) }.getOrDefault(emptyList())
    override suspend fun inviteCode(jamId: String) = core { it.orgInviteCode(jamId) }.getOrNull()
    override suspend fun resetInvite(jamId: String, on: Boolean) = core { it.resetOrgInvite(jamId, on) }.getOrNull().also { deliver() }
    override suspend fun setRole(jamId: String, userId: String, role: String) = core { it.setOrgRole(jamId, userId, role) }.isSuccess.also { deliver() }
    override suspend fun remove(jamId: String, userId: String) = core { it.removeOrgMember(jamId, userId) }.isSuccess.also { deliver() }
    override suspend fun parse(code: String) = core { it.parseOrgInvite(code) }.getOrNull()
    override suspend fun join(code: String) = core { it.joinOrg(code) }.isSuccess.also { deliver() }
    override suspend fun joinState(jamId: String) = core { it.orgJoinState(jamId) }.getOrNull()
    override suspend fun mine() = core { it.myOrgs() }.getOrDefault(emptyList())
    override suspend fun groups(jamId: String) = core { it.orgGroups(jamId) }.getOrDefault(emptyList())
    override suspend fun groupJoinState(jamId: String, conversationId: String) = core { it.orgGroupJoinState(jamId, conversationId) }.getOrNull()
    override suspend fun joinGroup(jamId: String, conversationId: String) = core { it.joinOrgGroup(jamId, conversationId) }.isSuccess.also { deliver() }
    override suspend fun createGroup(jamId: String, name: String, open: Boolean, members: List<String>) = core { it.createOrgGroup(jamId, name.trim(), null, open, members) }.getOrNull().also { deliver() }
    override suspend fun leave(jamId: String) = core { it.leaveOrg(jamId) }.isSuccess.also { deliver() }
}

/** A band's invite link and reading a code out of what someone pasted (iOS `ConversationStore.bandLink` / `bandCode(from:)`). // ANDROID DEBT: a Kotlin twin of two small Swift functions; the code itself is the core's (`parse_org_invite`). */
object BandLinks {
    private const val HOST = "limemessenger.com"

    fun link(code: String) = "https://$HOST/b/#$code"

    /** The code in a pasted link (`https://limemessenger.com/b/#<code>`, the older `/b/<code>` and `lime://b/<code>`) or the pasted text itself when it is a bare code. */
    fun code(pasted: String): String {
        val text = pasted.trim()
        text.substringAfter("/b/#", "").takeIf { it.isNotEmpty() }?.let { return it.trim() }
        text.substringAfter("/b/", "").takeIf { it.isNotEmpty() }?.let { return it.substringBefore('?').trim() }
        return text
    }
}
