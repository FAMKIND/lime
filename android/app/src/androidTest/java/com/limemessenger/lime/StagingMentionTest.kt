package com.limemessenger.lime

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
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
 * LIME-303 on STAGING: Ada makes a group with Ben and Cleo, all three exchange messages, then Ada renames it, removes and adds a member and leaves.
 * Needs the pushed test accounts and BOTH partners running `group-echo` (`tools/connected.sh` starts them: Ben, and Cleo with `--as cleo`).
 * The partners' log must also show "system: … left" (connected.sh checks it).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingMentionTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.groups.staging"
    private val dir = File(context.cacheDir, "staging-groups-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun text(tag: String): String = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].joinToString("") { it.text }

    private fun typed(tag: String): String = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.EditableText].text

    @Test fun adaMentionsBenInAGroupAndBenGetsTheMarkup() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val accounts = JSONObject(pushed.readText()).getJSONObject("accounts")
        assumeTrue("no Cleo pushed", accounts.has("c"))
        val benId = accounts.getJSONObject("b").getString("user_id")
        val cleoId = accounts.getJSONObject("c").getString("user_id")
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

        // Ada knows Ben and Cleo as the new-chat screen leaves it: a first message to each, through the core (the partners accept).
        val core = session.store!!
        val token = kotlinx.coroutines.runBlocking { session.accessToken() }
        // (Started with their names, as the new-chat screen does: a group's default name is made from them.)
        core.startDm(benId, "Ben Android"); core.startDm(cleoId, "Cleo Android")
        core.sendTextIdentified(session.transport!!, token, benId, "Hello Ben")
        core.sendTextIdentified(session.transport!!, token, cleoId, "Hello Cleo")
        rule.waitUntil(30_000) { count("conversation-row-dm:$benId") > 0 && count("conversation-row-dm:$cleoId") > 0 }

        // New message → New group → pick both → Next → the name starts as their first names → Create.
        rule.onNodeWithTag("new-message-button", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("new-group") > 0 }
        rule.onNodeWithTag("new-group", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("group-pick-$benId") > 0 }
        assertEquals("1 member", text("group-count"))
        rule.onNodeWithTag("group-pick-$benId", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("group-pick-$cleoId", useUnmergedTree = true).performClick()
        assertEquals("3 members", text("group-count"))
        rule.onNodeWithTag("group-next", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("group-name-field") > 0 }
        assertEquals("Ben & Cleo", typed("group-name-field"))
        rule.onNodeWithTag("group-name-field", useUnmergedTree = true).performTextClearance()
        rule.onNodeWithTag("group-name-field", useUnmergedTree = true).performTextInput("Staff room")
        rule.onNodeWithTag("group-create", useUnmergedTree = true).performClick()
        rule.waitUntil(60_000) { count("chat-title") > 0 }
        assertEquals("Staff room", text("chat-title"))

        // Typing "@be" offers Ben; tapping him puts the mention in; the message goes out as the core's markup.
        rule.onNodeWithTag("composer-field").performTextInput("hi ")
        for (ch in "@be") { rule.onNodeWithTag("composer-field").performTextInput(ch.toString()); rule.waitForIdle() }
        rule.waitUntil(10_000) { count("mention-suggestion-$benId") > 0 }
        rule.onNodeWithTag("mention-suggestion-$benId", useUnmergedTree = true).performClick()
        rule.waitForIdle()
        for (ch in "there") { rule.onNodeWithTag("composer-field").performTextInput(ch.toString()); rule.waitForIdle() }
        rule.onNodeWithTag("send-button").performClick()
        rule.waitUntil(30_000) { descriptions().any { it.startsWith("You, hi @Ben Android there") } }
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("Ben Android, ") && it.contains("""Ben here: got "hi @Ben Android there"""") } }
        val mine = core.listMessages(core.listConversations().first { it.isGroup }.id).last { it.senderId == null }.text
        assertEquals("hi [@Ben Android](mention:$benId) there", mine)
    }

    private fun descriptions(): List<String> =
        rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("is a message") { it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.TestTag) && it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-") && it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription) })
            .fetchSemanticsNodes().map { it.config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString() }
}
