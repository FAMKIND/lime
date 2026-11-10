package com.limemessenger.lime.ui.chat

import android.content.Context
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.MediaRecorderCapture
import com.limemessenger.lime.chats.VoiceCapture
import com.limemessenger.lime.chats.VoicePlayer
import com.limemessenger.lime.chats.VoiceRecorder
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlin.math.abs
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.lime_core.AttachmentInfo
import uniffi.lime_core.voiceClock
import uniffi.lime_core.voiceSpoken

// Voice messages and files, as iOS's composer and attachment cards: hold the microphone to record (slide up to lock it hands-free, slide left to cancel;
// locked, it has Send and Cancel), a voice card with play/pause, the waveform, the clock and the speed, and a file card with its name and size.

/** Where recordings come from: the microphone; tests give a made-up sound. */
val LocalVoiceCapture = compositionLocalOf<(Context) -> VoiceCapture> { { MediaRecorderCapture(it) } }

private fun friendlySize(bytes: Long): String = when {
    bytes < 1_000 -> "$bytes B"
    bytes < 1_000_000 -> "%.0f KB".format(bytes / 1_000.0)
    bytes < 1_000_000_000 -> "%.1f MB".format(bytes / 1_000_000.0)
    else -> "%.2f GB".format(bytes / 1_000_000_000.0)
}

/**
 * The microphone button: hold to record, lift to send, slide up to lock, slide left to cancel. `onPress` starts (false when the microphone is not allowed
 * or not there); the rest says what the finger did. One TalkBack action for the same: "Record a voice message" starts it hands-free (locked).
 */
@Composable
fun MicButton(onPress: suspend () -> Boolean, onRelease: () -> Unit, onLock: () -> Unit, onCancel: () -> Unit, onHandsFree: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val lockAt = with(density) { 72.dp.toPx() }
    val cancelAt = with(density) { 96.dp.toPx() }
    val words = stringResource(R.string.voice_record)
    Box(
        modifier.size(56.dp).background(colors.surface, CircleShape)
            .semantics { contentDescription = words; role = Role.Button; onClick(label = words) { onHandsFree(); true } }
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown()
                    scope.launch { onPress() }
                    var locked = false; var cancelled = false
                    while (true) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull() ?: break
                        val dx = change.position.x - down.position.x; val dy = change.position.y - down.position.y
                        if (!locked && !cancelled && dy < -lockAt) { locked = true; onLock() }
                        if (!locked && !cancelled && dx < -cancelAt && abs(dx) > abs(dy)) { cancelled = true; onCancel() }
                        if (!change.pressed) break
                    }
                    if (!locked && !cancelled) onRelease()
                }
            }
            .testTag("voice-mic"),
        contentAlignment = Alignment.Center,
    ) { Icon(Icons.Mic, contentDescription = null, tint = colors.text) }
}

/** What the composer shows in place of the text while a voice message is recorded: the time, the loudness, and how to finish. */
@Composable
fun RecordingBar(recorder: VoiceRecorder, onSend: () -> Unit, onCancel: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Lime.colors
    val clock = voiceClock(recorder.elapsedMs / 1000.0)
    val recording = stringResource(R.string.voice_recording, voiceSpoken(recorder.elapsedMs / 1000.0))
    Row(modifier.heightIn(min = 56.dp).testTag("recording-bar"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.weight(1f).semantics(mergeDescendants = true) { contentDescription = recording}.padding(start = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(10.dp).background(colors.danger, CircleShape))
            Text(clock, color = colors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("recording-clock"))
            Levels(recorder.levels, Modifier.weight(1f).height(32.dp))
        }
        if (recorder.phase == VoiceRecorder.Phase.Locked) {
            TextButton(onClick = onCancel, Modifier.heightIn(min = 48.dp).testTag("voice-cancel")) { Text(stringResource(R.string.group_cancel), color = colors.danger, fontSize = 16.sp) }
            Box(
                Modifier.size(56.dp).background(colors.accent, CircleShape).semantics { role = Role.Button; contentDescription = "Send voice message" }.clickable(onClick = onSend).testTag("voice-send"),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Send, contentDescription = null, tint = colors.accentInk) }
        } else {
            Text(stringResource(R.string.voice_slide_hint), color = colors.textSecondary, fontSize = 13.sp, modifier = Modifier.padding(end = 12.dp))
        }
    }
}

@Composable
private fun Levels(levels: List<Float>, modifier: Modifier) {
    val colors = Lime.colors
    Canvas(modifier) {
        val bar = 3.dp.toPx(); val gap = 2.dp.toPx()
        val count = (size.width / (bar + gap)).toInt().coerceAtLeast(1)
        val shown = levels.takeLast(count)
        shown.forEachIndexed { i, level ->
            val h = (size.height * level.coerceIn(0.08f, 1f))
            val x = size.width - (shown.size - i) * (bar + gap)
            drawRect(colors.text, Offset(x, (size.height - h) / 2), Size(bar, h))
        }
    }
}

