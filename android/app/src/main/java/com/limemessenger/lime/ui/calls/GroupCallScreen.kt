package com.limemessenger.lime.ui.calls

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.limemessenger.lime.R
import com.limemessenger.lime.calls.GroupCallSession
import com.limemessenger.lime.calls.GroupTile
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeShapes
import com.limemessenger.lime.ui.theme.LimeSpacing
import com.limemessenger.lime.ui.theme.LimeType
import com.limemessenger.lime.ui.theme.LimeType.style
import io.livekit.android.renderer.TextureViewRenderer
import kotlinx.coroutines.delay

/**
 * The group call (iOS `GroupCallView`): a grid of tiles (one person fills the screen, two to four make a 2-wide grid, more a 3-wide grid), each with the person's picture or avatar, their name,
 * a muted mark and a ring when they speak; the four emoji once everyone's key is in; Mute, Camera, Flip, audio output and Leave at the bottom. A tile whose key has not arrived says "Securely
 * connecting…" instead of showing anything. Dark, like the 1:1 call screen.
 */
@Composable
fun GroupCallScreen(session: GroupCallSession, title: String, modifier: Modifier = Modifier, onMinimize: (() -> Unit)? = null, onAllowBluetooth: (() -> Unit)? = null, onToggleCamera: () -> Unit = { session.toggleCamera() }) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(session.connected) { while (true) { now = System.currentTimeMillis(); delay(1_000) } }
    val status = when {
        !session.connected -> stringResource(R.string.calls_connecting)
        else -> { val s = ((now - session.startMillis) / 1000).coerceAtLeast(0); "%d:%02d".format(s / 60, s % 60) }
    }
    val spokenEmoji = stringResource(R.string.calls_emoji_spoken, session.emoji.joinToString(", ") { it.name })
    val tiles = session.tiles.toList()
    val columns = when { tiles.size <= 1 -> 1; tiles.size <= 4 -> 2; else -> 3 }
    Column(modifier.fillMaxSize().background(Color(0xFF131B17)).systemBarsPadding().testTag("group-call-screen")) {
        Row(Modifier.fillMaxWidth().padding(horizontal = LimeSpacing.l, vertical = LimeSpacing.s), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(LimeSpacing.m)) {
            Column(Modifier.weight(1f)) {
                Text(title, color = Color.White, style = LimeType.run { screenTitle.style() }, maxLines = 1, modifier = Modifier.semantics { heading() }.testTag("group-call-title"))
                Row(horizontalArrangement = Arrangement.spacedBy(LimeSpacing.m), verticalAlignment = Alignment.CenterVertically) {
                    Text(status, color = Color.White.copy(alpha = 0.92f), style = LimeType.run { secondary.style() }, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("group-call-status"))
                    if (session.emoji.isNotEmpty()) Text(
                        session.emoji.joinToString(" ") { it.emoji }, color = Color.White, style = LimeType.run { secondary.style() },
                        modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = spokenEmoji }.testTag("group-call-emoji"),
                    ) else if (session.connected && session.emojiWaiting > 0) Text(
                        stringResource(R.string.group_call_waiting_keys), color = Color.White.copy(alpha = 0.8f), style = LimeType.run { caption.style() }, modifier = Modifier.testTag("group-call-waiting"),
                    )
                }
            }
            if (onMinimize != null) ToggleButton(Icons.Minimise, stringResource(R.string.calls_minimise), false, "group-call-minimize", size = 48.dp, toggle = false) { onMinimize() }
        }
        LazyVerticalGrid(GridCells.Fixed(columns), Modifier.weight(1f).padding(horizontal = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(tiles, key = { it.participant }) { tile -> Tile(session, tile, tall = tiles.size <= 2) }
        }
        Row(Modifier.fillMaxWidth().padding(vertical = LimeSpacing.l), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            ToggleButton(if (session.muted) Icons.MicOff else Icons.Mic, stringResource(R.string.calls_mute), session.muted, "group-call-mute", size = 56.dp) { session.toggleMute() }
            ToggleButton(if (session.cameraOn) Icons.Video else Icons.VideoOff, stringResource(R.string.calls_camera), session.cameraOn, "group-call-camera", size = 56.dp) { onToggleCamera() }
            if (session.cameraOn) ToggleButton(Icons.FlipCamera, stringResource(R.string.calls_flip), false, "group-call-flip", size = 56.dp, toggle = false) { session.flipCamera() }
            RoundButton(Icons.PhoneDown, stringResource(R.string.group_call_leave), Lime.colors.danger, Color.White, "group-call-leave", size = 64.dp) { session.leave() }
        }
    }
}

@Composable
private fun Tile(session: GroupCallSession, tile: GroupTile, tall: Boolean) {
    val words = buildString {
        append(tile.name.ifEmpty { "?" })
        if (tile.muted) append(", " + stringResource(R.string.calls_remote_muted_short))
        if (!tile.keyReady) append(", " + stringResource(R.string.group_call_securing))
    }
    Box(
        Modifier.fillMaxWidth().size(width = 0.dp, height = if (tall) 260.dp else 150.dp).let { if (tall) it else it }
            .background(Color(0xFF1B2420), LimeShapes.card).border(if (tile.speaking) 3.dp else 0.dp, Lime.colors.accent, LimeShapes.card)
            .semantics(mergeDescendants = true) { contentDescription = words }.testTag("group-tile-${tile.participant}"),
        contentAlignment = Alignment.Center,
    ) {
        if (tile.hasPicture && tile.keyReady) {
            AndroidView(modifier = Modifier.fillMaxSize(), factory = { ctx -> TextureViewRenderer(ctx).also { session.attach(tile.participant, it) } })
            DisposableEffect(tile.participant) { onDispose { session.attach(tile.participant, null) } }
        } else Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Avatar(tile.name.take(1), com.limemessenger.lime.chats.AvatarTone.tone(tile.userId.ifEmpty { tile.participant }), if (tall) 80.dp else 48.dp)
            if (!tile.keyReady) Text(stringResource(R.string.group_call_securing), color = Color.White.copy(alpha = 0.85f), style = LimeType.run { caption.style() }, modifier = Modifier.testTag("group-tile-securing-${tile.participant}"))
        }
        Row(Modifier.align(Alignment.BottomStart).padding(8.dp).background(Color.Black.copy(alpha = 0.55f), LimeShapes.pill).padding(horizontal = 10.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            if (tile.muted) Icon(Icons.MicOff, null, tint = Color.White, modifier = Modifier.size(14.dp))
            Text(tile.name, color = Color.White, style = LimeType.run { caption.style() }, maxLines = 1)
        }
    }
}
