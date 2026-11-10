package com.limemessenger.lime

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.AccountSession.Phase
import com.limemessenger.lime.auth.FakeAuthService
import com.limemessenger.lime.auth.IdentifyResult
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.Root
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Every step of the sign-in and sign-up screens against a fake auth service (as iOS's UI tests use `FakeAuthService`). */
@RunWith(AndroidJUnit4::class)
class SignInUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val auth = FakeAuthService()
    private lateinit var dir: File
    private lateinit var session: AccountSession
    private val alias = "lime.test.ui"

    @Before fun setUp() {
        dir = File(context.cacheDir, "ui-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        session = AccountSession(auth, backend = null, storage = StorageBootstrap(File(dir, "data"), secrets), secrets = secrets)
    }

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun show(fontScale: Float = 1f) = rule.setContent {
        val d = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(d.density, fontScale)) {
            LimeTheme { Root(session) }
        }
    }

    private fun tag(t: String) = rule.onNodeWithTag(t)
    private fun type(t: String, text: String) { tag(t).performTextInput(text) }
    private fun next() { tag("onboarding-next").performClick() }

    private fun toPassword(identifier: String = "ada@example.com") {
        tag("welcome-continue").performClick()
        type("identifier-field", identifier); next()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("confirm-yes") > 0 }
        tag("confirm-yes").performClick()
    }

    private fun ComposeContentTestRule.onAllNodesWithTagCount(t: String) = onAllNodes(androidx.compose.ui.test.hasTestTag(t)).fetchSemanticsNodes().size

    @Test fun welcomeShowsTheWordsAndContinues() {
        show()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("welcome-headline") > 0 }
        tag("welcome-headline").assertTextEquals("Connect All Teachers")
        rule.onNodeWithText("A secure messenger made for teachers.").assertIsDisplayed()
        tag("welcome-continue").performClick()
        tag("onboarding-title").assertTextEquals("Your email or username")
        tag("onboarding-next").assertIsNotEnabled()
    }

    @Test fun signInWithPasswordThenCodeThenSignOut() {
        show()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("welcome-continue") > 0 }
        toPassword()
        tag("onboarding-title").assertTextEquals("Enter your password")
        type("password-field", "correct horse"); next()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("code-field") > 0 }
        tag("onboarding-subtitle").assertTextContains("a•••@example.invalid", substring = true)
        type("code-field", "123456"); next()
        rule.waitUntil(10_000) { rule.onAllNodesWithTagCount("my-avatar") > 0 }
        assertEquals(Phase.SignedIn, session.phase)
        tag("my-avatar").performClick()
        rule.onNodeWithTag("settings-name", useUnmergedTree = true).assertTextEquals("Ada Fake")
        tag("settings-sign-out").performScrollTo().performClick()
        tag("sign-out-confirm").performClick()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("welcome-continue") > 0 }
        assertTrue(auth.calls.contains("signOut"))
        assertEquals(Phase.SignedOut, session.phase)
    }

    @Test fun aWrongPasswordAndAWrongCodeShowTheirMessages() {
        show()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("welcome-continue") > 0 }
        toPassword()
        type("password-field", "wrong wrong"); next()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("error-message") > 0 }
        tag("error-message").assertTextEquals("That email, username or password isn't right.")
        tag("password-field").performTextInput("") // still on the password screen
        tag("onboarding-title").assertTextEquals("Enter your password")
    }

    @Test fun wrongCodeAndResendCountdown() {
        show()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("welcome-continue") > 0 }
        toPassword()
        type("password-field", "correct horse"); next()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("code-field") > 0 }
        tag("resend-code").assertIsNotEnabled()
        rule.onNodeWithText("Resend code in", substring = true).assertIsDisplayed()
        type("code-field", "000000")  // six digits fill the boxes and submit by themselves
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("error-message") > 0 }
        tag("error-message").assertTextEquals("That code isn't right.")
    }

    @Test fun signUpAsksForTheTermsBeforeThePassword() {
        auth.identifyResult = IdentifyResult.NewEmail; auth.profile = null
        show()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("welcome-continue") > 0 }
        toPassword("new@example.com")
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("code-field") > 0 }
        type("code-field", "123456")
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("terms-agree") > 0 }
        tag("terms-continue").assertIsNotEnabled()
        tag("terms-agree").performClick()
        tag("terms-continue").assertIsEnabled().performClick()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("confirm-password-field") > 0 }
        type("password-field", "abcdefghij"); type("confirm-password-field", "abcdefghi")
        tag("password-mismatch").assertIsDisplayed()
        tag("confirm-password-field").performTextInput("j")
        next()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("name-field") > 0 }
        type("name-field", "New Teacher"); next()
        rule.waitUntil(10_000) { rule.onAllNodesWithTagCount("my-avatar") > 0 }
        tag("my-avatar").performClick()
        rule.onNodeWithTag("settings-name", useUnmergedTree = true).assertTextEquals("New Teacher")
        assertEquals("New Teacher", session.profile?.displayName)
    }

    @Test fun anUnknownUsernameOffersTheEmailInstead() {
        auth.identifyResult = IdentifyResult.UnknownUsername
        show()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("welcome-continue") > 0 }
        tag("welcome-continue").performClick()
        type("identifier-field", "nobody_here"); next()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("confirm-edit") > 0 }
        tag("confirmation-detail").assertTextEquals("Check the spelling, or use your email.")
        tag("confirm-edit").performClick()
        tag("onboarding-title").assertTextEquals("Your email or username")
    }

    @Test fun theLargestFontStillShowsTheTitleAndTheNextButton() {
        show(fontScale = 2f)
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("welcome-continue") > 0 }
        tag("welcome-continue").assertIsDisplayed().performClick()
        tag("onboarding-title").assertIsDisplayed()
        tag("onboarding-next").assertIsDisplayed()
        tag("identifier-field").assertIsDisplayed()
    }

    @Test fun backAndNextHaveTalkBackLabelsAndTheTitleIsAHeading() {
        show()
        rule.waitUntil(5_000) { rule.onAllNodesWithTagCount("welcome-continue") > 0 }
        tag("welcome-continue").performClick()
        rule.onNodeWithContentDescriptionCompat("Back").assertIsDisplayed()
        rule.onNodeWithContentDescriptionCompat("Next").assertIsDisplayed()
        val title = tag("onboarding-title").fetchSemanticsNode()
        assertTrue(title.config.contains(androidx.compose.ui.semantics.SemanticsProperties.Heading))
    }

    private fun ComposeContentTestRule.onNodeWithContentDescriptionCompat(label: String) =
        onNode(androidx.compose.ui.test.hasContentDescription(label))
}
