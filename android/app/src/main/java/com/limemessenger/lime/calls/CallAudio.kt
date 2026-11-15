package com.limemessenger.lime.calls

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import uniffi.lime_core.CallRouteKind
import uniffi.lime_core.callRouteChoice

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
    private var wanted: CallRouteKind? = null
    private var watching: AudioDeviceCallback? = null
    private var proximity: PowerManager.WakeLock? = null
    /** Called (on the main thread) when a headset or the speaker comes or goes. */
    var onRoutesChanged: (() -> Unit)? = null

    /** A call is on: the communication mode, audio focus, and the earpiece (a voice call) or the speaker. */
    fun start(speaker: Boolean) {
        if (savedMode == null) savedMode = audio.mode
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setOnAudioFocusChangeListener { }.build()
        focus = request
        audio.requestAudioFocus(request)
        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) { reapply(); onRoutesChanged?.invoke() }
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) { reapply(); onRoutesChanged?.invoke() }
        }
        watching = callback
        audio.registerAudioDeviceCallback(callback, Handler(Looper.getMainLooper()))
        setSpeaker(speaker)
    }

    private fun typeOf(kind: CallRouteKind): List<Int> = when (kind) {
        CallRouteKind.EARPIECE -> listOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
        CallRouteKind.SPEAKER -> listOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
        CallRouteKind.WIRED -> listOf(AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_USB_HEADSET)
        CallRouteKind.BLUETOOTH -> buildList {
            add(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
            if (Build.VERSION.SDK_INT >= 31) { add(AudioDeviceInfo.TYPE_BLE_HEADSET) }
        }
    }

    private fun devices(): List<AudioDeviceInfo> =
        if (Build.VERSION.SDK_INT >= 31) audio.availableCommunicationDevices else audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).toList()

    /** The routes this phone has right now (a tablet has no earpiece; a headset only while it is connected). */
    fun available(): List<CallRouteKind> {
        val list = devices()
        return CallRouteKind.entries.filter { kind ->
            when (kind) {
                CallRouteKind.SPEAKER -> true
                CallRouteKind.EARPIECE -> list.any { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE } || (Build.VERSION.SDK_INT < 31 && appContext.packageManager.hasSystemFeature("android.hardware.telephony"))
                else -> list.any { it.type in typeOf(kind) }
            }
        }
    }

    /** Where the sound is going now. */
    fun current(): CallRouteKind {
        if (Build.VERSION.SDK_INT >= 31) {
            val type = audio.communicationDevice?.type
            CallRouteKind.entries.firstOrNull { type != null && type in typeOf(it) }?.let { return it }
        }
        @Suppress("DEPRECATION")
        return when {
            audio.isSpeakerphoneOn -> CallRouteKind.SPEAKER
            audio.isBluetoothScoOn -> CallRouteKind.BLUETOOTH
            devices().any { it.type in typeOf(CallRouteKind.WIRED) } -> CallRouteKind.WIRED
            else -> CallRouteKind.EARPIECE
        }
    }

    /** Sends the sound to this route (a headset that is not there falls through to the next one). */
    fun choose(kind: CallRouteKind) {
        wanted = kind
        apply(kind)
    }

    /** A headset came or went: unless the person chose the speaker, the sound follows the best route there is (a headset that comes goes first, one that goes falls through). */
    private fun reapply() {
        if (wanted == null || wanted == CallRouteKind.SPEAKER) return
        val best = callRouteChoice(available(), false)
        wanted = best
        apply(best)
    }

    private fun apply(kind: CallRouteKind) {
        if (Build.VERSION.SDK_INT >= 31) {
            val device = audio.availableCommunicationDevices.firstOrNull { it.type in typeOf(kind) }
            if (device != null) { if (!runCatching { audio.setCommunicationDevice(device) }.getOrDefault(false)) audio.clearCommunicationDevice() } else audio.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            when (kind) {
                CallRouteKind.SPEAKER -> { audio.stopBluetoothSco(); audio.isBluetoothScoOn = false; audio.isSpeakerphoneOn = true }
                CallRouteKind.BLUETOOTH -> { audio.isSpeakerphoneOn = false; audio.startBluetoothSco(); audio.isBluetoothScoOn = true }
                else -> { audio.stopBluetoothSco(); audio.isBluetoothScoOn = false; audio.isSpeakerphoneOn = false }
            }
        }
    }

    /** The proximity sensor blanks the screen at the ear (a voice call on the earpiece only). */
    fun setProximity(on: Boolean) {
        val power = appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!on) { runCatching { proximity?.takeIf { it.isHeld }?.release() }; proximity = null; return }
        if (proximity?.isHeld == true || !power.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
        proximity = power.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "lime:call-proximity").also { it.setReferenceCounted(false); it.acquire(4 * 60 * 60 * 1000L) }
    }

    /** The speaker (true) or the best other route (a headset, else the earpiece). */
    fun setSpeaker(on: Boolean) = choose(callRouteChoice(available(), on))

    /** The call is over: the phone's audio goes back to what it was. */
    fun stop() {
        stopRingback(); stopRinging(); setProximity(false)
        watching?.let { audio.unregisterAudioDeviceCallback(it) }; watching = null; wanted = null
        if (Build.VERSION.SDK_INT >= 31) audio.clearCommunicationDevice() else @Suppress("DEPRECATION") run { audio.stopBluetoothSco(); audio.isBluetoothScoOn = false; audio.isSpeakerphoneOn = false }
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
