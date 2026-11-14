package com.limemessenger.lime.ui.calls

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
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
import uniffi.lime_core.CallPhaseKind
import uniffi.lime_core.callStatusText

/**
 * The call screen (iOS `CallView`, the voice layout): the person's picture and name, the status line (Calling… → Ringing… → Connecting… → the timer), the four
 * verification emoji once the call is up, and the buttons: Mute and Speaker (a toggle says On or Off to TalkBack and changes shape, not only fill) and a red End; an incoming call
 * shows Decline and Accept. Dark, like iOS's call screen, so the buttons keep their contrast. The status line is a polite live region.
 */
@Composable
fun CallScreen(session: CallSession, chats: ChatsModel, modifier: Modifier = Modifier, onAnswer: () -> Unit = { session.answer() }) {
    val state = session.driver.state
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(state.phase) { while (true) { nowMs = System.currentTimeMillis(); delay(500) } }
    val ink = Color(0xFF131B17)
    val member = chats.conversations.firstOrNull { !it.isGroup && it.members.firstOrNull()?.id == state.peerId }?.members?.firstOrNull()
    val name = state.peerName.ifEmpty { member?.name.orEmpty() }
    val status = callStatusText(state, nowMs)
    val emojiSpoken = stringResource(R.string.calls_emoji_spoken, session.emoji.joinToString(", ") { it.name })
    Column(modifier.fillMaxSize().background(ink).systemBarsPadding().padding(horizontal = LimeSpacing.xxl).testTag("call-screen"), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(48.dp))
        Avatar(member?.initials?.ifEmpty { null } ?: name.take(1), member?.tone?.toInt() ?: com.limemessenger.lime.chats.AvatarTone.tone(state.peerId), 96.dp)
        Spacer(Modifier.height(LimeSpacing.l))
        Text(name, color = Color.White, style = LimeType.run { screenTitle.style() }, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() }.testTag("call-name"))
        Spacer(Modifier.height(LimeSpacing.s))
        Text(
            status, color = Color.White.copy(alpha = 0.9f), style = LimeType.run { secondary.style() },
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("call-status"),
        )
        if (state.unreachableHint) Text(
            stringResource(R.string.calls_unreachable, name), color = Color.White.copy(alpha = 0.9f), style = LimeType.run { footnote.style() },
            textAlign = TextAlign.Center, modifier = Modifier.padding(top = LimeSpacing.m).testTag("call-unreachable"),
        )
        if (session.emoji.isNotEmpty()) Column(
            Modifier.padding(top = LimeSpacing.xl).semantics(mergeDescendants = true) {
                contentDescription = emojiSpoken
            }.testTag("call-emoji"),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(session.emoji.joinToString("  ") { it.emoji }, style = LimeType.run { largeTitle.style() }, color = Color.White)
            Text(stringResource(R.string.calls_emoji_note), color = Color.White.copy(alpha = 0.8f), style = LimeType.run { caption.style() }, textAlign = TextAlign.Center, modifier = Modifier.padding(top = LimeSpacing.s))
        }
        Spacer(Modifier.weight(1f))
        if (state.phase == CallPhaseKind.INCOMING) {
            Row(Modifier.padding(bottom = 48.dp), horizontalArrangement = Arrangement.spacedBy(80.dp)) {
                RoundButton(Icons.PhoneDown, stringResource(R.string.calls_decline), Lime.colors.danger, Color.White, "call-decline", caption = true) { session.decline() }
                RoundButton(Icons.Phone, stringResource(R.string.calls_accept), Lime.colors.accent, ink, "call-accept", caption = true) { onAnswer() }
            }
        } else {
            Row(Modifier.padding(bottom = 48.dp), horizontalArrangement = Arrangement.spacedBy(LimeSpacing.l), verticalAlignment = Alignment.CenterVertically) {
                ToggleButton(if (session.muted) Icons.MicOff else Icons.Mic, stringResource(R.string.calls_mute), session.muted, "call-mute") { session.toggleMute() }
                ToggleButton(if (session.speaker) Icons.SpeakerOn else Icons.SpeakerOff, stringResource(R.string.calls_speaker), session.speaker, "call-speaker") { session.toggleSpeaker() }
                RoundButton(Icons.PhoneDown, stringResource(R.string.calls_end), Lime.colors.danger, Color.White, "call-end") { session.hangUp() }
            }
        }
    }
}

/** A round toggle: lit (white with a black glyph) when on; the glyph changes shape with the state (WCAG 1.4.1); TalkBack hears "On" or "Off". */
@Composable
private fun ToggleButton(icon: ImageVector, label: String, on: Boolean, tag: String, onClick: () -> Unit) {
    val value = stringResource(if (on) R.string.calls_on else R.string.calls_off)
    Box(
        Modifier.size(64.dp).background(if (on) Color.White else Color.White.copy(alpha = 0.14f), LimeShapes.circle).clickable(onClick = onClick)
            .semantics { contentDescription = label; stateDescription = value; role = Role.Switch; selected = on }.testTag(tag),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = if (on) Color.Black else Color.White, modifier = Modifier.size(26.dp)) }
}

/** A round action button: a glyph on a colour (Accept is lime with ink, as iOS: 4.5:1 either way), with its word under it for an incoming call. */
@Composable
private fun RoundButton(icon: ImageVector, label: String, color: Color, glyph: Color, tag: String, caption: Boolean = false, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(LimeSpacing.s)) {
        Box(
            Modifier.size(72.dp).background(color, LimeShapes.circle).clickable(onClick = onClick).semantics { contentDescription = label; role = Role.Button }.testTag(tag),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, tint = glyph, modifier = Modifier.size(28.dp)) }
        if (caption) Text(label, color = Color.White, style = LimeType.run { footnote.style() }, modifier = Modifier.testTag("$tag-label"))
    }
}
