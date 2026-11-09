package com.limemessenger.lime.auth

import org.json.JSONObject

// ANDROID DEBT: twin of ios/Lime/Core/Auth/AuthModels.swift; moves into LimeCore in LIME-133

/** The tokens of a signed-in session. They live in the sealed secret store, this device only. */
data class AuthTokens(val accessToken: String, val refreshToken: String, val expiresAtMs: Long, val userId: String) {
    /** Refresh a little early so a call never goes out with a token about to expire. */
    fun isExpiring(nowMs: Long = System.currentTimeMillis(), marginMs: Long = 120_000): Boolean = expiresAtMs - nowMs < marginMs

    fun toJson(): String = JSONObject().put("accessToken", accessToken).put("refreshToken", refreshToken)
        .put("expiresAt", expiresAtMs).put("userID", userId).toString()

    companion object {
        fun fromJson(text: String): AuthTokens? = try {
            val o = JSONObject(text)
            AuthTokens(o.getString("accessToken"), o.getString("refreshToken"), o.getLong("expiresAt"), o.getString("userID"))
        } catch (e: Exception) {
            null
        }
    }
}

/** What the first screen's one question turned out to be. */
sealed class IdentifyResult {
    object ExistingEmail : IdentifyResult()
    object NewEmail : IdentifyResult()

    /** A username with an account; `hint` is the masked email the code goes to ("s•••@famkind.com"). */
    data class ExistingUsername(val hint: String) : IdentifyResult()
    object UnknownUsername : IdentifyResult()
}

/** The password step of signing in: the session (which can do nothing until the code is verified) and where the code was sent. */
data class PasswordSignIn(val tokens: AuthTokens, val maskedEmail: String)

data class Profile(
    val displayName: String,
    val username: String? = null,
    val school: String? = null,
    val aboutEmoji: String? = null,
    val aboutText: String? = null,
    val hideFromSearch: Boolean = false,
    val maskedEmail: String? = null,
) {
    /** The About line as one string for a list or a card ("👋 Happy to help"), or null when empty. */
    val about: String? get() = listOfNotNull(aboutEmoji, aboutText).filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() }?.joinToString(" ")

    fun toJson(): String = JSONObject().put("displayName", displayName).put("username", username).put("school", school)
        .put("aboutEmoji", aboutEmoji).put("aboutText", aboutText).put("hideFromSearch", hideFromSearch).put("maskedEmail", maskedEmail).toString()

    companion object {
        const val MAX_NAME_LENGTH = 40
        const val MAX_ABOUT_LENGTH = 140

        fun fromJson(text: String): Profile? = try {
            val o = JSONObject(text)
            fun s(k: String) = if (o.isNull(k)) null else o.getString(k)
            Profile(o.getString("displayName"), s("username"), s("school"), s("aboutEmoji"), s("aboutText"), o.optBoolean("hideFromSearch"), s("maskedEmail"))
        } catch (e: Exception) {
            null
        }
    }
}

data class ProfileDraft(
    val displayName: String,
    val username: String? = null,
    val school: String? = null,
    val aboutEmoji: String? = null,
    val aboutText: String? = null,
    val hideFromSearch: Boolean? = null,
)

/** Everything that can go wrong, in the words the screens show. */
sealed class AuthError(override val message: String) : Exception(message) {
    object InvalidCredentials : AuthError("That email, username or password isn't right.")
    class BadCode(message: String) : AuthError(message)
    object Locked : AuthError("Too many wrong codes. Go back and start again to get a new one.")
    class TooSoon(message: String) : AuthError(message)
    object AccountExists : AuthError("That email already has an account. Sign in instead.")
    object NotFound : AuthError("No account with that username.")
    object WeakPassword : AuthError("Use at least 10 characters.")
    object UsernameTaken : AuthError("That username is taken. Try another.")
    class BadUsername(message: String) : AuthError(message)
    object RateLimited : AuthError("Too many tries. Wait a moment and try again.")
    object EmailFailed : AuthError("We couldn't send the code. Try again in a moment.")
    object Network : AuthError("Couldn't reach lime. Check your connection and try again.")

    /** The server answered with a 5xx: it, not the phone's connection, is the problem. */
    object Unavailable : AuthError("lime's server had a problem. Try again in a moment.")
    object NotVerified : AuthError("Finish signing in first.")
    class Server(message: String) : AuthError(message)
}
