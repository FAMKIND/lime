package com.limemessenger.lime.ui.band

import android.content.Intent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.AttachmentProcessing
import com.limemessenger.lime.jam.BandLinks
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.launch
import uniffi.lime_core.JamInfo
import uniffi.lime_core.JamPostInfo
import uniffi.lime_core.OrgMemberInfo

/** The most people a band's members group holds (the core refuses the 101st). */
private const val MAX_MEMBERS = 100

/**
 * A band's page (LIME-315b/315d; iOS `OrgProfile`): its picture, name and about, then the tabs **Posts | Info**, and for the band's **members only** (iOS `sections`: the members see more) **Members | Groups**.
 * What each person sees: the **owner** (the band is theirs): everything, Invite, New group, role changes; a **writer** or **member**: Members (read-only: the core says whom they may manage: nobody), the Groups, and **Leave band**;
 * a **subscriber** (follows the band, is not a member): Posts and Info and the **Subscribe** pill ("Subscribed ✓", asking before it unsubscribes), no member list, no invite, no groups.
 * (A writer cannot post straight as someone else's band: the core only lets the band's owner publish; writers send a draft for review: not built, see the record.)
 */
@Composable
fun BandScreen(jam: JamInfo, model: JamModel, onBack: () -> Unit, onOpenPost: (JamPostInfo) -> Unit, onOpenChat: (String) -> Unit = {}) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var tab by remember { mutableStateOf("posts") }
    var myRole by remember { mutableStateOf<String?>(null) }
    var roleLoaded by remember { mutableStateOf(false) }
    var confirmUnsubscribe by remember { mutableStateOf(false) }
    // My role in this band: from the core's list of the bands I belong to (nothing there: I only follow it).
    LaunchedEffect(jam.jamId, model.reloads) { myRole = model.bands.mine().firstOrNull { it.jamId == jam.jamId }?.myRole; roleLoaded = true }
    val member = myRole != null
    val owner = myRole == "owner"
    val picture = remember(jam.jamId, model.reloads) { model.picture(jam.jamId)?.let { AttachmentProcessing.decodeForDisplay(it, 400) }?.asImageBitmap() }
    val posts = model.posts.filter { it.jamId == jam.jamId }.sortedByDescending { it.created }
    val following = model.subscriptionStatus(jam.jamId).let { it == "active" || it == "requested" }
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().testTag("band-page")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("band-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Text(jam.title, color = colors.text, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1, modifier = Modifier.weight(1f).semantics { heading() }.testTag("band-title"))
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(72.dp).clip(RoundedCornerShape(20.dp)).background(colors.surface), contentAlignment = Alignment.Center) {
                    if (picture != null) Image(picture, null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                    else Text(jam.title.take(1).uppercase(), color = colors.textSecondary, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                }
                Column {
                    Text(stringResource(R.string.band_label), color = colors.textSecondary, fontSize = 13.sp)
                    if (jam.about.isNotEmpty()) Text(jam.about, color = colors.text, fontSize = 16.sp, maxLines = 3)
                    if (myRole != null) Text(stringResource(R.string.band_your_role, roleTitleOf(myRole!!)), color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.testTag("band-your-role"))
                }
            }
            // Subscribe (a band I do not own): lime when I do not follow it, neutral "Subscribed ✓" after; a tap on it asks before it unsubscribes (as a jam's).
            if (!jam.mine && !owner && roleLoaded) {
                val words = stringResource(if (following) R.string.band_subscribed_words else R.string.band_subscribe_words, jam.title)
                Box(
                    Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(24.dp)).background(if (following) colors.surface else colors.accent)
                        .clickable { if (following) confirmUnsubscribe = true else scope.launch { model.subscribeTo(jam.jamId, jam.writer) } }
                        .semantics { contentDescription = words; role = Role.Button }.padding(horizontal = 20.dp).testTag("band-subscribe"),
                    contentAlignment = Alignment.Center,
                ) { Text(stringResource(if (following) R.string.band_subscribed else R.string.band_subscribe), color = if (following) colors.text else colors.accentInk, fontWeight = FontWeight.SemiBold) }
            }
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TabPill(stringResource(R.string.band_tab_posts), tab == "posts", "band-tab-posts") { tab = "posts" }
                TabPill(stringResource(R.string.band_tab_info), tab == "info", "band-tab-info") { tab = "info" }
                if (member) {
                    TabPill(stringResource(R.string.band_members_row), tab == "members", "band-tab-members") { tab = "members" }
                    TabPill(stringResource(R.string.band_tab_groups), tab == "groups", "band-tab-groups") { tab = "groups" }
                }
            }
            when (tab) {
                "posts" -> {
                    if (posts.isEmpty()) Text(stringResource(if (jam.mine || following) R.string.band_no_posts else R.string.band_subscribe_to_read), color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.padding(vertical = 24.dp).testTag("band-no-posts"))
                    posts.forEach { post ->
                        Column(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surface).clickable { onOpenPost(post) }.padding(14.dp)
                                .semantics(mergeDescendants = true) { role = Role.Button }.testTag("band-post-${post.postId}"),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            if (post.title.isNotEmpty()) Text(post.title, color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 2)
                            Text(JamModel.excerpt(post, 160), color = colors.textSecondary, fontSize = 15.sp, maxLines = 3)
                        }
                    }
                }
                "info" -> {
                    if (jam.about.isNotEmpty()) Text(jam.about, color = colors.text, fontSize = 17.sp, modifier = Modifier.testTag("band-about"))
                    if (jam.topics.isNotEmpty()) Text(jam.topics.joinToString(" · "), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("band-topics"))
                    InfoRow(stringResource(R.string.band_posts_count), jam.postCount.toInt().toString(), "band-info-posts")
                }
                "members" -> BandMembersScreen(jam, model, onBack = {}, embedded = true, onLeft = onBack)
                "groups" -> BandGroupsPane(jam, model, owner = owner, onOpenChat = onOpenChat)
            }
        }
    }
    if (confirmUnsubscribe) AlertDialog(
        onDismissRequest = { confirmUnsubscribe = false }, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.band_unsubscribe_title, jam.title), color = colors.text) },
        text = { Text(stringResource(R.string.band_unsubscribe_body), color = colors.textSecondary) },
        confirmButton = { TextButton({ confirmUnsubscribe = false; scope.launch { model.unsubscribe(jam.jamId) } }, Modifier.heightIn(min = 48.dp).testTag("band-unsubscribe-confirm")) { Text(stringResource(R.string.band_unsubscribe), color = colors.danger) } },
        dismissButton = { TextButton({ confirmUnsubscribe = false }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
    )
}

