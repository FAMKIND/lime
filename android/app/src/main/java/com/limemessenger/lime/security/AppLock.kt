package com.limemessenger.lime.security

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import uniffi.lime_core.LockDelay
import uniffi.lime_core.hidesNotificationText
import uniffi.lime_core.lockDelayFromSeconds
import uniffi.lime_core.lockDelaySeconds
import uniffi.lime_core.shouldLock

/** Asks the system whether it is really the owner: the screen lock (a fingerprint or face, with the PIN, pattern or password as the fallback). */
interface LockAuthenticator {
    suspend fun authenticate(reason: String): Boolean
}

/**
 * The optional lock on lime itself (iOS `AppLock`, LIME-269): off by default. Nothing leaves the device; the check is the system's. The rules (when being
 * away calls for the lock; when notifications hide their words) are the core's `should_lock` / `hides_notification_text`; this keeps the state and the choices.
 * While it is on, the window is `FLAG_SECURE` (MainActivity) so the recent-apps picture and screenshots never show chats.
 */
class AppLock(
    private val prefs: SharedPreferences,
    var authenticator: LockAuthenticator = object : LockAuthenticator { override suspend fun authenticate(reason: String) = false },
    private val clock: () -> Long = { System.currentTimeMillis() },
) {
    var isEnabled by mutableStateOf(prefs.getBoolean(ENABLED, false))
        private set
    var delay by mutableStateOf(lockDelayFromSeconds(prefs.getInt(DELAY, 0).toUInt()))
        private set

    /** The lock screen is up. A cold start with the lock on asks first. */
    var isLocked by mutableStateOf(isEnabled)
        private set

    /** The app is not in front (or something is over it): nothing of the chats may show. */
    var isCovered by mutableStateOf(false)
        private set

    private var leftAtMs: Long? = null
    private var authenticating = false

    fun changeDelay(value: LockDelay) {
        delay = value
        prefs.edit().putInt(DELAY, lockDelaySeconds(value).toInt()).apply()
    }

    /** Turning it on asks the system once (a phone with no screen lock says so) and only then switches on. */
    suspend fun turnOn(): Boolean {
        if (!authenticator.authenticate("Turn on Lock lime")) return false
        isEnabled = true
        prefs.edit().putBoolean(ENABLED, true).apply()
        return true
    }

    fun turnOff() {
        isEnabled = false
        prefs.edit().putBoolean(ENABLED, false).apply()
        isLocked = false
        isCovered = false
    }

    /** Nobody is signed in: there is nothing to cover. (The setting stays; the lock comes back with the next cold start.) */
    fun turnOffForSignedOut() { isLocked = false; isCovered = false }

    // Scene changes (the activity's lifecycle)

    /** Something is over the app or it is leaving: cover it (the recent-apps picture is taken now). */
    fun sceneBecameInactive() { if (isEnabled) isCovered = true }

    fun sceneEnteredBackground() {
        if (!isEnabled) return
        isCovered = true
        if (leftAtMs == null) leftAtMs = clock()
        if (delay == LockDelay.IMMEDIATELY) isLocked = true
    }

    fun sceneBecameActive() {
        if (!isEnabled) { isLocked = false; isCovered = false; return }
        val left = leftAtMs
        if (left != null && shouldLock(clock() - left, delay)) isLocked = true
        leftAtMs = null
        if (!isLocked) isCovered = false
    }

    /** Asks the system and opens lime when it passes. Calling it twice at once asks once. */
    suspend fun unlock() {
        if (!isLocked || authenticating) return
        authenticating = true
        try {
            if (authenticator.authenticate("Unlock lime")) { isLocked = false; isCovered = false }
        } finally {
            authenticating = false
        }
    }

    /** Notifications and banners show no message words while the lock is on and lime is locked, or away long enough to be locked. */
    fun hidesNotificationText(): Boolean = hidesNotificationText(isEnabled, isLocked, leftAtMs, clock(), delay)

    companion object {
        const val ENABLED = "lock.enabled"
        const val DELAY = "lock.delay"
    }
}
