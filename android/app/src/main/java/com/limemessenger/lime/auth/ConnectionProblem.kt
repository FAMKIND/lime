package com.limemessenger.lime.auth

import uniffi.lime_core.StoreException

// The words and the "needs sign-in" rule are the core's (LIME-400: auth_rules.rs); which failure is which stays here (these are this platform's own errors).

/** Why talking to the backend failed, in words that are true. "Check your connection" is for a real connection failure only. */
enum class ConnectionProblem {
    SessionEnded, Offline, Busy, Server, Other;

    private val trouble: uniffi.lime_core.ConnectionTrouble get() = when (this) {
        SessionEnded -> uniffi.lime_core.ConnectionTrouble.SESSION_ENDED
        Offline -> uniffi.lime_core.ConnectionTrouble.OFFLINE
        Busy -> uniffi.lime_core.ConnectionTrouble.BUSY
        Server -> uniffi.lime_core.ConnectionTrouble.SERVER
        Other -> uniffi.lime_core.ConnectionTrouble.OTHER
    }

    val message: String get() = uniffi.lime_core.connectionTroubleWords(trouble)

    /** Only an ended session needs the person to do something (sign in again). */
    val needsSignIn: Boolean get() = uniffi.lime_core.connectionTroubleNeedsSignIn(trouble)

    companion object {
        fun from(error: Throwable): ConnectionProblem = when (error) {
            is StoreException.Unauthorized -> SessionEnded
            is StoreException.Network -> Offline
            is StoreException.RateLimited -> Busy
            is StoreException.Unavailable -> Server
            is AuthError -> when (error) {
                is AuthError.NotVerified -> SessionEnded
                is AuthError.Network -> Offline
                is AuthError.RateLimited, is AuthError.TooSoon -> Busy
                is AuthError.Unavailable -> Server
                else -> Other
            }
            else -> Other
        }
    }
}
