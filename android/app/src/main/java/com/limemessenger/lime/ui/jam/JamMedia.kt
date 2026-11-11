package com.limemessenger.lime.ui.jam

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.AttachmentProcessing
import com.limemessenger.lime.chats.VoicePlayer
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.lime_core.JamAttachmentInfo
import uniffi.lime_core.JamPostInfo
import uniffi.lime_core.voiceClock

/** A photo of a jam post, in the place the writer put it (or under a quick post's words): the picture, its caption, and the writer's description for TalkBack. */
@Composable
fun JamPhoto(post: JamPostInfo, attachment: JamAttachmentInfo, caption: String, model: JamModel) {
    val colors = Lime.colors
    val bitmap by produceState<androidx.compose.ui.graphics.ImageBitmap?>(null, post.postId, attachment.attachmentId) {
        val bytes = model.attachmentBytes(post.postId, attachment.attachmentId)
        value = bytes?.let { withContext(Dispatchers.Default) { AttachmentProcessing.decodeForDisplay(it, 1600) }?.asImageBitmap() }
    }
    val alt = model.altOf(post)[attachment.attachmentId].orEmpty()
    val words = alt.ifEmpty { caption }.ifEmpty { stringResource(R.string.jam_photo_label) }
    val ratio = if ((attachment.width ?: 0u) > 0u && (attachment.height ?: 0u) > 0u) (attachment.width!!.toFloat() / attachment.height!!.toFloat()).coerceIn(0.6f, 2f) else 1.5f
    Column(Modifier.fillMaxWidth().testTag("jam-photo-${attachment.attachmentId}"), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(ratio).clip(RoundedCornerShape(14.dp)).background(colors.chip).semantics { contentDescription = words; role = Role.Image }) {
            bitmap?.let { Image(it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxWidth().aspectRatio(ratio)) }
        }
        if (caption.isNotEmpty()) Text(caption, color = colors.textSecondary, fontSize = 14.sp)
    }
}

/** A recording's play pill (iOS `JamPodcastCard` / the player, in small): Play or Pause, the length, and the speed while it plays. Plays through the same player as voice messages. */
@Composable
fun JamPodcastPill(post: JamPostInfo, audio: JamAttachmentInfo, model: JamModel, player: VoicePlayer, modifier: Modifier = Modifier) {
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    val current = player.isCurrent(audio.attachmentId)
    val playing = current && player.isPlaying
    val total = (audio.durationMs ?: 0u).toDouble() / 1000.0
    val words = stringResource(if (playing) R.string.jam_pause else R.string.jam_play) + ", " + post.title.ifEmpty { stringResource(R.string.jam_podcast) } + ", " + uniffi.lime_core.voiceSpoken(total)
    Row(modifier.heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            Modifier.heightIn(min = 48.dp).background(colors.pressed, RoundedCornerShape(24.dp)).semantics { contentDescription = words; role = Role.Button }
                .clickable { scope.launch { player.toggle(audio.attachmentId, after = { null }, data = { model.attachmentBytes(post.postId, it) }) } }.padding(horizontal = 16.dp).testTag("jam-play-${post.postId}"),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(if (playing) Icons.Pause else Icons.Play, null, tint = colors.text, modifier = Modifier.size(22.dp))
            Text(voiceClock(if (current) player.progress * total else total), color = colors.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.testTag("jam-clock-${post.postId}"))
        }
        if (playing) {
            val speed = "%.1f".format(player.speed).removeSuffix(".0")
            Box(Modifier.heightIn(min = 48.dp).padding(horizontal = 8.dp).semantics { contentDescription = "Speed $speed times"; role = Role.Button }.clickable { player.cycleSpeed() }.testTag("jam-speed-${post.postId}"), contentAlignment = Alignment.Center) {
                Text("$speed×", color = colors.text, fontSize = 15.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
    androidx.compose.runtime.LaunchedEffect(current, player.isPlaying) { while (current && player.isPlaying) { player.tick(); delay(100) } }
}
