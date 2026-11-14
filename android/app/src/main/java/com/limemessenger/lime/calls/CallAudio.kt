package com.limemessenger.lime.calls

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build

/**
 * What the phone's audio does for a call (iOS `CallRoute` and the call sounds): the communication mode and audio focus while a call is going, the earpiece or the
 * speaker (the person's toggle), the caller's ringback, and the ring of an incoming call while lime is open. Pure platform code: the rules are the core's machine.
 */
class CallAudio(context: Context) {
    private val appContext = context.applicationContext
    private val audio = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var focus: AudioFocusRequest? = null
    private var tone: ToneGenerator? = null
    private var ringtone: android.media.Ringtone? = null
    private var savedMode: Int? = null

    /** A call is on: the communication mode, audio focus, and the earpiece (a voice call) or the speaker. */
    fun start(speaker: Boolean) {
        if (savedMode == null) savedMode = audio.mode
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setOnAudioFocusChangeListener { }.build()
        focus = request
        audio.requestAudioFocus(request)
        setSpeaker(speaker)
    }

    /** The speaker (true) or the earpiece (false). */
    fun setSpeaker(on: Boolean) {
        if (Build.VERSION.SDK_INT >= 31) {
            val wanted = if (on) AudioDeviceInfo.TYPE_BUILTIN_SPEAKER else AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
            val device = audio.availableCommunicationDevices.firstOrNull { it.type == wanted }
            if (device != null) audio.setCommunicationDevice(device) else audio.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            audio.isSpeakerphoneOn = on
        }
    }

    /** The call is over: the phone's audio goes back to what it was. */
    fun stop() {
        stopRingback(); stopRinging()
        if (Build.VERSION.SDK_INT >= 31) audio.clearCommunicationDevice() else @Suppress("DEPRECATION") run { audio.isSpeakerphoneOn = false }
        focus?.let { audio.abandonAudioFocusRequest(it) }
        focus = null
        savedMode?.let { audio.mode = it }
        savedMode = null
    }

    /** The caller hears ringing from the moment the offer is out. */
    fun startRingback() {
        if (tone != null) return
        tone = runCatching { ToneGenerator(AudioManager.STREAM_VOICE_CALL, 60).also { it.startTone(ToneGenerator.TONE_SUP_RINGTONE) } }.getOrNull()
    }

    fun stopRingback() { runCatching { tone?.stopTone(); tone?.release() }; tone = null }

    /** An incoming call rings (the phone's ringtone) while lime is open. */
    fun startRinging() {
        if (ringtone != null) return
        ringtone = runCatching {
            RingtoneManager.getRingtone(appContext, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))?.also {
                it.audioAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                it.isLooping = true
                it.play()
            }
        }.getOrNull()
    }

    fun stopRinging() { runCatching { ringtone?.stop() }; ringtone = null }
}
