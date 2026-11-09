package com.limemessenger.lime.auth

import uniffi.lime_core.StoreException

// ANDROID DEBT: twin of ios/Lime/Core/Network/ConnectionProblem.swift; moves into LimeCore in LIME-133

/** Why talking to the backend failed, in words that are true. "Check your connection" is for a real connection failure only. */
enum class ConnectionProblem(val message: String) {
    SessionEnded("Your session has ended. Please sign in again."),
    Offline("You're offline. Check your connection and try again."),
    Busy("Too many requests. Wait a minute and try again."),
    Server("lime's server had a problem. Try again in a moment."),
    Other("Something went wrong. Try again.");

    /** Only an ended session needs the person to do something (sign in again). */
    val needsSignIn: Boolean get() = this == SessionEnded

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
