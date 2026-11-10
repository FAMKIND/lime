package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
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
 * LIME-305 on STAGING: the chat list's controls and search. With Ben (the partner running `echo`) and a chat with Cleo: pin reorders, mute shows its mark and the
 * Muted filter, a label and the label filter, the Unread segment, the row's TalkBack actions, and a search that finds Ben's echo and opens the chat at it.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingListTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.list.staging"
    private val dir = File(context.cacheDir, "staging-list-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun text(tag: String): String = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString("") { it.text }
    private fun descriptions(): List<String> =
        rule.onAllNodes(SemanticsMatcher("is a message") { it.config.contains(SemanticsProperties.TestTag) && it.config[SemanticsProperties.TestTag].startsWith("message-") && it.config.contains(SemanticsProperties.ContentDescription) })
            .fetchSemanticsNodes().map { it.config[SemanticsProperties.ContentDescription].joinToString() }
    private fun longPress(messageId: String) {
        rule.waitUntil(30_000) { count("message-text-$messageId") > 0 }
        rule.onNodeWithTag("message-text-$messageId", useUnmergedTree = true).performTouchInput { longClick() }
        rule.waitUntil(10_000) { count("message-actions") > 0 }
    }

    @Test fun pinMuteLabelUnreadAndSearch() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val accounts = JSONObject(pushed.readText()).getJSONObject("accounts")
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

        val core = session.store!!
        val ben = "dm:$benId"
        val cleo = "dm:$cleoId"
        val token = kotlinx.coroutines.runBlocking { session.accessToken() }
        core.startDm(benId, "Ben Android"); core.startDm(cleoId, "Cleo Android")
        core.sendTextIdentified(session.transport!!, token, benId, "Hello Ben")
        core.sendTextIdentified(session.transport!!, token, cleoId, "Hello Cleo")
        rule.waitUntil(60_000) { count("conversation-row-$ben") > 0 && count("conversation-row-$cleo") > 0 }
        // Ben's echo arrives (the partner answers "Ben here: got …").
        rule.waitUntil(180_000) { core.listMessages(ben).any { it.senderId != null && it.text.contains("Ben here: got") } }
        val echo = core.listMessages(ben).first { it.senderId != null && it.text.contains("Ben here: got") }.id

        fun longPressRow(id: String) {
            rule.onNodeWithTag("conversation-row-$id", useUnmergedTree = true).performTouchInput { longClick() }
            rule.waitUntil(10_000) { count("row-actions") > 0 }
        }
        fun rowAction(id: String, action: String) { longPressRow(id); rule.onNodeWithTag("row-action-$action", useUnmergedTree = true).performClick() }
        fun openFilter(tag: String) {
            rule.onNodeWithTag("chat-filter-menu", useUnmergedTree = true).performClick()
            rule.waitUntil(10_000) { count(tag) > 0 }
            rule.onNodeWithTag(tag, useUnmergedTree = true).performClick()
        }

        // Every row action is also a TalkBack custom action of the row, by name.
        val labels = rule.onNodeWithTag("conversation-row-$cleo", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.CustomActions].map { it.label }
        for (name in listOf("Mark as unread", "Pin", "Mute", "Label", "Delete chat")) assertTrue("missing the $name action in $labels", name in labels)

        // Pin: Cleo's chat moves above Ben's (the core orders pinned first) and shows the pin mark.
        rowAction(cleo, "pin")
        rule.waitUntil(30_000) { count("pinned-$cleo") > 0 }
        assertEquals(cleo, core.listConversations().first { !it.isGroup }.id)
        assertEquals(0, count("pinned-$ben"))
        // …and Pinned is a filter.
        openFilter("filter-pinned")
        rule.waitUntil(10_000) { count("conversation-row-$ben") == 0 && count("conversation-row-$cleo") > 0 }
        rule.onNodeWithTag("chat-filter-menu", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("filter-clear", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("conversation-row-$ben") > 0 }

        // Mute Ben (always): the mark shows, and the Muted filter keeps only him.
        rowAction(ben, "mute")
        rule.waitUntil(10_000) { count("mute-always") > 0 }
        rule.onNodeWithTag("mute-always", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("muted-$ben") > 0 }
        openFilter("filter-muted")
        rule.waitUntil(10_000) { count("conversation-row-$cleo") == 0 && count("conversation-row-$ben") > 0 }
        rule.onNodeWithTag("chat-filter-menu", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("filter-clear", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("conversation-row-$cleo") > 0 }
        rowAction(ben, "unmute")
        rule.waitUntil(10_000) { count("muted-$ben") == 0 }

        // A label for Cleo, then the label filter.
        rowAction(cleo, "label")
        rule.waitUntil(10_000) { count("label-field") > 0 }
        rule.onNodeWithTag("label-field", useUnmergedTree = true).performTextInput("Grade 4")
        rule.onNodeWithTag("label-save", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { core.contactLabel(cleoId) == "Grade 4" }
        openFilter("filter-label-Grade 4")
        rule.waitUntil(10_000) { count("conversation-row-$ben") == 0 && count("conversation-row-$cleo") > 0 }
        rule.onNodeWithTag("chat-filter-menu", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("filter-clear", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("conversation-row-$ben") > 0 }

        // Unread: mark Cleo's chat unread by hand; the badge shows; the Unread segment keeps only her.
        // (Ben's chat is unread too: his echo arrived and was never opened. Read it first, from the row, so only Cleo's is unread.)
        if (count("count-badge-$ben") > 0) { rowAction(ben, "markread"); rule.waitUntil(10_000) { count("count-badge-$ben") == 0 } }
        rowAction(cleo, "markunread")
        rule.waitUntil(10_000) { count("count-badge-$cleo") > 0 }
        rule.onNodeWithTag("chat-filter-unread", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("conversation-row-$ben") == 0 && count("conversation-row-$cleo") > 0 }
        rule.onNodeWithTag("chat-filter-all", useUnmergedTree = true).performClick()
        rowAction(cleo, "markread")
        rule.waitUntil(10_000) { count("count-badge-$cleo") == 0 }

        // Search: the partner's echo is found by its words, and the result opens Ben's chat at that message.
        rule.onNodeWithTag("search-button", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("search-field") > 0 }
        rule.onNodeWithTag("search-field", useUnmergedTree = true).performTextInput("got")
        rule.waitUntil(30_000) { count("search-message-$echo") > 0 }
        rule.onNodeWithTag("search-message-$echo", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("chat-title") > 0 && count("message-$echo") > 0 }
        assertEquals("Ben Android", text("chat-title"))
        // A name search finds the chat; nothing matches nonsense.
        rule.onNodeWithTag("chat-back").performClick()
        rule.waitUntil(10_000) { count("search-button") > 0 }
        rule.onNodeWithTag("search-button", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("search-field") > 0 }
        rule.onNodeWithTag("search-field", useUnmergedTree = true).performTextInput("cleo")
        rule.waitUntil(30_000) { count("search-chat-$cleo") > 0 }
        rule.onNodeWithTag("search-field", useUnmergedTree = true).performTextClearance()
        rule.onNodeWithTag("search-field", useUnmergedTree = true).performTextInput("zzzqqq")
        rule.waitUntil(30_000) { count("search-none") > 0 }
    }
}
