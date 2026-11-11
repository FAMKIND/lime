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
import androidx.compose.ui.test.performTextInputSelection
import androidx.compose.ui.text.TextRange
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
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * LIME-405 on STAGING: Ada formats three messages in the composer (a bold word, a bulleted list, a link) and sends them; Ben (the partner running `echo`) receives each, and
 * `connected.sh` checks his log for exactly the Markdown the core makes of them (`markdown: **bold** word`, `- one\n- two`, the link).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingComposerTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.composer.staging"
    private val dir = File(context.cacheDir, "staging-composer-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun click(tag: String) { rule.onNodeWithTag(tag, useUnmergedTree = true).performClick(); rule.waitForIdle() }
    private fun until(ms: Long, why: String, check: () -> Boolean) { try { rule.waitUntil(ms) { check() } } catch (e: Throwable) { throw AssertionError("timed out: $why", e) } }
    private fun type(text: String) { for (ch in text) { rule.onNodeWithTag("composer-field").performTextInput(ch.toString()); rule.waitForIdle() } }

    @Test fun adaSendsFormattedMessagesAndBenGetsTheMarkdown() {
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
        until(30_000, "Ben's first echo") { core.listMessages(dm).any { it.senderId != null && it.localState != "system" } }

        fun sent() = core.listMessages(dm).count { it.senderId == null && it.localState != "system" }
        fun heard() = core.listMessages(dm).count { it.senderId != null && it.localState != "system" }
        // 1. A bold word.
        type("bold word")
        rule.onNodeWithTag("composer-field").performTextInputSelection(TextRange(0, 4))
        until(10_000, "the strip") { count("fmt-bold") > 0 }
        click("fmt-bold"); click("send-button")
        until(60_000, "the bold message to be sent") { sent() == 2 }
        until(240_000, "Ben's answer to it") { heard() >= 2 }
        // 2. A list.
        type("- one\ntwo"); click("send-button")
        until(60_000, "the list to be sent") { sent() == 3 }
        until(240_000, "Ben's answer to it") { heard() >= 3 }
        // 3. A link.
        type("see the plan today")
        rule.onNodeWithTag("composer-field").performTextInputSelection(TextRange(8, 12))
        until(10_000, "the strip") { count("fmt-link") > 0 }
        click("fmt-link")
        until(10_000, "the link dialog") { count("link-url") > 0 }
        rule.onNodeWithTag("link-url", useUnmergedTree = true).performTextInput("limemessenger.com/plan")
        click("link-apply"); click("send-button")
        until(60_000, "the link message to be sent") { sent() == 4 }
        until(240_000, "Ben's answer to it") { heard() >= 4 }
        val texts = core.listMessages(dm).filter { it.senderId == null && it.localState != "system" }.map { it.text }
        assertEquals(listOf("Hello Ben", "**bold** word", "- one\n- two", "see the [plan](https://limemessenger.com/plan) today"), texts)
    }
}
