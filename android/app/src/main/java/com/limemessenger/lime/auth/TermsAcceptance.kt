package com.limemessenger.lime.auth

import android.content.Context

// ANDROID DEBT: twin of ios/Lime/Core/Auth/TermsAcceptance.swift; moves into LimeCore in LIME-133

/** What a teacher agreed to at sign-up (LIME-283): the terms version and the date, kept on this phone only. Nothing about it is sent anywhere. */
object TermsAcceptance {
    /** Change this when the terms change in a way people must agree to again. */
    const val CURRENT_VERSION = "terms-2026-11"
    const val TERMS_URL = "https://limemessenger.com/terms"
    const val PRIVACY_URL = "https://limemessenger.com/privacy"
    const val GUIDELINES_URL = "https://limemessenger.com/guidelines"
    const val SAFETY_URL = "https://limemessenger.com/safety"

    private const val PREFS = "lime.terms"

    fun record(context: Context, nowMs: Long = System.currentTimeMillis()) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("version", CURRENT_VERSION).putLong("date", nowMs).apply()
    }

    fun accepted(context: Context): String? = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("version", null)
}
