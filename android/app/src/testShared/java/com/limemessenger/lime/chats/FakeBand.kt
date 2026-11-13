package com.limemessenger.lime.chats

import com.limemessenger.lime.jam.BandBackend
import uniffi.lime_core.OrgGroupInfo
import uniffi.lime_core.OrgInfo
import uniffi.lime_core.OrgInvite
import uniffi.lime_core.OrgMemberInfo

/**
 * A made-up band for the tests (LIME-315b/315d): members, roles, an invite, groups, my role and my join states. The *reading* of a code is whatever `parser` is (the tests give the real core's `parse_org_invite`);
 * who may manage whom is whatever this fake reports in `canManage`, as the core would: the rules themselves are the core's and are tested there.
 */
class FakeBand(private val parser: (String) -> OrgInvite?) : BandBackend {
    /** My role in the band: owner, writer, member, or null (I only follow it: not in `my_orgs`). */
    var myRole: String? = "owner"
    var jamId = "band"
    var people = mutableListOf(
        OrgMemberInfo("me", "Ada Android", 1u, "owner", true, false),
        OrgMemberInfo("ben", "Ben Android", 2u, "writer", false, true),
        OrgMemberInfo("cleo", "Cleo Android", 3u, "member", false, true),
    )
    var token = 1
    var inviteOn = true
    val roleChanges = mutableListOf<Triple<String, String, String>>()
    val removed = mutableListOf<String>()
    val joined = mutableListOf<String>()
    var joinStateAnswer: String? = "asked"
    var groupList = mutableListOf<OrgGroupInfo>()
    val groupStates = mutableMapOf<String, String>()
    val joinedGroups = mutableListOf<String>()
    val createdGroups = mutableListOf<Triple<String, Boolean, List<String>>>()
    var left = false
    var joinOk = true

    override suspend fun members(jamId: String) = if (myRole == null) emptyList() else people.toList()
    override suspend fun inviteCode(jamId: String) = if (inviteOn) "$jamId.me.token$token" else null
    override suspend fun resetInvite(jamId: String, on: Boolean): String? { inviteOn = on; if (on) token++; return inviteCode(jamId) }
    override suspend fun setRole(jamId: String, userId: String, role: String): Boolean { roleChanges += Triple(jamId, userId, role); people.replaceAll { if (it.userId == userId) it.copy(role = role) else it }; return true }
    override suspend fun remove(jamId: String, userId: String): Boolean { removed += userId; people.removeAll { it.userId == userId }; return true }
    override suspend fun parse(code: String): OrgInvite? = parser(code)
    override suspend fun join(code: String): Boolean { if (!joinOk) return false; joined += code; return true }
    override suspend fun joinState(jamId: String): String? = joinStateAnswer
    override suspend fun mine(): List<OrgInfo> = myRole?.let { listOf(OrgInfo(jamId, "grp:$jamId", "me", "Band", it, people.size.toUInt())) } ?: emptyList()
    override suspend fun groups(jamId: String): List<OrgGroupInfo> = groupList.toList()
    override suspend fun groupJoinState(jamId: String, conversationId: String): String? = groupStates[conversationId]
    override suspend fun joinGroup(jamId: String, conversationId: String): Boolean {
        joinedGroups += conversationId; groupStates[conversationId] = "joined"
        groupList.replaceAll { if (it.conversationId == conversationId) it.copy(joined = true) else it }
        return true
    }
    override suspend fun createGroup(jamId: String, name: String, open: Boolean, members: List<String>): String? {
        val id = "grp:new-${groupList.size}"
        createdGroups += Triple(name, open, members)
        groupList += OrgGroupInfo(id, name, open, true, true)
        return id
    }
    override suspend fun leave(jamId: String): Boolean { left = true; myRole = null; return true }
}
