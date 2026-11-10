package com.limemessenger.lime.chats

import android.content.SharedPreferences
import androidx.compose.runtime.mutableStateMapOf
import uniffi.lime_core.MuteDuration
import uniffi.lime_core.isMutedUntil
import uniffi.lime_core.muteEndMs

/**
 * Which chats this phone has muted and until when. Kept in the app's private preferences (as iOS keeps it in UserDefaults: not secret, never sent
 * anywhere); the rules (how long, when it ends) are the core's `mute_end_ms` / `is_muted_until`.
 */
class MuteSettings(private val prefs: SharedPreferences, private val clock: () -> Long = { System.currentTimeMillis() }) {
    private val until = mutableStateMapOf<String, Long>()

    init {
        for ((key, value) in prefs.all) if (key.startsWith(PREFIX) && value is Long) until[key.removePrefix(PREFIX)] = value
    }

    fun isMuted(conversationId: String): Boolean = isMutedUntil(until[conversationId], clock())

    fun mute(conversationId: String, duration: MuteDuration) {
        val end = muteEndMs(duration, clock())
        until[conversationId] = end
        prefs.edit().putLong(PREFIX + conversationId, end).apply()
    }

    fun unmute(conversationId: String) {
        until.remove(conversationId)
        prefs.edit().remove(PREFIX + conversationId).apply()
    }

    /** The chats muted now. */
    fun mutedIds(): List<String> = until.filterValues { isMutedUntil(it, clock()) }.keys.toList()

    private companion object {
        const val PREFIX = "muted:"
    }
}
