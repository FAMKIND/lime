package com.limemessenger.lime.ui.calls

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
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
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.limemessenger.lime.R
import com.limemessenger.lime.calls.CallSession
import com.limemessenger.lime.calls.WebRtcCallMedia
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeShapes
import com.limemessenger.lime.ui.theme.LimeSpacing
import com.limemessenger.lime.ui.theme.LimeType
import com.limemessenger.lime.ui.theme.LimeType.style
import livekit.org.webrtc.RendererCommon
import livekit.org.webrtc.SurfaceViewRenderer
import uniffi.lime_core.CallRouteKind
import uniffi.lime_core.callRouteName
import kotlin.math.hypot

private enum class Corner { TopEnd, BottomEnd, BottomStart, TopStart }

/**
 * The video call (iOS `CallView`, the video layout): the other person's picture fills the screen, mine is a small tile that drags to a corner (or moves with a TalkBack
 * action) and swaps with a tap, the name, the timer and the four emoji at the top, a column of round buttons at the right (Camera, Mute, audio output, End) and Flip camera
 * at the bottom left. When their camera is off the screen shows their picture-less avatar, never a frozen or black frame. The screen is dark like iOS's, so the buttons keep
 * their contrast over any picture.
 */
@Composable
internal fun VideoCallLayout(session: CallSession, name: String, initials: String, tone: Int, status: String, emojiSpoken: String, modifier: Modifier = Modifier, onAllowBluetooth: (() -> Unit)? = null, onMinimize: (() -> Unit)? = null) {
    var swapped by rememberSaveable { mutableStateOf(false) }
    var corner by rememberSaveable { mutableStateOf(Corner.TopEnd) }
    var drag by remember { mutableStateOf(androidx.compose.ui.geometry.Offset.Zero) }
    val density = LocalDensity.current
    val myPicture = stringResource(R.string.calls_my_picture)
    val moveTile = stringResource(R.string.calls_move_tile)
    val swapWords = stringResource(R.string.calls_swap)
    val mutedWords = stringResource(R.string.calls_remote_muted, name)
    BoxWithConstraints(modifier.fillMaxSize().background(Color.Black).testTag("call-screen")) {
        val tileW = 108.dp; val tileH = 148.dp
        val widthPx = with(density) { maxWidth.toPx() }; val heightPx = with(density) { maxHeight.toPx() }
        val tileWPx = with(density) { tileW.toPx() }; val tileHPx = with(density) { tileH.toPx() }
        val margin = with(density) { 16.dp.toPx() }; val top = with(density) { 96.dp.toPx() }; val bottom = with(density) { 120.dp.toPx() }
        fun origin(c: Corner) = when (c) {
            Corner.TopEnd -> androidx.compose.ui.geometry.Offset(widthPx - tileWPx - margin - with(density) { 72.dp.toPx() }, top)
            Corner.TopStart -> androidx.compose.ui.geometry.Offset(margin, top)
            Corner.BottomStart -> androidx.compose.ui.geometry.Offset(margin, heightPx - tileHPx - bottom)
            Corner.BottomEnd -> androidx.compose.ui.geometry.Offset(widthPx - tileWPx - margin - with(density) { 72.dp.toPx() }, heightPx - tileHPx - bottom)
        }
        val big = if (swapped) Picture.Mine else Picture.Theirs
        val small = if (swapped) Picture.Theirs else Picture.Mine
        PictureLayer(session, big, name, initials, tone, Modifier.fillMaxSize(), tile = false)
        // The tile: a handle that drags to the nearest corner, taps to swap, and has a non-drag way to move (WCAG 2.5.7).
        val at = origin(corner) + drag
        Box(
            Modifier.offset { IntOffset(at.x.toInt(), at.y.toInt()) }.size(tileW, tileH)
                .border(1.dp, Color.White.copy(alpha = 0.4f), LimeShapes.card)
                .pointerInput(Unit) {
                    detectDragGestures(
                        onDrag = { change, amount -> change.consume(); drag += amount },
                        onDragEnd = {
                            val end = origin(corner) + drag + androidx.compose.ui.geometry.Offset(tileWPx / 2, tileHPx / 2)
                            corner = Corner.entries.minBy { c -> val o = origin(c); hypot(o.x + tileWPx / 2 - end.x, o.y + tileHPx / 2 - end.y) }
                            drag = androidx.compose.ui.geometry.Offset.Zero
                        },
                        onDragCancel = { drag = androidx.compose.ui.geometry.Offset.Zero },
                    )
                }
                .clickable(onClickLabel = swapWords) { swapped = !swapped }
                .semantics {
                    contentDescription = if (small == Picture.Mine) myPicture else name
                    role = Role.Button
                    customActions = listOf(CustomAccessibilityAction(moveTile) { corner = Corner.entries[(corner.ordinal + 1) % Corner.entries.size]; true })
                }
                .testTag("call-tile"),
        ) { PictureLayer(session, small, name, initials, tone, Modifier.fillMaxSize(), tile = true) }

        // The header: the name, the status line, the emoji chip and "Muted".
        Column(Modifier.systemBarsPadding().padding(horizontal = LimeSpacing.l, vertical = LimeSpacing.s)) {
            Text(name, color = Color.White, style = LimeType.run { screenTitle.style() }, modifier = Modifier.semantics { heading() }.testTag("call-name"))
            Row(horizontalArrangement = Arrangement.spacedBy(LimeSpacing.m), verticalAlignment = Alignment.CenterVertically) {
                Text(status, color = Color.White.copy(alpha = 0.92f), style = LimeType.run { secondary.style() }, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("call-status"))
                if (session.emoji.isNotEmpty()) Text(
                    session.emoji.joinToString(" ") { it.emoji }, color = Color.White, style = LimeType.run { secondary.style() },
                    modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = emojiSpoken }.testTag("call-emoji"),
                )
                if (session.remoteMuted) Row(
                    Modifier.semantics(mergeDescendants = true) { contentDescription = mutedWords }.testTag("call-remote-muted"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(Icons.MicOff, null, tint = Color.White, modifier = Modifier.size(14.dp))
                    Text(stringResource(R.string.calls_remote_muted_short), color = Color.White, style = LimeType.run { caption.style() })
                }
            }
            if (session.cameraHeld) Text(stringResource(R.string.calls_camera_held), color = Color.White.copy(alpha = 0.9f), style = LimeType.run { footnote.style() }, modifier = Modifier.padding(top = 4.dp).testTag("call-camera-paused"))
            session.routeToast?.let { words ->
                Text(
                    words, color = Color.White, style = LimeType.run { footnote.style() },
                    modifier = Modifier.padding(top = LimeSpacing.s).background(Color.Black.copy(alpha = 0.6f), LimeShapes.pill).padding(horizontal = 14.dp, vertical = 8.dp)
                        .semantics { liveRegion = LiveRegionMode.Polite }.testTag("call-route-toast"),
                )
            }
        }

        // The buttons: a column at the right; Flip camera at the bottom left.
        Column(
            Modifier.align(Alignment.BottomEnd).systemBarsPadding().padding(end = LimeSpacing.l, bottom = LimeSpacing.xl),
            verticalArrangement = Arrangement.spacedBy(14.dp), horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            ToggleButton(if (session.cameraOn && session.hasLocalVideo) Icons.Video else Icons.VideoOff, stringResource(R.string.calls_camera), session.cameraOn && session.hasLocalVideo, "call-video", size = 56.dp) { session.toggleCamera() }
            ToggleButton(if (session.muted) Icons.MicOff else Icons.Mic, stringResource(R.string.calls_mute), session.muted, "call-mute", size = 56.dp) { session.toggleMute() }
            if (onMinimize != null) ToggleButton(Icons.Minimise, stringResource(R.string.calls_minimise), false, "call-minimize", size = 56.dp, toggle = false) { onMinimize() }
            RouteButton(session, size = 56.dp, onAllowBluetooth = onAllowBluetooth)
            RoundButton(Icons.PhoneDown, stringResource(R.string.calls_end), Lime.colors.danger, Color.White, "call-end", size = 64.dp) { session.hangUp() }
        }
        Box(Modifier.align(Alignment.BottomStart).systemBarsPadding().padding(start = LimeSpacing.l, bottom = LimeSpacing.xl)) {
            ToggleButton(Icons.FlipCamera, stringResource(R.string.calls_flip), false, "call-flip", size = 56.dp, toggle = false) { session.flipCamera() }
        }
    }
}

