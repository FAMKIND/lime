package com.limemessenger.lime.ui.calls

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.limemessenger.lime.R
import com.limemessenger.lime.calls.CallSession
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeShapes
import com.limemessenger.lime.ui.theme.LimeSpacing
import com.limemessenger.lime.ui.theme.LimeType
import com.limemessenger.lime.ui.theme.LimeType.style
import kotlinx.coroutines.delay
import uniffi.lime_core.callStatusText

/**
 * The call put away (iOS `CallMiniPlayer`): a bar over every screen but the call itself with the person's picture, their name, the running time and **Mute** and **End call**; a tap on
 * the rest of it returns to the call. It sits under the status bar (iOS floats it at the bottom above the tab bar; on Android the bottom holds the keyboard, the composer and the tab
 * bar), is 48 dp high and one stop for TalkBack ("Call with Ben, 1:23. Return to the call") with its two buttons beside it. A change in the time is not read out every second.
 */
@Composable
fun CallMiniBar(session: CallSession, chats: ChatsModel, modifier: Modifier = Modifier) {
    val state = session.driver.state
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(state.phase) { while (true) { nowMs = System.currentTimeMillis(); delay(1_000) } }
    val member = chats.conversations.firstOrNull { !it.isGroup && it.members.firstOrNull()?.id == state.peerId }?.members?.firstOrNull()
    val name = state.peerName.ifEmpty { member?.name.orEmpty() }
    val status = callStatusText(state, nowMs)
    val colors = Lime.colors
    val label = stringResource(R.string.calls_mini_label, name, status)
    Row(
        modifier.statusBarsPadding().padding(horizontal = LimeSpacing.l, vertical = 4.dp).fillMaxWidth().heightIn(min = 48.dp)
            .background(colors.accent, LimeShapes.pill).testTag("call-mini-bar"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).heightIn(min = 48.dp).clickable(onClickLabel = stringResource(R.string.calls_mini_return)) { session.restore() }
                .semantics(mergeDescendants = true) { contentDescription = label; role = Role.Button }.padding(start = 8.dp).testTag("call-mini-open"),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Avatar(member?.initials?.ifEmpty { null } ?: name.take(1), member?.tone?.toInt() ?: com.limemessenger.lime.chats.AvatarTone.tone(state.peerId), 32.dp)
            Text(name, color = Color(0xFF131B17), style = LimeType.run { secondary.style() }, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
            Text(
                status, color = Color(0xFF131B17), style = LimeType.run { caption.style() },
                modifier = Modifier.testTag("call-mini-status"),
            )
        }
        MiniButton(if (session.muted) Icons.MicOff else Icons.Mic, stringResource(R.string.calls_mute), "call-mini-mute", on = session.muted) { session.toggleMute() }
        MiniButton(Icons.PhoneDown, stringResource(R.string.calls_end), "call-mini-end", end = true) { session.hangUp() }
    }
}

/** The group call put away: the same bar (the group's name, the running time, Mute and Leave). */
@Composable
fun GroupCallMiniBar(session: com.limemessenger.lime.calls.GroupCallSession, title: String, modifier: Modifier = Modifier) {
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(session.connected) { while (true) { nowMs = System.currentTimeMillis(); delay(1_000) } }
    val colors = Lime.colors
    val secs = if (session.connected) ((nowMs - session.startMillis) / 1000).coerceAtLeast(0) else 0
    val status = "%d:%02d".format(secs / 60, secs % 60)
    val label = stringResource(R.string.calls_mini_label, title, status)
    Row(
        modifier.statusBarsPadding().padding(horizontal = LimeSpacing.l, vertical = 4.dp).fillMaxWidth().heightIn(min = 48.dp).background(colors.accent, LimeShapes.pill).testTag("group-call-mini-bar"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f).heightIn(min = 48.dp).clickable(onClickLabel = stringResource(R.string.calls_mini_return)) { session.restore() }
                .semantics(mergeDescendants = true) { contentDescription = label; role = Role.Button }.padding(start = 16.dp).testTag("group-call-mini-open"),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(title, color = Color(0xFF131B17), style = LimeType.run { secondary.style() }, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
            Text(status, color = Color(0xFF131B17), style = LimeType.run { caption.style() })
        }
        MiniButton(if (session.muted) Icons.MicOff else Icons.Mic, stringResource(R.string.calls_mute), "group-call-mini-mute", on = session.muted) { session.toggleMute() }
        MiniButton(Icons.PhoneDown, stringResource(R.string.group_call_leave), "group-call-mini-leave", end = true) { session.leave() }
    }
}

@Composable
private fun MiniButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, tag: String, on: Boolean = false, end: Boolean = false, onClick: () -> Unit) {
    val value = stringResource(if (on) R.string.calls_on else R.string.calls_off)
    Box(
        Modifier.size(48.dp).clickable(onClick = onClick).semantics { contentDescription = label; if (!end) { stateDescription = value; role = Role.Switch } else role = Role.Button }.testTag(tag),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(36.dp).background(if (end) Lime.colors.danger else if (on) Color(0xFF131B17) else Color.White.copy(alpha = 0.55f), LimeShapes.circle), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = if (end || on) Color.White else Color(0xFF131B17), modifier = Modifier.size(20.dp))
        }
    }
}
