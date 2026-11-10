package com.limemessenger.lime

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.AccountSession.Phase
import com.limemessenger.lime.auth.AuthError
import com.limemessenger.lime.auth.AuthTokens
import com.limemessenger.lime.auth.FakeAuthService
import com.limemessenger.lime.auth.Profile
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.Samples
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.jam.JamFeedScreen
import com.limemessenger.lime.ui.jam.JamReaderScreen
import com.limemessenger.lime.ui.profile.PersonProfileScreen
import com.limemessenger.lime.ui.settings.SettingsScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.PublicProfile

/** Settings (edit my profile, About lime, sign out), another person's profile, and the read-only jam feed, against fakes. */
@RunWith(AndroidJUnit4::class)
class SettingsJamProfileUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val auth = FakeAuthService()
    private lateinit var dir: File
    private lateinit var session: AccountSession
    private val alias = "lime.test.settings"
    private var closed = false

    @Before fun setUp() {
        dir = File(context.cacheDir, "settings-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        session = AccountSession(auth, backend = null, storage = StorageBootstrap(File(dir, "data"), secrets), secrets = secrets)
        runBlocking {
            session.completeSignIn(AuthTokens("a", "r", System.currentTimeMillis() + 3_600_000, "ada-id"), Profile("Ada Android", "ada_android", "Park School", "👋", "Happy to help", maskedEmail = "a•••@example.invalid"))
        }
    }

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun settings() = rule.setContent { LimeTheme { SettingsScreen(session, onClose = { closed = true }) } }

    @Test fun theProfileCardShowsMeAndTheRowsShowMyFields() {
        settings()
        rule.onNodeWithTag("settings-name", useUnmergedTree = true).assertTextEquals("Ada Android")
        rule.onNodeWithTag("settings-about-line", useUnmergedTree = true).assertTextEquals("👋 Happy to help")
        rule.onNodeWithTag("settings-row-username", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithTag("settings-row-email", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test fun editingMyNameSavesTheWholeProfileAndTheCardUpdates() {
        settings()
        rule.onNodeWithTag("settings-row-name").performClick()
        rule.onNodeWithTag("editor-title", useUnmergedTree = true).assertTextEquals("Edit Name")
        rule.onNodeWithTag("editor-save").assertIsNotEnabled()
        rule.onNodeWithTag("editor-field").performTextClearance()
        rule.onNodeWithTag("editor-field").performTextInput("Ada Kay")
        rule.onNodeWithTag("editor-save").assertIsEnabled().performClick()
        rule.waitUntil(5_000) { session.profile?.displayName == "Ada Kay" }
        assertEquals("Ada Android", auth.lastDraft?.let { "Ada Android" })   // the draft went through the service
        assertEquals("ada_android", auth.lastDraft?.username); assertEquals("Park School", auth.lastDraft?.school); assertEquals("Happy to help", auth.lastDraft?.aboutText)
        rule.waitUntil(5_000) { count("field-editor") == 0 }
        rule.onNodeWithTag("settings-name", useUnmergedTree = true).assertTextEquals("Ada Kay")
    }

    @Test fun aboutTakesAPresetAndAnEmptyNameIsRefusedInWords() {
        settings()
        rule.onNodeWithTag("settings-row-about").performClick()
        rule.onNodeWithTag("preset-Grading").performClick()
        rule.onNodeWithTag("editor-save").assertIsEnabled().performClick()
        rule.waitUntil(5_000) { session.profile?.about == "📝 Grading" }
        rule.waitUntil(5_000) { count("field-editor") == 0 }
        rule.onNodeWithTag("settings-row-name").performClick()
        rule.onNodeWithTag("editor-field").performTextClearance()
        rule.waitUntil(5_000) { count("editor-error") > 0 }
        rule.onNodeWithTag("editor-error", useUnmergedTree = true).assertTextEquals("Your name can't be empty.")
        rule.onNodeWithTag("editor-save").assertIsNotEnabled()
    }

    @Test fun aServerRefusalIsShownInTheEditor() {
        settings()
        rule.onNodeWithTag("settings-row-username").performClick()
        rule.onNodeWithTag("editor-field").performTextClearance()
        rule.onNodeWithTag("editor-field").performTextInput("taken_one")
        auth.failNext = AuthError.UsernameTaken
        rule.onNodeWithTag("editor-save").performClick()
        rule.waitUntil(5_000) { count("editor-error") > 0 }
        rule.onNodeWithTag("editor-error", useUnmergedTree = true).assertTextEquals("That username is taken. Try another.")
        assertEquals("ada_android", session.profile?.username)
    }

    @Test fun aboutLimeShowsTheVersionsAndSignOutTellsTheTruthThenSignsOut() {
        settings()
        rule.onNodeWithTag("settings-row-about-lime").performScrollTo().performClick()
        rule.onNodeWithTag("about-version", useUnmergedTree = true).assertTextEquals("Version ${BuildConfig.VERSION_NAME}")
        rule.onNodeWithTag("about-core", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithTag("about-terms").assertIsDisplayed()
        rule.onNodeWithTag("about-back").performClick()
        rule.onNodeWithTag("settings-sign-out").performScrollTo().performClick()
        rule.onNodeWithTag("sign-out-confirm").assertIsDisplayed()
        rule.onNodeWithTag("sign-out-confirm-cancel").performClick()
        assertEquals(Phase.SignedIn, session.phase)
        rule.onNodeWithTag("settings-sign-out").performScrollTo().performClick()
        rule.onNodeWithTag("sign-out-confirm").performClick()
        rule.waitUntil(5_000) { session.phase == Phase.SignedOut }
        assertTrue(auth.calls.contains("signOut"))
    }

    @Test fun anotherPersonsProfileIsShownReadOnly() {
        val ben = PublicProfile("ben-id", "Ben Android", "ben_android", "North High", "☕", "Coffee lover", null, false)
        rule.setContent { LimeTheme { PersonProfileScreen("ben-id", "Ben", chats = ChatsModel({ null }, { null }, { "" }, { "" }), onBack = { closed = true }, load = { ben }) } }
        rule.waitUntil(5_000) { count("profile-username") > 0 }
        rule.onNodeWithTag("profile-name", useUnmergedTree = true).assertTextEquals("Ben Android")
        rule.onNodeWithTag("profile-username", useUnmergedTree = true).assertTextEquals("@ben_android")
        rule.onNodeWithTag("profile-school", useUnmergedTree = true).assertTextEquals("North High")
        rule.onNodeWithTag("profile-about", useUnmergedTree = true).assertTextEquals("☕ Coffee lover")
        rule.onNodeWithTag("profile-back").performClick()
        assertTrue(closed)
    }

    @Test fun aPersonWithNoProfileYetSaysSo() {
        rule.setContent { LimeTheme { PersonProfileScreen("x", "Someone", chats = ChatsModel({ null }, { null }, { "" }, { "" }), onBack = {}, load = { null }) } }
        rule.waitUntil(5_000) { count("profile-none") > 0 }
        rule.onNodeWithTag("profile-name", useUnmergedTree = true).assertTextEquals("Someone")
    }

    // The jam tab, read only

    @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
    @Test fun theJamFeedListsPostsNewestFirstAndOpensOne() {
        val jams = listOf(Samples.jam("j1", "Bell Ringer"))
        val posts = listOf(
            Samples.jamPost("old", "j1", at = 1_000, plain = "An older quick post"),
            Samples.jamPost("new", "j1", at = 2_000, kind = "article", title = "Planning a unit", subtitle = "Start from the end", plain = "Start from the end. Then work back.", markdown = "# Heading\n\nStart from the end.\n\n- one\n- two"),
        )
        val model = JamModel({ null }, nameOf = { if (it == "writer1") "Ada Android" else null }, source = { jams to posts })
        var opened: String? = null
        rule.setContent { LimeTheme { JamFeedScreen(model) { opened = it.postId } } }
        rule.waitUntil(5_000) { model.posts.size == 2 }
        assertEquals(listOf("new", "old"), model.posts.map { it.postId })
        val description = rule.onNodeWithTag("jam-post-new").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString()
        assertTrue(description, description.startsWith("Ada Android, ") && description.contains("Planning a unit"))
        rule.onNodeWithTag("jam-post-new").performClick()
        assertEquals("new", opened)
    }

    @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
    @Test fun anEmptyJamFeedSaysHowToGetPosts() {
        val model = JamModel({ null }, nameOf = { null }, source = { emptyList<uniffi.lime_core.JamInfo>() to emptyList() })
        rule.setContent { LimeTheme { JamFeedScreen(model) {} } }
        rule.waitUntil(5_000) { count("jam-feed-empty") > 0 }
        rule.onNodeWithTag("jam-feed-empty", useUnmergedTree = true).assertTextEquals("Subscribe to teachers from their profiles. Your posts show here too.")
    }

    @Test fun theReaderShowsTheTitleBylineAndFormattedText() {
        val post = Samples.jamPost("a", "j1", kind = "article", title = "Planning a unit", subtitle = "Start from the end", markdown = "Start from the **end**.\n\n- one\n- two", coauthors = listOf("lee"))
        val model = JamModel({ null }, nameOf = { if (it == "lee") "Lee Wong" else "Ada Android" }, source = { listOf(Samples.jam("j1")) to listOf(post) })
        runBlocking { model.reload() }
        var back = false
        rule.setContent { LimeTheme { JamReaderScreen(post, model) { back = true } } }
        rule.onNodeWithTag("jam-reader").assertIsDisplayed()
        rule.onNodeWithTag("jam-reader-byline", useUnmergedTree = true).assertTextEquals("Ada Android · with Lee Wong · ${com.limemessenger.lime.jam.JamDates.short(1_000L)}")
        rule.onNodeWithTag("jam-reader-back").performClick()
        assertTrue(back)
    }
}