private enum class Picture { Mine, Theirs }

/** One picture: the camera's frames when there are some, otherwise the person's avatar (their camera is off, or no frame has come yet). */
@Composable
private fun PictureLayer(session: CallSession, which: Picture, name: String, initials: String, tone: Int, modifier: Modifier, tile: Boolean) {
    val showing = if (which == Picture.Theirs) session.remoteVideoShowing else session.cameraOn && session.hasLocalVideo && !session.cameraHeld
    Box(modifier.background(Color(0xFF1B2420)), contentAlignment = Alignment.Center) {
        if (showing) VideoView(session, which, Modifier.fillMaxSize(), mirror = which == Picture.Mine)
        else if (which == Picture.Theirs) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(LimeSpacing.m)) {
                Avatar(initials, tone, if (tile) 40.dp else 120.dp)
                if (!tile) Text(stringResource(R.string.calls_remote_camera_off, name), color = Color.White.copy(alpha = 0.9f), style = LimeType.run { footnote.style() }, modifier = Modifier.testTag("call-remote-camera-off"))
            }
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(LimeSpacing.s)) {
                Icon(Icons.VideoOff, null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(if (tile) 28.dp else 48.dp))
                Text(stringResource(R.string.calls_my_camera_off), color = Color.White.copy(alpha = 0.9f), style = LimeType.run { caption.style() }, modifier = Modifier.testTag("call-my-camera-off"))
            }
        }
    }
}

