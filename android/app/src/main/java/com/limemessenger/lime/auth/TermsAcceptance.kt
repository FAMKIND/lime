package com.limemessenger.lime.auth

import android.content.Context

// The version and the legal pages are the core's (LIME-400: auth_rules.rs); where the acceptance is kept stays with the platform.

/** What a teacher agreed to at sign-up (LIME-283): the terms version and the date, kept on this phone only. Nothing about it is sent anywhere. */
object TermsAcceptance {
    /** Change this when the terms change in a way people must agree to again. */
    val CURRENT_VERSION: String get() = uniffi.lime_core.termsCurrentVersion()
    val TERMS_URL: String get() = uniffi.lime_core.legalLinks().terms
    val PRIVACY_URL: String get() = uniffi.lime_core.legalLinks().privacy
    val GUIDELINES_URL: String get() = uniffi.lime_core.legalLinks().guidelines
    val SAFETY_URL: String get() = uniffi.lime_core.legalLinks().safety

    private const val PREFS = "lime.terms"

    fun record(context: Context, nowMs: Long = System.currentTimeMillis()) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("version", CURRENT_VERSION).putLong("date", nowMs).apply()
    }

    fun accepted(context: Context): String? = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("version", null)
}
