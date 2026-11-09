package com.limemessenger.lime

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
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
        rule.waitUntil(60_000) { session.phase == Phase.SignedIn && session.deviceRegistered }

        // Ada starts the chat as the new-chat screen will (LIME-299): her first message to Ben, through the core.
        val core = session.store!!
        val token = runBlocking { session.accessToken() }
        core.sendTextIdentified(session.transport!!, token, benId, "Hello Ben")

        // Ben (echo) accepts and answers; the list's sync loop brings the answer in and the chat shows up.
        val row = "conversation-row-dm:$benId"
        rule.waitUntil(120_000) { count(row) > 0 }
        rule.onNodeWithTag(row).performClick()
        rule.waitUntil(30_000) { count("chat-title") > 0 }
        rule.onNodeWithTag("chat-title").assertIsDisplayed()
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

        // Leave nothing behind: sign out on the server and remove this test's store.
        runBlocking { session.signOut(removingData = true) }
        assertEquals(Phase.SignedOut, session.phase)
    }

    /** The TalkBack descriptions of every message on screen (one stop per message). */
    private fun descriptions(): List<String> =
        rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("is a message") { it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.TestTag) && it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-") && it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription) })
            .fetchSemanticsNodes().map { it.config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString() }
}
