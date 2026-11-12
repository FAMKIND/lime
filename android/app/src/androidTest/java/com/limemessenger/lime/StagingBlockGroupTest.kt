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
 * LIME-412b on STAGING (class 1): Ada, Ben and Cleo in a group. Ada opens Cleo's profile from her **avatar in the group** and blocks her. What the core and iOS say a block is (read first: `moderation.rs`
 * `block_sender` sets the **1:1 conversation** `dm:<id>` to "blocked"; `report_target_message` says "a group message has no chat to block"; iOS has no group-sender filter): the **chat with Cleo
 * leaves Ada's list and Blocked lists it; the GROUP is untouched: Cleo's earlier message and a new one still show there, and so do Ben's**; Cleo is not told. Unblocking brings the 1:1 chat back with
 * its messages. Needs the pushed accounts and BOTH partners running `group-echo` (connected.sh starts them).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingBlockGroupTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.blockgroup.staging"
    private val dir = File(context.cacheDir, "staging-blockgroup-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun text(tag: String): String = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].joinToString("") { it.text }

    private fun typed(tag: String): String = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.EditableText].text

    @Test fun adaBlocksCleoFromTheGroupAndUnblocksHer() {
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

        // A three-way exchange: Ada's message, and both partners answer (sender names on the first message of each run).
        rule.onNodeWithTag("composer-field").performTextInput("Hello team")
        rule.onNodeWithTag("send-button").performClick()
        rule.waitUntil(30_000) { descriptions().any { it.startsWith("You, Hello team") } }
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("Ben Android, ") && it.contains("""Ben here: got "Hello team"""") } }
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("Cleo Android, ") && it.contains("""Cleo here: got "Hello team"""") } }

        // Ada blocks Cleo from her avatar in the group.
        val group = core.listConversations().first { it.isGroup }.id
        val dmCleo = "dm:$cleoId"
        assertTrue("the 1:1 chat with Cleo is in Ada's list before", core.listConversations().any { it.id == dmCleo })
        rule.onNodeWithTag("sender-avatar-$cleoId", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("profile-block") > 0 }
        rule.onNodeWithTag("profile-block", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("profile-block-confirm") > 0 }
        rule.onNodeWithTag("profile-block-confirm", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("messages-list") > 0 }
        // (1) the 1:1 chat is blocked: listed by Blocked, gone from the list; (2) the group is still there with Cleo's earlier reply.
        assertEquals(listOf(dmCleo), core.listBlocked().map { it.conversationId })
        assertTrue("the blocked chat leaves the list", core.listConversations().none { it.id == dmCleo })
        assertTrue("the group stays", core.listConversations().any { it.id == group })
        assertTrue("Cleo's earlier group message is still in the group", core.listMessages(group).any { it.senderId == cleoId && it.text.contains("got") })
        // (3) A new group message: Ben AND Cleo answer and both show for Ada (the core has no per-person filter in a group).
        rule.waitUntil(30_000) { count("conversation-row-$group") > 0 }
        rule.onNodeWithTag("conversation-row-$group", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("composer-field") > 0 }
        rule.onNodeWithTag("composer-field").performTextInput("After the block")
        rule.onNodeWithTag("send-button").performClick()
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("Ben Android, ") && it.contains("""got "After the block"""") } }
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("Cleo Android, ") && it.contains("""got "After the block"""") } }
        // Unblock from Settings > Blocked: the 1:1 chat is back.
        rule.onNodeWithTag("chat-back", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("my-avatar") > 0 }
        rule.onNodeWithTag("my-avatar", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("settings-row-blocked") > 0 }
        rule.onNodeWithTag("settings-row-blocked", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("blocked-row-$dmCleo") > 0 }
        rule.onNodeWithTag("unblock-$dmCleo", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("blocked-empty") > 0 }
        assertTrue(core.listBlocked().isEmpty())
        assertTrue("the 1:1 chat with Cleo is back in the list", core.listConversations().any { it.id == dmCleo })
    }

    private fun descriptions(): List<String> =
        rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("is a message") { it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.TestTag) && it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-") && it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription) })
            .fetchSemanticsNodes().map { it.config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString() }
}
