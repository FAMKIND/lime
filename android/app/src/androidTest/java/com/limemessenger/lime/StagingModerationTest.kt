package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.longClick
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
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * LIME-401 on STAGING: Ada reports Ben's test message and then Ben's profile (the reason "other", the note "Test (LIME-401)": the reports are Ben's test content, in the
 * moderation queue for the user to clear), blocks Ben from his profile (the chat leaves the list and Settings > Blocked lists him), and unblocks him (the chat and
 * its earlier messages come back).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingModerationTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.moderation.staging"
    private val dir = File(context.cacheDir, "staging-moderation-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun click(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).performClick()
    private fun until(ms: Long, why: String, check: () -> Boolean) { try { rule.waitUntil(ms) { check() } } catch (e: Throwable) { throw AssertionError("timed out: $why", e) } }

    private fun sendReportThroughTheSheet() {
        until(10_000, "the report sheet") { count("report-sheet") > 0 }
        click("report-reason-other")
        rule.onNodeWithTag("report-note", useUnmergedTree = true).performTextInput("Test (LIME-401)")
        click("report-send")
        until(60_000, "the report to be accepted by the server") { count("report-thanks") > 0 }
        click("report-done")
        until(10_000, "the sheet to close") { count("report-sheet") == 0 }
    }

    @Test fun adaReportsBlocksAndUnblocksBen() {
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
        val core = session.store!!
        val dm = "dm:$benId"
        core.startDm(benId, "Ben Android")
        core.sendTextIdentified(session.transport!!, kotlinx.coroutines.runBlocking { session.accessToken() }, benId, "Hello Ben")
        until(120_000, "the chat with Ben") { count("conversation-row-$dm") > 0 }
        click("conversation-row-$dm")
        until(30_000, "Ben's echo") { core.listMessages(dm).any { it.senderId != null && it.localState != "system" } }
        val echo = core.listMessages(dm).first { it.senderId != null && it.localState != "system" }
        val before = core.listMessages(dm).size

        // Report his message from its long-press menu.
        until(30_000, "his message on screen") { count("message-text-${echo.id}") > 0 }
        rule.onNodeWithTag("message-text-${echo.id}", useUnmergedTree = true).performTouchInput { longClick() }
        until(10_000, "the message menu") { count("action-report") > 0 }
        click("action-report")
        sendReportThroughTheSheet()

        // Report his profile, then block him from it: the chat closes.
        until(10_000, "the chat header") { count("chat-header") > 0 }
        click("chat-header")
        until(30_000, "the profile's Report") { count("profile-report") > 0 }
        click("profile-report")
        sendReportThroughTheSheet()
        click("profile-block")
        until(10_000, "the confirmation") { count("profile-block-confirm") > 0 }
        click("profile-block-confirm")
        until(60_000, "the chat to leave the list") { count("my-avatar") > 0 && count("conversation-row-$dm") == 0 }
        assertEquals(listOf(dm), core.listBlocked().map { it.conversationId })

        // Settings > Blocked lists him; Unblock brings the chat and its messages back.
        click("my-avatar")
        until(10_000, "Settings") { count("settings-row-blocked") > 0 }
        click("settings-row-blocked")
        until(10_000, "him in the list") { count("blocked-row-$dm") > 0 }
        click("unblock-$dm")
        until(30_000, "the list to empty") { count("blocked-empty") > 0 }
        click("settings-page-back")
        until(10_000, "Settings again") { count("settings-close") > 0 }
        click("settings-close")
        until(60_000, "the chat to come back") { count("conversation-row-$dm") > 0 }
        assertEquals("what was stored before the block shows again", before, core.listMessages(dm).size)
        assertTrue(core.listBlocked().isEmpty())
    }
}
