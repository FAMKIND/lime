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
 * LIME-304 on STAGING: Ben (the partner running `actions-echo`) reacts to Ada's message and Ada sees it; Ada reacts to Ben's and takes it back; she edits
 * her message (the partner prints "edited: …"), deletes one for everyone (the partner prints "deleted: …") and one for herself, forwards one into another
 * chat, and selects messages. `tools/connected.sh` starts the partner and checks its log.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingActionsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.actions.staging"
    private val dir = File(context.cacheDir, "staging-actions-${System.nanoTime()}")

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

    @Test fun reactEditDeleteForwardAndSelect() {
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
        val dm = "dm:$benId"
        core.startDm(benId, "Ben Android"); core.startDm(cleoId, "Cleo Android")
        core.sendTextIdentified(session.transport!!, kotlinx.coroutines.runBlocking { session.accessToken() }, benId, "Hello Ben")
        rule.waitUntil(120_000) { count("conversation-row-$dm") > 0 }
        rule.onNodeWithTag("conversation-row-$dm").performClick()
        rule.waitUntil(30_000) { count("chat-title") > 0 }

        // Ben answers and reacts 👍 to Ada's message: the chip and the TalkBack words say so.
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("Ben Android, ") && it.contains("""got "Hello Ben"""") } }
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("You, Hello Ben") && it.contains("1 reaction") } }
        val mine = core.listMessages(dm).first { it.senderId == null && it.text == "Hello Ben" }.id
        val echo = core.listMessages(dm).first { it.senderId != null }.id
        assertTrue(count("reaction-$mine-👍") > 0)

        // Every action is also a custom accessibility action on the message (TalkBack), by the menu's names.
        val labels = rule.onNodeWithTag("message-$mine", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.CustomActions].map { it.label }
        for (name in listOf("React", "Reply", "Forward", "Edit", "Copy", "Select", "Delete")) assertTrue("missing the $name action in $labels", name in labels)

        // Ada reacts to Ben's message (the long-press menu), sees her chip, and takes it back by tapping it.
        longPress(echo)
        rule.onNodeWithTag("react-👍", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("reaction-$echo-👍") > 0 }
        rule.onNodeWithTag("reaction-$echo-👍", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("reaction-$echo-👍") == 0 }

        // Edit: Ada changes her message; it says edited; the partner prints it.
        longPress(mine)
        rule.onNodeWithTag("action-edit", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("edit-field", useUnmergedTree = true).performTextClearance()
        rule.onNodeWithTag("edit-field", useUnmergedTree = true).performTextInput("Hello Ben (edited)")
        rule.onNodeWithTag("edit-save", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { descriptions().any { it.startsWith("You, Hello Ben (edited)") && it.contains(", edited") } }

        // Delete for everyone: a new message, then "This message was deleted"; the partner prints it.
        rule.waitUntil(10_000) { count("composer-field") > 0 }
        rule.onNodeWithTag("composer-field").performClick()
        rule.onNodeWithTag("composer-field").performTextInput("Delete me")
        rule.waitUntil(10_000) { count("send-button") > 0 }
        rule.onNodeWithTag("send-button").performClick()
        try {
            rule.waitUntil(60_000) { core.listMessages(dm).any { it.senderId == null && it.text == "Delete me" } }
        } catch (e: Throwable) {
            throw AssertionError("Delete me was not sent; messages: " + core.listMessages(dm).map { (if (it.senderId == null) "me:" else "ben:") + it.text.take(30) + "/" + it.localState }, e)
        }
        val doomed = core.listMessages(dm).first { it.senderId == null && it.text == "Delete me" }.id
        rule.waitUntil(180_000) { descriptions().any { it.startsWith("Ben Android, ") && it.contains("""got "Delete me"""") } }
        longPress(doomed)
        rule.onNodeWithTag("action-delete", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("delete-for-everyone") > 0 }
        rule.onNodeWithTag("delete-for-everyone", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { descriptions().any { it.startsWith("You, This message was deleted") } }
        // Delete for me: Ben's answer to it leaves this phone.
        val echo2 = core.listMessages(dm).first { it.senderId != null && it.text.contains("Delete me") }.id
        longPress(echo2)
        rule.onNodeWithTag("action-delete", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("delete-for-me", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("message-$echo2") == 0 }

        // Select mode: two messages selected, then out.
        longPress(mine)
        rule.onNodeWithTag("action-select", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("select-count") > 0 }
        assertEquals("1 selected", text("select-count"))
        rule.onNodeWithTag("select-$echo", useUnmergedTree = true).performClick()
        assertEquals("2 selected", text("select-count"))
        rule.onNodeWithTag("select-cancel", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("select-count") == 0 }

        // Forward: the edited message into the chat with Cleo; it shows there as Forwarded.
        longPress(mine)
        rule.onNodeWithTag("action-forward", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("forward-pick-dm:$cleoId") > 0 }
        rule.onNodeWithTag("forward-pick-dm:$cleoId", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("forward-send", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("forward-sheet") == 0 }
        rule.onNodeWithTag("chat-back").performClick()
        rule.waitUntil(10_000) { count("conversation-row-dm:$cleoId") > 0 }
        rule.onNodeWithTag("conversation-row-dm:$cleoId").performClick()
        rule.waitUntil(30_000) { descriptions().any { it.startsWith("You, Forwarded, Hello Ben (edited)") } }
    }
}
