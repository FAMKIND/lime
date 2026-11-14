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
 * LIME-424 on STAGING: Ada (this emulator) messages Ben (the host-side partner running `call-miss`); Ben answers, then calls her (a `call.offer`) and hangs up
 * (`call.end`) 1.5 s later. Her phone hands the call ops to the core's machine (`call_rules.rs`), which logs a MISSED call: the Call tab gets a badge, its history
 * shows the row with "Missed", and the chat shows a "Missed voice call" bubble. Needs the pushed test accounts and the partner started BEFORE Ada acts (a message or a
 * call to a person with no registered device is lost): `tools/connected.sh` does both.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingCallsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.calls.staging"
    private val dir = File(context.cacheDir, "staging-calls-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size

    @Test fun aCallFromTheCallerThatEndsBeforeAnAnswerIsAMissedCall() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val benId = JSONObject(pushed.readText()).getJSONObject("accounts").getJSONObject("b").getString("user_id")
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets)
        rule.setContent { LimeTheme { Root(session) } }
        rule.waitUntil(15_000) { count("use-test-account") > 0 }
        rule.onNodeWithTag("use-test-account").performClick()
        rule.onNodeWithTag("test-account-ada_android").performClick()
        try {
            rule.waitUntil(60_000) { session.phase == Phase.SignedIn && (session.deviceRegistered || session.problem != null) }
        } catch (e: Throwable) {
            throw AssertionError("sign-in stalled: phase=${session.phase} registered=${session.deviceRegistered} problem=${session.problem}", e)
        }
        assertEquals("registration problem: ${session.problem}", true, session.deviceRegistered)

        // Ada's first message: Ben (call-miss) accepts, answers, then calls and hangs up.
        val core = session.store!!
        core.sendTextIdentified(session.transport!!, runBlocking { session.accessToken() }, benId, "Hello Ben")
        // The Call tab's badge: one missed call, not yet seen.
        rule.waitUntil(180_000) { count("tab-call-badge") > 0 }
        rule.onNodeWithTag("tab-call", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("call-history-row") > 0 }
        // The call was logged the moment it ended; the row shows the name the chats know (Ben's name reaches this phone with his profile, a moment later).
        fun label() = rule.onNodeWithTag("call-history-row", useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString()
        rule.waitUntil(120_000) { label().startsWith("Ben Android, voice call") }
        assertTrue(label(), label().endsWith("missed"))
        assertEquals(1, count("call-row-missed"))
        // Opening the tab marked it seen: the badge is gone on the other tab too.
        rule.onNodeWithTag("tab-link", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("tab-call-badge") == 0 }

        // The chat shows it as a bubble.
        val row = "conversation-row-dm:$benId"
        rule.waitUntil(60_000) { count(row) > 0 }
        rule.onNodeWithTag(row).performClick()
        rule.waitUntil(30_000) { count("call-bubble-title") > 0 }
        rule.onNodeWithTag("call-bubble-title", useUnmergedTree = true).assertTextEquals("Missed voice call")
        rule.onNodeWithTag("call-bubble-detail", useUnmergedTree = true).assertTextEquals("Missed")
        assertTrue(core.callHistoryList().any { it.peer == benId && it.outcome == "missed" && !it.outgoing })
    }
}