/**
 * A voice message in a bubble (iOS `VoiceCard`): play or pause, the waveform (tap or drag to move), the time, and the speed once it plays. The whole message is one
 * TalkBack stop; Play, Pause, the speed and skipping are its custom actions (ChatScreen), not tiny controls to find.
 */
@Composable
fun VoiceCard(attachment: AttachmentInfo, player: VoicePlayer, nextAfter: (String) -> String?, dataFor: suspend (String) -> ByteArray?, ink: Color) {
    val scope = rememberCoroutineScope()
    val current = player.isCurrent(attachment.id)
    val total = (attachment.durationMs ?: 0u).toDouble() / 1000.0
    val progress = if (current) player.progress else 0.0
    val bars = attachment.thumb.map { (it.toInt() and 0xFF) }.ifEmpty { List(64) { 24 } }
    val toggle: () -> Unit = { scope.launch { player.toggle(attachment.id, after = nextAfter, data = dataFor) } }
    Row(Modifier.widthIn(min = 220.dp, max = 260.dp).heightIn(min = 48.dp).testTag("voice-card-${attachment.id}"), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.size(48.dp).clickable(onClick = toggle).testTag("voice-play-${attachment.id}"), contentAlignment = Alignment.Center) {
            Icon(if (current && player.isPlaying) Icons.Pause else Icons.Play, contentDescription = null, tint = ink, modifier = Modifier.size(28.dp))
        }
        Canvas(
            Modifier.weight(1f).height(36.dp).pointerInput(attachment.id, current) {
                detectTapGestures { at -> if (current) player.seek((at.x / size.width).toDouble()) else toggle() }
            }.testTag("voice-wave-${attachment.id}"),
        ) {
            val n = bars.size
            val slot = size.width / n
            bars.forEachIndexed { i, b ->
                val h = size.height * (b / 255f).coerceIn(0.1f, 1f)
                val played = (i + 1).toDouble() / n <= progress
                drawRect(if (played) ink else ink.copy(alpha = 0.4f), Offset(i * slot + slot * 0.2f, (size.height - h) / 2), Size(slot * 0.6f, h))
            }
        }
        Text(voiceClock(if (current) progress * total else total), color = ink, fontSize = 14.sp, modifier = Modifier.testTag("voice-clock-${attachment.id}"))
        if (current && player.isPlaying) {
            val speedWords = stringResource(R.string.voice_speed, "%.1f".format(player.speed).removeSuffix(".0"))
            Box(Modifier.heightIn(min = 48.dp).widthIn(min = 40.dp).semantics { contentDescription = speedWords; role = Role.Button }.clickable { player.cycleSpeed() }.testTag("voice-speed-${attachment.id}"), contentAlignment = Alignment.Center) {
                Text("%.1f×".format(player.speed).replace(".0×", "×"), color = ink, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
    // The clock ticks while it plays.
    LaunchedEffect(current, player.isPlaying) { while (current && player.isPlaying) { player.tick(); delay(100) } }
}

/** A file in a bubble (iOS file card): its name and size; a tap downloads it when this phone does not have it. */
@Composable
fun FileCard(attachment: AttachmentInfo, model: ChatModel, ink: Color) {
    val scope = rememberCoroutineScope()
    var state by remember(attachment.id) { mutableStateOf(if (attachment.downloaded) "saved" else if (attachment.removed) "removed" else "idle") }
    val words = stringResource(R.string.file_card_words, attachment.name.ifEmpty { "File" }, friendlySize(attachment.size.toLong()))
    Row(
        Modifier.widthIn(min = 200.dp, max = 260.dp).heightIn(min = 48.dp).semantics(mergeDescendants = true) { contentDescription = words; role = Role.Button }
            .clickable(enabled = state == "idle") { state = "working"; scope.launch { state = if (model.attachmentBytes(attachment) != null) "saved" else "idle" } }.testTag("file-${attachment.id}"),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Document, contentDescription = null, tint = ink, modifier = Modifier.size(28.dp))
        Column(Modifier.weight(1f)) {
            Text(attachment.name.ifEmpty { "File" }, color = ink, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 2)
            Text(
                when (state) { "saved" -> stringResource(R.string.file_saved, friendlySize(attachment.size.toLong())); "removed" -> stringResource(R.string.file_removed); "working" -> stringResource(R.string.file_downloading); else -> stringResource(R.string.file_tap, friendlySize(attachment.size.toLong())) },
                color = ink.copy(alpha = 0.8f), fontSize = 13.sp, modifier = Modifier.testTag("file-state-${attachment.id}"),
            )
        }
    }
}
