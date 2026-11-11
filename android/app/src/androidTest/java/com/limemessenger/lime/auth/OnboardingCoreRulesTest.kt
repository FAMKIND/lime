package com.limemessenger.lime.auth

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.limemessenger.lime.auth.OnboardingModel.Intent
import com.limemessenger.lime.auth.OnboardingModel.Step
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * LIME-400: the onboarding tests that touch rules which moved into LimeCore (the password checks, the connection words, the terms version), run on a device
 * because those rules are native now. The assertions are the ones the JVM tests had.
 */
@RunWith(AndroidJUnit4::class)
class OnboardingCoreRulesTest {
    private var clock = 1_000_000L
    private val auth = FakeAuthService()
    private var completed: Triple<AuthTokens, Profile?, String?>? = null
    private var termsAgreed = 0

    private fun model() = OnboardingModel(auth, now = { clock }, onTermsAgreed = { termsAgreed++ }, onComplete = { t, p, m -> completed = Triple(t, p, m) })

    @Test fun passwordChecksAndHints() {
        assertEquals("At least 10 characters.", PasswordChecks("", "", true).hint)
        assertEquals("4 more to go.", PasswordChecks("abcdef", "", true).hint)
        assertEquals(PasswordChecks.Strength.TooShort, PasswordChecks("short", "", true).strength)
        assertEquals(PasswordChecks.Strength.Fair, PasswordChecks("abcdefghij", "", true).strength)
        assertEquals(PasswordChecks.Strength.Good, PasswordChecks("Abcdefghi1", "", true).strength)
        assertEquals(PasswordChecks.Strength.Strong, PasswordChecks("a-long-passphrase-of-words", "", true).strength)
        assertEquals("Good. A few random words make a good password.", PasswordChecks("Abcdefghi1", "", true).hint)
        assertFalse(PasswordChecks("abcdefghij", "abcdefghi", true).isAcceptable)
        assertTrue(PasswordChecks("abcdefghij", "abcdefghij", true).isAcceptable)
        assertTrue(PasswordChecks("abcdefghij", "", false).matches) // signing in needs no confirmation
    }
    @Test fun signUpGoesCodeTermsPasswordProfile() = runTest {
        auth.identifyResult = IdentifyResult.NewEmail; auth.profile = null
        val m = model(); m.start(); m.identifier = "new@example.com"; m.submitIdentifier()
        assertEquals("We'll send a code to:", m.confirmation!!.title)
        m.confirmIdentifier(); assertEquals(Step.Code, m.step); assertEquals("new@example.com", m.codeDestination)
        m.code = "123456"; m.submitCode(); assertEquals(Step.Terms, m.step)
        m.agreeToTerms(); assertEquals(1, termsAgreed); assertEquals(Step.Password, m.step)
        m.password = "abcdefghij"; m.confirmPassword = "abcdefghi"; assertFalse(m.canSubmitPassword)
        m.confirmPassword = "abcdefghij"; m.submitPassword(); assertEquals(Step.Profile, m.step)
        m.displayName = "New Teacher"; m.username = "@new.teacher"; m.school = " Park School "
        m.submitProfile()
        assertTrue(auth.calls.contains("saveProfile:New Teacher:new.teacher:Park School"))
        assertEquals("New Teacher", completed!!.second!!.displayName)
    }
    @Test fun forgotPasswordResetsWithTheCode() = runTest {
        val m = model(); m.start(); m.identifier = "ada@example.com"; m.submitIdentifier(); m.confirmIdentifier()
        m.forgotPassword(); assertEquals(Intent.Reset, m.intent); assertEquals(Step.Code, m.step)
        m.code = "123456"; m.submitCode(); assertEquals(Step.Password, m.step)
        m.password = "a brand new one"; m.confirmPassword = "a brand new one"; m.submitPassword()
        assertTrue(auth.calls.contains("finishReset:123456")); assertNotNull(completed)
    }
    @Test fun connectionProblemWords() {
        assertEquals(ConnectionProblem.Offline, ConnectionProblem.from(AuthError.Network))
        assertEquals(ConnectionProblem.SessionEnded, ConnectionProblem.from(AuthError.NotVerified))
        assertEquals(ConnectionProblem.Busy, ConnectionProblem.from(AuthError.TooSoon("x")))
        assertEquals(ConnectionProblem.Server, ConnectionProblem.from(AuthError.Unavailable))
        assertEquals(ConnectionProblem.Other, ConnectionProblem.from(RuntimeException()))
        assertTrue(ConnectionProblem.SessionEnded.needsSignIn)
    }
}
