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
 * A band's page (LIME-315b; iOS `OrgProfile`): its picture, name and about, then **Posts | Info**. Posts are the band's jam posts (open one in the usual reader); Info is the about, the tags, how many posts and
 * a **Members** row that opens the members screen. Members is where the owner manages roles, removes people and makes the invite link.
 */
@Composable
fun BandScreen(jam: JamInfo, model: JamModel, onBack: () -> Unit, onOpenPost: (JamPostInfo) -> Unit) {
    val colors = Lime.colors
    var tab by remember { mutableStateOf(0) }
    var members by remember { mutableStateOf(false) }
    var count by remember { mutableStateOf<Int?>(null) }
    LaunchedEffect(jam.jamId, members) { count = model.bands.members(jam.jamId).size }
    if (members) { BandMembersScreen(jam, model, onBack = { members = false }); return }
    val picture = remember(jam.jamId, model.reloads) { model.picture(jam.jamId)?.let { AttachmentProcessing.decodeForDisplay(it, 400) }?.asImageBitmap() }
    val posts = model.posts.filter { it.jamId == jam.jamId }.sortedByDescending { it.created }
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
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TabPill(stringResource(R.string.band_tab_posts), tab == 0, "band-tab-posts") { tab = 0 }
                TabPill(stringResource(R.string.band_tab_info), tab == 1, "band-tab-info") { tab = 1 }
            }
            if (tab == 0) {
                if (posts.isEmpty()) Text(stringResource(R.string.band_no_posts), color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.padding(vertical = 24.dp).testTag("band-no-posts"))
                posts.forEach { post ->
                    val words = post.title.ifEmpty { JamModel.excerpt(post, 120) }
                    Column(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(colors.surface).clickable { onOpenPost(post) }.padding(14.dp)
                            .semantics(mergeDescendants = true) { role = Role.Button }.testTag("band-post-${post.postId}"),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        if (post.title.isNotEmpty()) Text(post.title, color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 2)
                        Text(JamModel.excerpt(post, 160), color = colors.textSecondary, fontSize = 15.sp, maxLines = 3)
                    }
                }
            } else {
                if (jam.about.isNotEmpty()) Text(jam.about, color = colors.text, fontSize = 17.sp, modifier = Modifier.testTag("band-about"))
                if (jam.topics.isNotEmpty()) Text(jam.topics.joinToString(" · "), color = colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("band-topics"))
                InfoRow(stringResource(R.string.band_posts_count), jam.postCount.toInt().toString(), "band-info-posts")
                InfoRow(stringResource(R.string.band_members_row), count?.toString().orEmpty(), "band-info-members", onClick = { members = true })
            }
        }
    }
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
fun BandMembersScreen(jam: JamInfo, model: JamModel, onBack: () -> Unit) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    var members by remember { mutableStateOf<List<OrgMemberInfo>>(emptyList()) }
    var loaded by remember { mutableStateOf(false) }
    var acting by remember { mutableStateOf<OrgMemberInfo?>(null) }
    var removing by remember { mutableStateOf<OrgMemberInfo?>(null) }
    var inviting by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    suspend fun load() { members = model.bands.members(jam.jamId); loaded = true }
    LaunchedEffect(jam.jamId) { load() }
    fun change(person: OrgMemberInfo, role: String) { scope.launch { failed = !model.bands.setRole(jam.jamId, person.userId, role); load() } }
    val canInvite = members.any { it.canManage } || members.any { it.isMe && it.role == "owner" }
    val roles = listOf("owner", "writer", "member")
    val roleWords = roles.associateWith { roleTitle(it) }
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().testTag("band-members")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("band-members-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Text(stringResource(R.string.band_members_row), color = colors.text, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).semantics { heading() })
            if (canInvite) TextButton({ inviting = true }, Modifier.heightIn(min = 48.dp).testTag("band-invite-open")) { Text(stringResource(R.string.band_invite), color = colors.text, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
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
        }
    }
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
                }
            }
        },
        confirmButton = {
            if (state == "asked") TextButton(onDismiss, Modifier.heightIn(min = 48.dp).testTag("band-join-done")) { Text(stringResource(R.string.band_join_done), color = colors.text) }
            else TextButton({
                scope.launch {
                    val code = BandLinks.code(text)
                    state = if (model.bands.parse(code) == null) "bad" else if (model.bands.join(code)) "asked" else "failed"
                }
            }, Modifier.heightIn(min = 48.dp).testTag("band-join-go"), enabled = text.isNotBlank()) { Text(stringResource(R.string.band_join_go), color = colors.text, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = { if (state != "asked") TextButton(onDismiss, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
    )
}