/** A WebRTC surface the call draws into; the session feeds it frames while it is on screen. */
@Composable
private fun VideoView(session: CallSession, which: Picture, modifier: Modifier, mirror: Boolean) {
    var view by remember { mutableStateOf<SurfaceViewRenderer?>(null) }
    AndroidView(
        modifier = modifier,
        factory = { context ->
            SurfaceViewRenderer(context).also {
                it.init(WebRtcCallMedia.eglBase.eglBaseContext, null)
                it.setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FILL)
                it.setEnableHardwareScaler(true)
                it.setMirror(mirror)
                if (which == Picture.Mine) it.setZOrderMediaOverlay(true)
                view = it
            }
        },
    )
    DisposableEffect(view, which) {
        val renderer = view
        if (renderer != null) { if (which == Picture.Theirs) session.attachRemote(renderer) else session.attachLocal(renderer) }
        onDispose {
            if (which == Picture.Theirs) session.attachRemote(null) else session.attachLocal(null)
            renderer?.release()
        }
    }
}

/** The audio output button: it shows where the sound is now and opens the list of routes the phone has. */
@Composable
internal fun RouteButton(session: CallSession, size: androidx.compose.ui.unit.Dp, onAllowBluetooth: (() -> Unit)? = null) {
    var open by remember { mutableStateOf(false) }
    val name = callRouteName(session.route)
    val label = stringResource(R.string.calls_route_button, name)
    Box {
        Box(
            Modifier.size(size).background(Color.White.copy(alpha = 0.14f), LimeShapes.circle).clickable { open = true }
                .semantics { contentDescription = label; role = Role.Button }.testTag("call-route"),
            contentAlignment = Alignment.Center,
        ) { Icon(routeIcon(session.route), null, tint = Color.White, modifier = Modifier.size(26.dp)) }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.testTag("call-route-menu")) {
            val appContext = androidx.compose.ui.platform.LocalContext.current
            val needsBluetooth = onAllowBluetooth != null && android.os.Build.VERSION.SDK_INT >= 31 &&
                androidx.core.content.ContextCompat.checkSelfPermission(appContext, android.Manifest.permission.BLUETOOTH_CONNECT) != android.content.pm.PackageManager.PERMISSION_GRANTED
            session.routes().forEach { kind ->
                DropdownMenuItem(
                    text = { Text(routeWord(kind) + if (kind == session.route) "  ✓" else "") },
                    leadingIcon = { Icon(routeIcon(kind), null) },
                    onClick = { open = false; session.chooseRoute(kind) },
                    modifier = Modifier.testTag("call-route-${kind.name.lowercase()}"),
                )
            }
            if (needsBluetooth) DropdownMenuItem(
                text = { Text(stringResource(R.string.calls_route_allow_bluetooth)) }, leadingIcon = { Icon(Icons.Bluetooth, null) },
                onClick = { open = false; onAllowBluetooth?.invoke() }, modifier = Modifier.testTag("call-route-allow-bluetooth"),
            )
        }
    }
}

internal fun routeIcon(kind: CallRouteKind): ImageVector = when (kind) {
    CallRouteKind.EARPIECE -> Icons.Phone
    CallRouteKind.SPEAKER -> Icons.SpeakerOn
    CallRouteKind.WIRED -> Icons.Headphones
    CallRouteKind.BLUETOOTH -> Icons.Bluetooth
}

@Composable
private fun routeWord(kind: CallRouteKind): String = stringResource(
    when (kind) {
        CallRouteKind.EARPIECE -> R.string.calls_route_phone
        CallRouteKind.SPEAKER -> R.string.calls_route_speaker
        CallRouteKind.WIRED -> R.string.calls_route_wired
        CallRouteKind.BLUETOOTH -> R.string.calls_route_bluetooth
    },
)

/** The video call floating in Picture in Picture: only the other person's picture (or their avatar), nothing to tap; the window's own button hangs up. */
@Composable
fun CallPipView(session: CallSession, name: String, initials: String, tone: Int) {
    PictureLayer(session, Picture.Theirs, name, initials, tone, Modifier.fillMaxSize().testTag("call-pip"), tile = true)
}
