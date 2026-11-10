package com.limemessenger.lime.chats

import android.content.Context
import android.media.MediaPlayer
import android.media.PlaybackParams
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import uniffi.lime_core.voiceMoved
import uniffi.lime_core.voiceNextSpeed

/**
 * Plays voice messages one at a time, at 1x, 1.5x or 2x, and goes on to the next voice message of the chat (iOS `VoicePlayer`). The speeds and the position
 * rule are the core's (`voice_next_speed`, `voice_moved`). `MediaPlayer` plays a temporary file of the decrypted bytes, removed when it ends.
 */
class VoicePlayer(private val context: Context) {
    var currentId by mutableStateOf<String?>(null)
        private set
    var isPlaying by mutableStateOf(false)
        private set
    var progress by mutableStateOf(0.0)
        private set
    var failed by mutableStateOf(false)
        private set
    var speed by mutableStateOf(1f)
        private set

    private var player: MediaPlayer? = null
    private var file: File? = null
    private var durationMs = 0
    private var next: ((String) -> String?)? = null
    private var load: (suspend (String) -> ByteArray?)? = null

    fun isCurrent(id: String) = currentId == id

    /** Plays or pauses a message; at the end, `after` names the next voice message to play. */
    suspend fun toggle(id: String, after: (String) -> String?, data: suspend (String) -> ByteArray?) {
        next = after; load = data
        if (currentId == id) { if (isPlaying) pause() else resume(); return }
        play(id)
    }

    private suspend fun play(id: String) {
        stop()
        failed = false
        currentId = id; progress = 0.0
        val bytes = load?.invoke(id)
        if (bytes == null) { failed = true; currentId = null; return }
        if (currentId != id) return
        try {
            val temp = File.createTempFile("lime-play-", ".m4a", context.cacheDir).also { it.writeBytes(bytes) }
            val made = MediaPlayer()
            made.setDataSource(temp.path)
            made.prepare()
            durationMs = made.duration
            applySpeed(made)
            made.setOnCompletionListener { finished(id) }
            made.start()
            player = made; file = temp
            isPlaying = true
        } catch (e: Exception) {
            failed = true; currentId = null; isPlaying = false
        }
    }

    private fun finished(id: String) {
        val following = next?.invoke(id)
        stop()
        if (following != null) {
            // The next voice message of the chat starts by itself.
            CoroutineScope(Dispatchers.Main).launch { play(following) }
        }
    }

    private fun applySpeed(p: MediaPlayer) {
        runCatching {
            val params = p.playbackParams ?: PlaybackParams()
            p.playbackParams = params.setSpeed(speed)
            if (!p.isPlaying) p.pause()
        }
    }

    fun pause() { runCatching { player?.pause() }; isPlaying = false }

    fun resume() { runCatching { player?.start() }; isPlaying = player != null }

    /** 1x to 1.5x to 2x and round again; takes effect at once. */
    fun cycleSpeed() {
        speed = voiceNextSpeed(speed)
        player?.let { p -> val was = p.isPlaying; applySpeed(p); if (was) runCatching { p.start() } }
    }

    /** Moves the position by `seconds` (negative: back), inside the message. */
    fun skip(bySeconds: Double) {
        val p = player ?: return
        val total = durationMs / 1000.0
        val to = voiceMoved(progress, total, bySeconds)
        p.seekTo((to * durationMs).toInt()); progress = to
    }

    fun seek(fraction: Double) {
        val p = player ?: return
        p.seekTo((fraction.coerceIn(0.0, 1.0) * durationMs).toInt()); progress = fraction.coerceIn(0.0, 1.0)
    }

    /** Called about every 100 ms by the screen while something plays. */
    fun tick() {
        val p = player ?: return
        if (durationMs > 0) progress = (p.currentPosition.toDouble() / durationMs).coerceIn(0.0, 1.0)
    }

    fun stop() {
        runCatching { player?.stop() }
        runCatching { player?.release() }
        player = null
        file?.delete(); file = null
        isPlaying = false; progress = 0.0; currentId = null
    }
}
