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
class StagingGroupsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.groups.staging"
    private val dir = File(context.cacheDir, "staging-groups-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun text(tag: String): String = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].joinToString("") { it.text }

    private fun typed(tag: String): String = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.EditableText].text

    @Test fun adaMakesAGroupWithBenAndCleo() {
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

        // The details: members, rename, remove, add, leave.
        rule.onNodeWithTag("chat-header", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("group-details-name") > 0 }
        assertEquals("Staff room", text("group-details-name"))
        assertEquals("3 members", text("group-details-count"))
        rule.onNodeWithTag("group-rename", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("group-rename-field", useUnmergedTree = true).performTextClearance()
        rule.onNodeWithTag("group-rename-field", useUnmergedTree = true).performTextInput("Staff room 2")
        rule.onNodeWithTag("group-rename-save", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("group-details-name") > 0 && text("group-details-name") == "Staff room 2" }

        rule.onNodeWithTag("group-remove-$cleoId", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("group-remove-confirm", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("group-details-count") > 0 && text("group-details-count") == "2 members" }
        assertEquals(0, count("group-member-$cleoId"))

        rule.onNodeWithTag("group-add-members", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("group-pick-$cleoId") > 0 }
        assertEquals(0, count("group-pick-$benId"))
        rule.onNodeWithTag("group-pick-$cleoId", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("group-next", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("group-details-count") > 0 && text("group-details-count") == "3 members" }

        rule.onNodeWithTag("group-leave", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("group-leave-confirm", useUnmergedTree = true).performClick()
        // Leaving returns to the list; the group stays there as an ended, read-only chat until Ada removes it (as iOS).
        rule.waitUntil(30_000) { count("messages-list") > 0 }
        val groupRow = core.listConversations().first { it.isGroup }.id
        rule.waitUntil(30_000) { count("conversation-row-$groupRow") > 0 }
        rule.onNodeWithTag("conversation-row-$groupRow", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("group-ended-note") > 0 }
        assertEquals("You left this group.", text("group-ended-note"))
        assertEquals(0, count("composer-field"))
        rule.onNodeWithTag("group-ended-remove", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("conversation-row-$groupRow") == 0 && count("messages-list") > 0 }
        assertTrue(core.listConversations().none { it.id == groupRow })
    }

    /** The TalkBack descriptions of every message on screen (one stop per message). */
    private fun descriptions(): List<String> =
        rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("is a message") { it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.TestTag) && it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-") && it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription) })
            .fetchSemanticsNodes().map { it.config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString() }
}