@Composable
private fun roleTitleOf(role: String) = stringResource(when (role) { "owner" -> R.string.band_role_owner; "writer" -> R.string.band_role_writer; else -> R.string.band_role_member })

/**
 * The band's groups (LIME-315d; iOS `OrgGroupsTab`): each group with "Open" or "Invite only"; **Open** for a group I am in, **Join** for an open group I am not in (`org_group_join_state` says "asked" while an owner's phone
 * has not added me yet), **New group** for the band's owner. A band's group opens as an ordinary group chat.
 */
@Composable
fun BandGroupsPane(jam: JamInfo, model: JamModel, owner: Boolean, onOpenChat: (String) -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var groups by remember { mutableStateOf<List<uniffi.lime_core.OrgGroupInfo>>(emptyList()) }
    var states by remember { mutableStateOf<Map<String, String?>>(emptyMap()) }
    var loaded by remember { mutableStateOf(false) }
    var making by remember { mutableStateOf(false) }
    val reads = remember { com.limemessenger.lime.ui.common.NewestRead() }   // the newest read wins (LIME-417)
    suspend fun load() {
        reads.read({ val list = model.bands.groups(jam.jamId); list to list.associate { it.conversationId to model.bands.groupJoinState(jam.jamId, it.conversationId) } }) { (list, st) -> groups = list; states = st; loaded = true }
    }
    LaunchedEffect(jam.jamId) { load() }
    Column(Modifier.fillMaxWidth().testTag("band-groups"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (owner) TextButton({ making = true }, Modifier.heightIn(min = 48.dp).testTag("band-new-group")) { Text(stringResource(R.string.band_new_group), color = colors.text, fontWeight = FontWeight.SemiBold) }
        if (loaded && groups.isEmpty()) Text(stringResource(R.string.band_no_groups), color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.padding(vertical = 16.dp).testTag("band-no-groups"))
        groups.forEach { group ->
            val state = states[group.conversationId]
            val inIt = group.joined || state == "joined"
            val kind = stringResource(if (group.open) R.string.band_group_open else R.string.band_group_invite_only)
            Row(
                Modifier.fillMaxWidth().heightIn(min = 60.dp).semantics(mergeDescendants = true) { contentDescription = "${group.name}, $kind" }.testTag("band-group-${group.conversationId}"),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Avatar(group.name.take(1).uppercase(), 2, 40.dp)
                Column(Modifier.weight(1f)) {
                    Text(group.name, color = colors.text, fontSize = 17.sp, maxLines = 1)
                    Text(kind, color = colors.textSecondary, fontSize = 13.sp)
                    if (state == "asked" && !inIt) Text(stringResource(R.string.band_group_asked), color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.testTag("band-group-asked-${group.conversationId}"))
                }
                if (inIt) TextButton({ onOpenChat(group.conversationId) }, Modifier.heightIn(min = 48.dp).testTag("band-group-open-${group.conversationId}")) { Text(stringResource(R.string.band_group_open_action), color = colors.text) }
                else if (group.open && state != "asked") TextButton({ scope.launch { model.bands.joinGroup(jam.jamId, group.conversationId); load() } }, Modifier.heightIn(min = 48.dp).testTag("band-group-join-${group.conversationId}")) { Text(stringResource(R.string.band_group_join), color = colors.text, fontWeight = FontWeight.SemiBold) }
            }
        }
    }
    if (making) NewBandGroupDialog(jam, model, onDismiss = { making = false }, onMade = { making = false; scope.launch { load() } })
}

/** An owner makes a group inside the band (LIME-315d; iOS `NewBandGroupSheet`): a name (50), Open (any member may join) or Invite only, and who starts in it, from the band. */
@Composable
private fun NewBandGroupDialog(jam: JamInfo, model: JamModel, onDismiss: () -> Unit, onMade: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf("") }
    var open by remember { mutableStateOf(true) }
    var chosen by remember { mutableStateOf(setOf<String>()) }
    var people by remember { mutableStateOf<List<OrgMemberInfo>>(emptyList()) }
    var failed by remember { mutableStateOf(false) }
    var making by remember { mutableStateOf(false) }
    LaunchedEffect(jam.jamId) { people = model.bands.members(jam.jamId).filter { !it.isMe } }
    AlertDialog(
        onDismissRequest = { if (!making) onDismiss() }, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.band_new_group), color = colors.text) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(name, { name = it.take(50) }, singleLine = true, label = { Text(stringResource(R.string.band_group_name_hint)) }, modifier = Modifier.fillMaxWidth().testTag("band-group-name"))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TabPill(stringResource(R.string.band_group_open), open, "band-group-kind-open") { open = true }
                    TabPill(stringResource(R.string.band_group_invite_only), !open, "band-group-kind-invite") { open = false }
                }
                Text(stringResource(if (open) R.string.band_group_open_note else R.string.band_group_invite_note), color = colors.textSecondary, fontSize = 13.sp)
                if (people.isNotEmpty()) Text(stringResource(R.string.band_group_start_with), color = colors.textSecondary, fontSize = 14.sp)
                people.forEach { person ->
                    val on = person.userId in chosen
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { chosen = if (on) chosen - person.userId else chosen + person.userId }
                            .semantics(mergeDescendants = true) { role = Role.Checkbox; selected = on; contentDescription = person.name }.testTag("band-group-pick-${person.userId}"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(person.name, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
                        if (on) Icon(Icons.Check, null, tint = colors.text)
                    }
                }
                if (failed) Text(stringResource(R.string.band_group_failed), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("band-group-failed"))
            }
        },
        confirmButton = {
            TextButton({
                scope.launch { making = true; failed = false; val id = model.bands.createGroup(jam.jamId, name, open, chosen.toList()); making = false; if (id != null) onMade() else failed = true }
            }, Modifier.heightIn(min = 48.dp).testTag("band-group-create"), enabled = name.isNotBlank() && !making) { Text(stringResource(if (making) R.string.band_creating else R.string.band_make), color = colors.text, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = { TextButton({ if (!making) onDismiss() }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
    )
}

@Composable
private fun TabPill(title: String, on: Boolean, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(
        Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(24.dp)).background(if (on) colors.pressed else colors.surface).clickable(onClick = onClick)
            .semantics { role = Role.Tab; selected = on }.padding(horizontal = 18.dp).testTag(tag),
        contentAlignment = Alignment.Center,
    ) { Text(title, color = colors.text, fontSize = 15.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal) }
}

@Composable
private fun InfoRow(title: String, value: String, tag: String, onClick: (() -> Unit)? = null) {
    val colors = Lime.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .semantics(mergeDescendants = true) { if (onClick != null) role = Role.Button; contentDescription = "$title, $value" }.testTag(tag),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
        Text(value, color = colors.textSecondary, fontSize = 17.sp)
    }
}

/** What a role is called (the core's `owner`, `writer`, `member`). */
@Composable
private fun roleTitle(role: String) = stringResource(when (role) { "owner" -> R.string.band_role_owner; "writer" -> R.string.band_role_writer; else -> R.string.band_role_member })

/**
 * The band's members (LIME-315b; iOS `OrgMembers`): each person with their role, **one TalkBack stop per row ("Ada, Owner") with its actions**; whoever the core says can manage a person (`can_manage`) can change their role
 * (Owner, Writer, Member) or remove them; the core refuses what a person may not do. "n of 100"; **Invite** (for people who can manage) opens the invite link.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BandMembersScreen(jam: JamInfo, model: JamModel, onBack: () -> Unit, embedded: Boolean = false, onLeft: () -> Unit = {}) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var members by remember { mutableStateOf<List<OrgMemberInfo>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var acting by remember { mutableStateOf<OrgMemberInfo?>(null) }
    var removing by remember { mutableStateOf<OrgMemberInfo?>(null) }
    var inviting by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    var leaving by remember { mutableStateOf(false) }
    val reads = remember { com.limemessenger.lime.ui.common.NewestRead() }   // the newest read wins (LIME-417): a role change or a removal reads the list while the first load may still run
    suspend fun load() { reads.read({ model.bands.members(jam.jamId) }) { members = it; loaded = true } }
    LaunchedEffect(jam.jamId) { load() }
    fun change(person: OrgMemberInfo, role: String) { scope.launch { failed = !model.bands.setRole(jam.jamId, person.userId, role); load() } }
    val canInvite = members.any { it.canManage } || members.any { it.isMe && it.role == "owner" }
    val roles = listOf("owner", "writer", "member")
    val roleWords = roles.associateWith { roleTitle(it) }
    Column(if (embedded) Modifier.fillMaxWidth().testTag("band-members") else Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().testTag("band-members")) {
        if (embedded) { if (canInvite) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { TextButton({ inviting = true }, Modifier.heightIn(min = 48.dp).testTag("band-invite-open")) { Text(stringResource(R.string.band_invite), color = colors.text, fontWeight = FontWeight.SemiBold) } } }
        else Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("band-members-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Text(stringResource(R.string.band_members_row), color = colors.text, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).semantics { heading() })
            if (canInvite) TextButton({ inviting = true }, Modifier.heightIn(min = 48.dp).testTag("band-invite-open")) { Text(stringResource(R.string.band_invite), color = colors.text, fontWeight = FontWeight.SemiBold) }
        }
        Column(if (embedded) Modifier.fillMaxWidth() else Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(R.string.band_members_count, members.size, MAX_MEMBERS), color = colors.textSecondary, fontSize = 14.sp, modifier = Modifier.testTag("band-members-count"))
            if (loaded && members.isEmpty()) Text(stringResource(R.string.band_members_none), color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.padding(vertical = 16.dp).testTag("band-members-none"))
            if (failed) Text(stringResource(R.string.band_change_failed), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("band-members-failed"))
            members.forEach { person ->
                val roleName = roleWords.getValue(person.role.takeIf { it in roles } ?: "member")
                val name = if (person.isMe) stringResource(R.string.jam_you) else person.name
                val actions = if (person.canManage) roles.filter { it != person.role }.map { r -> CustomAccessibilityAction(stringResource(R.string.band_make_role, roleWords.getValue(r))) { change(person, r); true } } +
                    CustomAccessibilityAction(stringResource(R.string.band_remove)) { removing = person; true } else emptyList()
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp).then(if (person.canManage) Modifier.clickable { acting = person } else Modifier)
                        .semantics(mergeDescendants = true) { contentDescription = "$name, $roleName"; if (person.canManage) role = Role.Button; customActions = actions }.testTag("band-member-${person.userId}"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Avatar(person.name.take(1).uppercase(), person.tone.toInt(), 40.dp)
                    Text(name, color = colors.text, fontSize = 17.sp, modifier = Modifier.weight(1f))
                    Text(roleName, color = colors.textSecondary, fontSize = 15.sp)
                }
            }
            // Everyone but the owner can leave the band (iOS: "everyone else can leave"): out of its members and groups, and no longer following it.
            val me = members.firstOrNull { it.isMe }
            if (me != null && me.role != "owner") TextButton({ leaving = true }, Modifier.heightIn(min = 52.dp).testTag("band-leave")) { Text(stringResource(R.string.band_leave), color = colors.danger, fontSize = 17.sp) }
        }
    }
    if (leaving) AlertDialog(
        onDismissRequest = { leaving = false }, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.band_leave_title), color = colors.text) },
        text = { Text(stringResource(R.string.band_leave_body), color = colors.textSecondary) },
        confirmButton = { TextButton({ leaving = false; scope.launch { if (model.bands.leave(jam.jamId)) onLeft() else failed = true } }, Modifier.heightIn(min = 48.dp).testTag("band-leave-confirm")) { Text(stringResource(R.string.band_leave), color = colors.danger) } },
        dismissButton = { TextButton({ leaving = false }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
    )
    acting?.let { person ->
        ModalBottomSheet(onDismissRequest = { acting = null }, containerColor = colors.canvas) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 24.dp).testTag("band-member-sheet")) {
                Text(person.name, color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 8.dp).semantics { heading() })
                roles.filter { it != person.role }.forEach { r ->
                    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { acting = null; change(person, r) }.semantics { role = Role.Button }.testTag("band-role-$r"), verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.band_make_role, roleWords.getValue(r)), color = colors.text, fontSize = 17.sp)
                    }
                }
                Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { acting = null; removing = person }.semantics { role = Role.Button }.testTag("band-remove"), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.band_remove), color = colors.danger, fontSize = 17.sp)
                }
            }
        }
    }
    removing?.let { person ->
        AlertDialog(
            onDismissRequest = { removing = null }, containerColor = colors.canvas,
            title = { Text(stringResource(R.string.band_remove_title, person.name), color = colors.text) },
            text = { Text(stringResource(R.string.band_remove_body), color = colors.textSecondary) },
            confirmButton = { TextButton({ removing = null; scope.launch { failed = !model.bands.remove(jam.jamId, person.userId); load() } }, Modifier.heightIn(min = 48.dp).testTag("band-remove-confirm")) { Text(stringResource(R.string.band_remove), color = colors.danger) } },
            dismissButton = { TextButton({ removing = null }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
        )
    }
    if (inviting) BandInviteSheet(jam, model, onDismiss = { inviting = false })
}

/** The invite link (LIME-315b; iOS `OrgInviteSheet`): the link, Share (a plain text send), New link (the old one stops working: asks first) and Turn off; "The link is off." with Turn on. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BandInviteSheet(jam: JamInfo, model: JamModel, onDismiss: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var code by remember { mutableStateOf<String?>(null) }
    var loaded by remember { mutableStateOf(false) }
    var confirmNew by remember { mutableStateOf(false) }
    LaunchedEffect(jam.jamId) { code = model.bands.inviteCode(jam.jamId); loaded = true }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.canvas) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp).testTag("band-invite"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.band_invite_title), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).semantics { heading() })
                TextButton(onDismiss, Modifier.heightIn(min = 48.dp).testTag("band-invite-close")) { Text(stringResource(R.string.band_join_done), color = colors.text) }
            }
            val c = code
            if (c != null) {
                val link = BandLinks.link(c)
                Text(link, color = colors.textSecondary, fontSize = 14.sp, modifier = Modifier.testTag("band-invite-text"))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton({
                        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, link), null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }, Modifier.heightIn(min = 48.dp).testTag("band-invite-share")) { Text(stringResource(R.string.band_invite_share), color = colors.text, fontWeight = FontWeight.SemiBold) }
                    TextButton({ confirmNew = true }, Modifier.heightIn(min = 48.dp).testTag("band-invite-new")) { Text(stringResource(R.string.band_invite_new), color = colors.text) }
                    TextButton({ scope.launch { code = model.bands.resetInvite(jam.jamId, false) } }, Modifier.heightIn(min = 48.dp).testTag("band-invite-off")) { Text(stringResource(R.string.band_invite_off), color = colors.danger) }
                }
            } else if (loaded) {
                Text(stringResource(R.string.band_invite_is_off), color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.testTag("band-invite-is-off"))
                TextButton({ scope.launch { code = model.bands.resetInvite(jam.jamId, true) } }, Modifier.heightIn(min = 48.dp).testTag("band-invite-on")) { Text(stringResource(R.string.band_invite_on), color = colors.text, fontWeight = FontWeight.SemiBold) }
            }
            Text(stringResource(R.string.band_invite_note), color = colors.textSecondary, fontSize = 13.sp)
        }
    }
    if (confirmNew) AlertDialog(
        onDismissRequest = { confirmNew = false }, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.band_invite_new_title), color = colors.text) },
        text = { Text(stringResource(R.string.band_invite_new_body), color = colors.textSecondary) },
        confirmButton = { TextButton({ confirmNew = false; scope.launch { code = model.bands.resetInvite(jam.jamId, true) } }, Modifier.heightIn(min = 48.dp).testTag("band-invite-new-confirm")) { Text(stringResource(R.string.band_invite_new), color = colors.text) } },
        dismissButton = { TextButton({ confirmNew = false }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
    )
}

/** Join a band by its link or code (LIME-315b): paste it; the core reads it (`parse_org_invite`); a wrong code says so, never a crash; a good one asks to join (an owner's phone adds you the next time it is online). */
@Composable
fun BandJoinDialog(model: JamModel, onDismiss: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    var state by remember { mutableStateOf<String?>(null) }   // null, "bad", "asked", "failed"
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.band_join_title), color = colors.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(text, { text = it; state = null }, singleLine = true, label = { Text(stringResource(R.string.band_join_hint)) }, modifier = Modifier.fillMaxWidth().testTag("band-join-field"))
                when (state) {
                    "bad" -> Text(stringResource(R.string.band_join_bad), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("band-join-bad"))
                    "failed" -> Text(stringResource(R.string.band_join_failed), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("band-join-failed"))
                    "asked" -> Text(stringResource(R.string.band_join_asked), color = colors.text, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("band-join-asked"))
                    "joined" -> Text(stringResource(R.string.band_join_in), color = colors.text, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("band-join-joined"))
                    "full" -> Text(stringResource(R.string.band_join_full), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("band-join-full"))
                    "refused" -> Text(stringResource(R.string.band_join_refused), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("band-join-refused"))
                }
            }
        },
        confirmButton = {
            if (state == "asked" || state == "joined") TextButton(onDismiss, Modifier.heightIn(min = 48.dp).testTag("band-join-done")) { Text(stringResource(R.string.band_join_done), color = colors.text) }
            else TextButton({
                scope.launch {
                    val code = BandLinks.code(text)
                    val invite = model.bands.parse(code)
                    state = if (invite == null) "bad" else if (!model.bands.join(code)) "failed" else when (model.bands.joinState(invite.jamId)) { "joined" -> "joined"; "full" -> "full"; "refused" -> "refused"; else -> "asked" }
                }
            }, Modifier.heightIn(min = 48.dp).testTag("band-join-go"), enabled = text.isNotBlank()) { Text(stringResource(R.string.band_join_go), color = colors.text, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = { if (state != "asked" && state != "joined") TextButton(onDismiss, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
    )
}
