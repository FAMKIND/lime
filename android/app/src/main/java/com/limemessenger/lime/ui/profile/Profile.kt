package com.limemessenger.lime.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.AvatarTone
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.profileOf
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.chats.block
import com.limemessenger.lime.chats.unblock
import com.limemessenger.lime.chats.blockedPeople
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.clickable
import uniffi.lime_core.PublicProfile

/** Someone else's profile, opened from a chat (iOS `ProfileView`, minimal): their name, username, school and About line, read only. */
@Composable
fun PersonProfileScreen(
    userId: String, fallbackName: String, chats: ChatsModel, onBack: () -> Unit, load: suspend (String) -> PublicProfile? = { chats.profileOf(it) },
    /** Their jam, to subscribe to it (null where jams are not wired, as in tests of the profile alone). */
    jam: com.limemessenger.lime.jam.JamModel? = null,
    /** After I block them from here: iOS clears the whole path, so the chat and the profile close. */
    onBlocked: () -> Unit = {},
) {
    val colors = Lime.colors
    var profile by remember { mutableStateOf<PublicProfile?>(null) }
    var done by remember { mutableStateOf(false) }
    LaunchedEffect(userId) { profile = runCatching { load(userId) }.getOrNull(); done = true }
    val name = profile?.displayName?.ifEmpty { null } ?: fallbackName
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().testTag("person-profile")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("profile-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Text(stringResource(R.string.profile_title_other), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        }
        Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Avatar(initialsOf(name), AvatarTone.tone(userId), 96.dp)
            Text(name, color = colors.text, fontSize = 24.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.testTag("profile-name"))
            profile?.username?.let { Text("@$it", color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.testTag("profile-username")) }
            profile?.school?.let { Text(it, color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.testTag("profile-school")) }
            val about = listOfNotNull(profile?.aboutEmoji, profile?.aboutText).filter { it.isNotEmpty() }.joinToString(" ")
            if (about.isNotEmpty()) Text(about, color = colors.text, fontSize = 17.sp, textAlign = TextAlign.Center, modifier = Modifier.testTag("profile-about"))
            if (done && profile == null) Text(stringResource(R.string.profile_not_found), color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.testTag("profile-none"))
            if (!done) Text(stringResource(R.string.profile_loading), color = colors.textSecondary, fontSize = 15.sp)
            if (jam != null) JamSubscribe(userId, jam)
            ProfileSafety(userId, name, chats, onBlocked)
        }
    }
}

/** Their jam on their profile (iOS `JamPage`'s header): its title and post count and one button, **Subscribe** (free) / Subscribed. Posts are readable once subscribed. */
@Composable
private fun JamSubscribe(userId: String, jam: com.limemessenger.lime.jam.JamModel) {
    val colors = Lime.colors
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var page by remember(userId) { mutableStateOf<uniffi.lime_core.JamPageInfo?>(null) }
    var confirming by remember { mutableStateOf(false) }
    LaunchedEffect(userId) { page = jam.pageOf(userId) }
    val p = page ?: return
    val status = jam.subscriptionStatus(p.jamId)
    Column(Modifier.fillMaxWidth().padding(top = 12.dp).testTag("profile-jam"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(p.title, color = colors.text, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.testTag("profile-jam-title"))
        Text(stringResource(R.string.jam_page_line, p.topics.joinToString(", ").ifEmpty { "jam" }, p.postCount.toInt()), color = colors.textSecondary, fontSize = 14.sp)
        val label = when (status) { "active" -> stringResource(R.string.jam_subscribed); "requested" -> stringResource(R.string.jam_requested); else -> stringResource(R.string.jam_subscribe) }
        com.limemessenger.lime.ui.onboarding.PrimaryButton(
            label, { if (status == "active" || status == "requested") confirming = true else scope.launch { jam.subscribe(p) } }, Modifier.testTag("profile-jam-subscribe"),
        )
        // Leaving asks first (iOS's confirm sheet): what is already here stays on this phone.
        if (confirming) androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirming = false }, containerColor = colors.canvas,
            title = { Text(stringResource(R.string.jam_unsubscribe_title, p.title), color = colors.text) },
            text = { Text(stringResource(R.string.jam_unsubscribe_body), color = colors.textSecondary) },
            confirmButton = { androidx.compose.material3.TextButton({ confirming = false; scope.launch { jam.unsubscribe(p.jamId) } }, Modifier.heightIn(min = 48.dp).testTag("profile-jam-subscribe-confirm")) { Text(stringResource(R.string.jam_unsubscribe), color = colors.danger) } },
            dismissButton = { androidx.compose.material3.TextButton({ confirming = false }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.jam_cancel), color = colors.text) } },
        )
        if (status != "active") Text(stringResource(R.string.jam_subscribe_to_read), color = colors.textSecondary, fontSize = 14.sp)
    }
}

/** Report and Block on someone's profile (iOS's ⋯ menu): quiet buttons, one TalkBack stop each. A blocked person's profile offers Unblock instead. */
@Composable
private fun ProfileSafety(userId: String, name: String, chats: ChatsModel, onBlocked: () -> Unit) {
    val colors = Lime.colors
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val chatId = "dm:$userId"
    var reporting by remember { mutableStateOf<uniffi.lime_core.ReportTargetInfo?>(null) }
    var confirming by remember { mutableStateOf(false) }
    var blocked by remember { mutableStateOf(false) }
    val hasChat = chats.conversations.any { it.id == chatId }
    LaunchedEffect(chats.revision) { blocked = chats.blockedPeople().any { it.conversationId == chatId } }
    androidx.compose.foundation.layout.Spacer(Modifier.size(12.dp))
    SafetyButton(stringResource(R.string.profile_report), "profile-report") { reporting = uniffi.lime_core.reportTargetPerson(userId, name, hasChat || blocked) }
    if (blocked) SafetyButton(stringResource(R.string.blocked_unblock_person, name), "profile-unblock") { scope.launch { chats.unblock(chatId) } }
    else if (hasChat) SafetyButton(stringResource(R.string.profile_block, name), "profile-block") { confirming = true }
    reporting?.let { com.limemessenger.lime.ui.moderation.ReportDialog(it, chats, onDismiss = { reporting = null }) }
    if (confirming) com.limemessenger.lime.ui.moderation.BlockConfirm(name, stringResource(R.string.block_profile_body), "profile-block-confirm", onConfirm = { confirming = false; scope.launch { chats.block(chatId); onBlocked() } }, onDismiss = { confirming = false })
}

@Composable
private fun SafetyButton(title: String, tag: String, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { role = Role.Button }.clickable(onClick = onClick).testTag(tag),
        contentAlignment = Alignment.Center,
    ) { Text(title, color = colors.danger, fontSize = 16.sp, fontWeight = FontWeight.SemiBold) }
}
