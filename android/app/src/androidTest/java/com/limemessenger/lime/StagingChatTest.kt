package com.limemessenger.lime

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.AccountSession.Phase
import com.limemessenger.lime.auth.LiveAuthService
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.net.BackendConfig
import com.limemessenger.lime.net.HttpTransport
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.Root
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The end-to-end proof on STAGING: Ada (this emulator) and Ben (the host-side partner, `android/tools/partner`, running `echo`) exchange
 * end-to-end encrypted messages. Needs the pushed test accounts and a running partner (tools/connected.sh does both), so it is skipped without them.
 * NEEDS THE PARTNER RUNNING (`partner/run reset` on a fresh sign-in, then `partner/run echo`): with accounts pushed but no partner it does not skip, it times out after 120 s.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingChatTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.chat.staging"
    private val dir = File(context.cacheDir, "staging-chat-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size

    @Test fun adaAndBenExchangeMessagesThroughStaging() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val benId = JSONObject(pushed.readText()).getJSONObject("accounts").getJSONObject("b").getString("user_id")
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets)
        rule.setContent { LimeTheme { Root(session) } }

        // Sign in as Ada through the debug test sign-in; her device registers.
        rule.waitUntil(15_000) { count("use-test-account") > 0 }
        rule.onNodeWithTag("use-test-account").performClick()
        rule.onNodeWithTag("test-account-ada_android").performClick()
        try {
            rule.waitUntil(60_000) { session.phase == Phase.SignedIn && (session.deviceRegistered || session.problem != null) }
        } catch (e: Throwable) {
            throw AssertionError("sign-in stalled: phase=${session.phase} registered=${session.deviceRegistered} problem=${session.problem}", e)
        }
        assertEquals("registration problem: ${session.problem}", true, session.deviceRegistered)

        // Ada starts the chat as the new-chat screen will (LIME-299): her first message to Ben, through the core.
        val core = session.store!!
        val token = runBlocking { session.accessToken() }
        core.sendTextIdentified(session.transport!!, token, benId, "Hello Ben")

        // Ben (echo) accepts and answers; the list's sync loop brings the answer in and the chat shows up.
        val row = "conversation-row-dm:$benId"
        rule.waitUntil(120_000) { count(row) > 0 }
        rule.onNodeWithTag(row).performClick()
        rule.waitUntil(30_000) { count("chat-title") > 0 }
        rule.onNodeWithTag("chat-title", useUnmergedTree = true).assertIsDisplayed()
        val echo1 = """Ben here: got "Hello Ben""""
        rule.waitUntil(120_000) { descriptions().any { it.contains(echo1) } }

        // Ada types a second message in the chat; it shows as sent; Ben echoes it too.
        rule.onNodeWithTag("composer-field").performTextInput("Second message from the app")
        rule.onNodeWithTag("send-button").performClick()
        rule.waitUntil(30_000) { descriptions().any { it.startsWith("You, Second message from the app") } }
        rule.waitUntil(30_000) { count("delivery-sent") > 0 || count("delivery-sending") > 0 }
        val echo2 = """Ben here: got "Second message from the app""""
        rule.waitUntil(120_000) { descriptions().any { it.contains(echo2) } }
        assertTrue(descriptions().any { it.startsWith("Ben Android, ") })

        // Photos: Ada sends one (with a description); Ben downloads and decrypts it, tells her how big it came out, and sends one back.
        val picture = android.graphics.Bitmap.createBitmap(640, 400, android.graphics.Bitmap.Config.ARGB_8888).also { android.graphics.Canvas(it).drawColor(android.graphics.Color.rgb(9, 169, 80)) }
        val outgoing = com.limemessenger.lime.chats.AttachmentProcessing.photo(picture, "ada.jpg")!!.copy(alt = "A green test picture from Ada")
        val dmId = "dm:$benId"
        core.sendAttachments(dmId, "A photo from Ada", listOf(outgoing), null)
        runBlocking { core.deliverQueued(session.transport!!, session.accessToken()) }
        rule.waitUntil(60_000) { descriptions().any { it.startsWith("You, A photo from Ada, Photo: A green test picture from Ada") } }
        rule.waitUntil(120_000) { descriptions().any { it.startsWith("Ben Android, Ben here: got 1 photo (") && it.contains("and \"A photo from Ada\"") } }
        // Ben's photo arrives with its description, which is what TalkBack reads; this phone downloads and decrypts it by itself.
        rule.waitUntil(120_000) { descriptions().any { it.contains("Photo: A green gradient fading to dark, from Ben") } }
        val bensPhoto = core.listMessages(dmId).first { it.senderId != null && it.attachments.isNotEmpty() }.attachments.first()
        rule.waitUntil(60_000) { core.attachmentData(bensPhoto.id) != null }
        assertTrue(core.attachmentData(bensPhoto.id)!!.size > 1000)
        rule.waitUntil(30_000) { count("photo-${bensPhoto.id}") > 0 }
        // Open it full screen and leave.
        rule.onNodeWithTag("photo-${bensPhoto.id}", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("photo-viewer") > 0 }
        rule.onNodeWithTag("photo-close", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("photo-viewer") == 0 }

        // Ben's profile, from the chat's header (a real `profile-get` on staging), then back.
        rule.onNodeWithTag("chat-header", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("profile-username") > 0 }
        rule.onNodeWithTag("profile-name", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithTag("profile-username", useUnmergedTree = true).assertTextEquals("@ben_android")
        rule.onNodeWithTag("profile-back").performClick()
        rule.waitUntil(10_000) { count("chat-title") > 0 }
        rule.onNodeWithTag("chat-back").performClick()

        // The jam tab: Ada follows nobody, so it says how to get posts; then back to the link tab.
        rule.waitUntil(10_000) { count("tab-jam") > 0 }
        rule.onNodeWithTag("tab-jam", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("jam-feed-empty") > 0 }
        rule.onNodeWithTag("jam-feed-empty", useUnmergedTree = true).assertTextEquals("Subscribe to teachers from their profiles. Your posts show here too.")
        rule.onNodeWithTag("tab-link", useUnmergedTree = true).performClick()

        // Settings: my About changes through the real `profile-set`, then Sign out says what it does and signs out on the server.
        rule.waitUntil(10_000) { count("my-avatar") > 0 }
        rule.onNodeWithTag("my-avatar", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("settings-profile") > 0 }
        rule.onNodeWithTag("settings-row-about", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("preset-Planning lessons", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("editor-save", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { session.profile?.about == "📚 Planning lessons" }
        rule.waitUntil(10_000) { count("field-editor") == 0 }
        rule.onNodeWithTag("settings-about-line", useUnmergedTree = true).assertTextEquals("📚 Planning lessons")
        rule.onNodeWithTag("settings-sign-out", useUnmergedTree = true).performScrollTo().performClick()
        rule.onNodeWithTag("sign-out-confirm", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { session.phase == Phase.SignedOut }
        assertEquals(Phase.SignedOut, session.phase)
    }

    /** The TalkBack descriptions of every message on screen (one stop per message). */
    private fun descriptions(): List<String> =
        rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("is a message") { it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.TestTag) && it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-") && it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription) })
            .fetchSemanticsNodes().map { it.config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString() }
}
