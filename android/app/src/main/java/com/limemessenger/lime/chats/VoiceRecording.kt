package com.limemessenger.lime.chats

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import uniffi.lime_core.attachmentLimits
import uniffi.lime_core.voiceWaveformBars

/** What a finished recording is: the AAC file's bytes, how long it ran, and its loudness over time (64 bars, one byte each). */
class VoiceNote(val bytes: ByteArray, val durationMs: Int, val waveform: ByteArray)

/** Where the sound comes from: the microphone (`MediaRecorderCapture`), or a made-up one in tests and on an emulator with no microphone. */
interface VoiceCapture {
    /** Starts; false when it cannot (no microphone, or it is busy). */
    fun start(podcast: Boolean = false): Boolean

    /** The loudness right now, 0 to 1. */
    fun level(): Float

    /** Stops and returns the sound as an m4a (AAC in MPEG-4, as iOS makes it) or null. */
    fun stop(): ByteArray?

    fun cancel()
}

/** Records mono AAC at about 24 kbps (a minute is roughly 180 KB), as iOS's `VoiceRecorder` does. */
class MediaRecorderCapture(private val context: Context) : VoiceCapture {
    private var recorder: MediaRecorder? = null
    private var file: File? = null

    @Suppress("DEPRECATION")
    override fun start(podcast: Boolean): Boolean {
        cancel()
        val out = File.createTempFile("lime-voice-", ".m4a", context.cacheDir)
        val made = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()
        return try {
            made.setAudioSource(MediaRecorder.AudioSource.MIC)
            made.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            made.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            made.setAudioChannels(1)
            made.setAudioSamplingRate(22_050)
            made.setAudioEncodingBitRate(if (podcast) 32_000 else 24_000)
            made.setOutputFile(out.path)
            made.prepare()
            made.start()
            recorder = made; file = out
            true
        } catch (e: Exception) {
            runCatching { made.release() }
            out.delete()
            false
        }
    }

    override fun level(): Float = (recorder?.maxAmplitude ?: 0) / 32_767f

    override fun stop(): ByteArray? {
        val r = recorder ?: return null
        val f = file
        recorder = null; file = null
        return try {
            r.stop(); r.release()
            f?.readBytes()?.takeIf { it.isNotEmpty() }
        } catch (e: Exception) {
            runCatching { r.release() }
            null
        } finally {
            f?.delete()
        }
    }

    override fun cancel() {
        val r = recorder
        val f = file
        recorder = null; file = null
        runCatching { r?.stop() }
        runCatching { r?.release() }
        f?.delete()
    }
}

/**
 * Records a voice message (iOS `VoiceRecorder`): hold to record; the caller decides whether it is sent, cancelled or locked hands-free. Shorter than 0.6 s is a
 * tap, not a voice message; longer than 15 minutes is cut. The waveform bars are the core's `voice_waveform_bars`.
 */
class VoiceRecorder(private val capture: VoiceCapture, private val clock: () -> Long = { System.currentTimeMillis() }) {
    enum class Phase { Idle, Recording, Locked }

    var phase by mutableStateOf(Phase.Idle)
        private set
    var elapsedMs by mutableStateOf(0L)
        private set
    var levels by mutableStateOf(listOf<Float>())
        private set
    private var raw = mutableListOf<Float>()
    private var startedAt = 0L

    val isRecording: Boolean get() = phase != Phase.Idle
    val limitMs: Long get() = (attachmentLimits().maxVoiceSeconds * 1000).toLong()

    /** Starts recording. False when the microphone is not available. */
    fun start(): Boolean {
        if (phase != Phase.Idle) return true
        if (!capture.start()) return false
        phase = Phase.Recording
        startedAt = clock(); elapsedMs = 0; raw = mutableListOf(); levels = emptyList()
        return true
    }

    /** Called about every 50 ms while recording: the time, and a loudness sample. */
    fun tick() {
        if (phase == Phase.Idle) return
        elapsedMs = clock() - startedAt
        val level = capture.level().coerceIn(0f, 1f)
        raw.add(level)
        levels = (levels + level).takeLast(60)
    }

    /** Hands-free: recording goes on after the finger is lifted. */
    fun lock() { if (phase == Phase.Recording) phase = Phase.Locked }

    /** Stops and returns the note (null if it was too short to mean anything, or the sound could not be read). */
    fun finish(): VoiceNote? {
        if (phase == Phase.Idle) return null
        val duration = clock() - startedAt
        val bars = voiceWaveformBars(raw, 64u)
        phase = Phase.Idle
        val bytes = capture.stop()
        if (duration < attachmentLimits().minVoiceSeconds * 1000 || bytes == null) return null
        return VoiceNote(bytes, duration.toInt(), bars)
    }

    fun cancel() {
        if (phase == Phase.Idle) return
        phase = Phase.Idle
        capture.cancel()
    }
}
