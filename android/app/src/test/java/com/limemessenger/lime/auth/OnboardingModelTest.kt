package com.limemessenger.lime.auth

import com.limemessenger.lime.auth.OnboardingModel.Intent
import com.limemessenger.lime.auth.OnboardingModel.Step
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OnboardingModelTest {
    private var clock = 1_000_000L
    private val auth = FakeAuthService()
    private var completed: Triple<AuthTokens, Profile?, String?>? = null
    private var termsAgreed = 0

    private fun model() = OnboardingModel(auth, now = { clock }, onTermsAgreed = { termsAgreed++ }, onComplete = { t, p, m -> completed = Triple(t, p, m) })

    // Rules (the same cases as iOS's OnboardingModelTests)

    @Test fun classifiesWhatWasTyped() {
        assertTrue(OnboardingModel.classify("") is IdentifierKind.Empty)
        assertTrue(OnboardingModel.classify("ada@example.com") is IdentifierKind.Email)
        assertTrue(OnboardingModel.classify("ada@") is IdentifierKind.Invalid)
        assertTrue(OnboardingModel.classify("a b@example.com") is IdentifierKind.Invalid)
        assertTrue(OnboardingModel.classify("ada@example") is IdentifierKind.Invalid)
        assertTrue(OnboardingModel.classify("ms.park") is IdentifierKind.Username)
        assertTrue(OnboardingModel.classify("@ms.park") is IdentifierKind.Username)
        assertTrue(OnboardingModel.classify("+1 (555) 010-0000") is IdentifierKind.Phone)
        assertTrue(OnboardingModel.classify("ab") is IdentifierKind.Invalid)
    }

    @Test fun usernameRules() {
        assertEquals("Use 3 to 20 characters.", OnboardingModel.usernameError("ab"))
        assertEquals("Use 3 to 20 characters.", OnboardingModel.usernameError("a".repeat(21)))
        assertEquals("Use only letters, numbers, dots and underscores.", OnboardingModel.usernameError("ms park"))
        assertEquals("Use only letters, numbers, dots and underscores.", OnboardingModel.usernameError("müller"))
        assertEquals("A username can't start or end with a dot.", OnboardingModel.usernameError(".abc"))
        assertEquals("A username can't start or end with a dot.", OnboardingModel.usernameError("abc."))
        assertEquals("That username is reserved. Try another.", OnboardingModel.usernameError("Admin"))
        assertNull(OnboardingModel.usernameError("ms.park_2"))
    }

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

    @Test fun codeBoxesAndLengths() {
        val m = model()
        m.code = "123456"; assertTrue(m.canSubmitCode); assertEquals(6, m.codeBoxCount)
        m.code = "1234567"; assertTrue(m.canSubmitCode); assertEquals(8, m.codeBoxCount)
        m.code = "12345"; assertFalse(m.canSubmitCode)
        m.code = "12a456"; assertFalse(m.canSubmitCode)
    }

    @Test fun profileNeedsANameAndAValidOptionalUsername() {
        val m = model()
        assertFalse(m.canSubmitProfile)
        m.displayName = "Ada"; assertTrue(m.canSubmitProfile)
        m.username = "ab"; assertFalse(m.canSubmitProfile); assertEquals("Use 3 to 20 characters.", m.usernameProblem)
        m.username = "@ada.k"; assertTrue(m.canSubmitProfile)
        m.displayName = "x".repeat(41); assertFalse(m.canSubmitProfile)
    }

    // Flows

    @Test fun signInByEmail() = runTest {
        auth.identifyResult = IdentifyResult.ExistingEmail
        val m = model()
        m.start(); assertEquals(Step.Identifier, m.step)
        m.identifier = "Ada@Example.com"
        m.submitIdentifier()
        assertEquals("Sign in as:", m.confirmation!!.title); assertEquals("ada@example.com", m.confirmation!!.detail)
        m.confirmIdentifier(); assertEquals(Step.Password, m.step); assertEquals(Intent.SignIn, m.intent)
        m.password = "correct horse"; m.submitPassword()
        assertEquals(Step.Code, m.step); assertEquals("a•••@example.invalid", m.codeDestination)
        assertEquals(30, m.resendSeconds())
        m.code = "123456"; m.submitCode()
        assertEquals("user-1", completed!!.first.userId); assertEquals("Ada Fake", completed!!.second!!.displayName)
    }

    @Test fun signInByUsernameShowsTheHint() = runTest {
        auth.identifyResult = IdentifyResult.ExistingUsername("s•••@famkind.com")
        val m = model(); m.start(); m.identifier = "@ms.park"; m.submitIdentifier()
        assertEquals("Sign in as @ms.park", m.confirmation!!.title)
        assertEquals("The code goes to s•••@famkind.com", m.confirmation!!.detail)
    }

    @Test fun unknownUsernameHasNoYes() = runTest {
        auth.identifyResult = IdentifyResult.UnknownUsername
        val m = model(); m.start(); m.identifier = "nobody_here"; m.submitIdentifier()
        assertTrue(m.confirmation!!.isUnknownUsername)
        m.confirmIdentifier(); assertEquals(Step.Identifier, m.step)
        m.editIdentifier(); assertNull(m.confirmation)
    }

    @Test fun wrongPasswordAndWrongCodeShowTheServersWords() = runTest {
        val m = model(); m.start(); m.identifier = "ada@example.com"; m.submitIdentifier(); m.confirmIdentifier()
        m.password = "nope nope nope"; m.submitPassword()
        assertEquals("That email, username or password isn't right.", m.errorMessage); assertEquals(Step.Password, m.step)
        m.password = "correct horse"  // typing clears the error
        assertNull(m.errorMessage)
        m.submitPassword()
        m.code = "000000"; m.submitCode()
        assertEquals("That code isn't right.", m.errorMessage); assertNull(completed)
    }

    @Test fun aNetworkFailureSaysSo() = runTest {
        auth.failNext = AuthError.Network
        val m = model(); m.start(); m.identifier = "ada@example.com"; m.submitIdentifier()
        assertEquals("Couldn't reach lime. Check your connection and try again.", m.errorMessage)
        assertFalse(m.isBusy)
    }

    @Test fun resendWaitsThirtySeconds() = runTest {
        val m = model(); m.start(); m.identifier = "ada@example.com"; m.submitIdentifier(); m.confirmIdentifier()
        m.password = "correct horse"; m.submitPassword()
        m.resendCode(); assertFalse(auth.calls.contains("resendSignInCode"))
        clock += 30_000
        assertEquals(0, m.resendSeconds()); m.resendCode()
        assertTrue(auth.calls.contains("resendSignInCode")); assertEquals(30, m.resendSeconds())
        clock += 12_500; assertEquals(18, m.resendSeconds())
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

    @Test fun backStepsAsOnIos() = runTest {
        val m = model(); m.start(); m.identifier = "ada@example.com"; m.submitIdentifier(); m.confirmIdentifier()
        m.password = "correct horse"; m.submitPassword(); assertEquals(Step.Code, m.step)
        m.back(); assertEquals(Step.Password, m.step)   // a sign-in's code goes back to the password
        m.back(); assertEquals(Step.Identifier, m.step)
        m.back(); assertEquals(Step.Welcome, m.step)
    }

    @Test fun forgotPasswordResetsWithTheCode() = runTest {
        val m = model(); m.start(); m.identifier = "ada@example.com"; m.submitIdentifier(); m.confirmIdentifier()
        m.forgotPassword(); assertEquals(Intent.Reset, m.intent); assertEquals(Step.Code, m.step)
        m.code = "123456"; m.submitCode(); assertEquals(Step.Password, m.step)
        m.password = "a brand new one"; m.confirmPassword = "a brand new one"; m.submitPassword()
        assertTrue(auth.calls.contains("finishReset:123456")); assertNotNull(completed)
    }

    @Test fun aSignInWithNoProfileGoesToTheProfileScreen() = runTest {
        auth.profile = null
        val m = model(); m.start(); m.identifier = "ada@example.com"; m.submitIdentifier(); m.confirmIdentifier()
        m.password = "correct horse"; m.submitPassword(); m.code = "123456"; m.submitCode()
        assertEquals(Step.Profile, m.step); assertNull(completed)
    }

    @Test fun tokensRoundTripAndExpire() {
        val t = AuthTokens("a", "r", 10_000_000L, "u")
        assertEquals(t, AuthTokens.fromJson(t.toJson()))
        assertTrue(t.isExpiring(nowMs = 9_950_000L)); assertFalse(t.isExpiring(nowMs = 9_000_000L))
        assertNull(AuthTokens.fromJson("{}"))
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
