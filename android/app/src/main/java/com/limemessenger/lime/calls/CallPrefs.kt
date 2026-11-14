package com.limemessenger.lime.calls

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Settings → Calls (iOS `CallSettings`), kept on this phone and never sent: less data for video, and how loud the other people sound (half to double). They take
 * effect in a call from LIME-425 on. ("Include in Recents" is the iPhone's Phone app: it has no Android twin.)
 */
class CallPrefs(private val prefs: SharedPreferences) {
    var lowDataMode by mutableStateOf(prefs.getBoolean(LOW_DATA, false))
        private set
    var volume by mutableDoubleStateOf(clamp(prefs.getFloat(VOLUME, 1f).toDouble()))
        private set

    fun changeLowData(on: Boolean) { lowDataMode = on; prefs.edit().putBoolean(LOW_DATA, on).apply() }
    fun changeVolume(value: Double) { volume = clamp(value); prefs.edit().putFloat(VOLUME, volume.toFloat()).apply() }

    companion object {
        const val LOW_DATA = "calls.lowdata"
        const val VOLUME = "calls.volume"
        val VOLUME_RANGE = 0.5..2.0
        fun clamp(value: Double) = value.coerceIn(VOLUME_RANGE.start, VOLUME_RANGE.endInclusive)
        /** "100%" (the slider's value, spoken the same way). */
        fun percent(volume: Double): String = "${Math.round(volume * 100)}%"
    }
}
