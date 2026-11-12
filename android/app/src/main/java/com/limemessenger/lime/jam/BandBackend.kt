package com.limemessenger.lime.jam

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.LimeStore
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
