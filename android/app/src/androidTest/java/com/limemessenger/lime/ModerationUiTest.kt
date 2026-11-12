package com.limemessenger.lime

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.block
import com.limemessenger.lime.chats.blockedPeople
import com.limemessenger.lime.chats.unblock
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.moderation.BlockedScreen
import com.limemessenger.lime.ui.moderation.GroupReportDraft
import com.limemessenger.lime.ui.moderation.ReportDialog
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore
import uniffi.lime_core.ReportGroupMember
import uniffi.lime_core.ReportGroupMessage

/** LIME-401 on a real local store, with no network: the Report sheet's choices and words, Block and Unblock, the Blocked list's TalkBack, the largest font. */
@RunWith(AndroidJUnit4::class)
class ModerationUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var model: ChatsModel
    private val alias = "lime.test.moderation"

    @Before fun setUp() {
        dir = File(context.cacheDir, "moderation-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("moderation-user")).store
        model = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size

    @Test fun aReportNeedsAReasonAndWithNoLinkItSaysItCouldNotSend() {
        val target = uniffi.lime_core.reportTargetMessage("m1", "dm:ben", "ben", "Ben", "Hello there", 1_000, 0u)
        var dismissed = false
        rule.setContent { LimeTheme { ReportDialog(target, model, onDismiss = { dismissed = true }) } }
        rule.waitUntil(5_000) { count("report-sheet") > 0 }
        // The words: every reason as the core names them; the include line names the person.
        assertEquals(7, uniffi.lime_core.reportReasons().size)
        rule.onNodeWithTag("report-reason-harassment", useUnmergedTree = true).assertExists()
        assertEquals("Hello there", rule.onNodeWithTag("report-preview", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString(""))
        // Send waits for a reason, and the chosen one says "selected".
        rule.onNodeWithTag("report-reason-other", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { rule.onNodeWithTag("report-reason-other", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Selected] }   // (idle-based: the state is read once the click has recomposed)
        rule.onNodeWithTag("report-note").performTextInput("Test (LIME-401)")
        rule.onNodeWithTag("report-send").performClick()
        // No link on this phone: nothing is sent, and it says so (the sheet stays).
        rule.waitUntil(5_000) { count("report-failed") > 0 }
        assertEquals(0, count("report-thanks"))
        rule.onNodeWithTag("report-cancel").performClick()
        assertTrue(dismissed)
    }

    @Test fun aGroupReportListsTheMessagesToTickAndSaysWhatIsOnOrOff() {
        val messages = listOf(ReportGroupMessage("a", "ada", "Ada", "First words", 1, 0u), ReportGroupMessage("b", "cleo", "Cleo", "Second words", 2, 1u))
        val draft = GroupReportDraft("grp:x", "Class", false, messages, listOf(ReportGroupMember("ada", "Ada", "owner")))
        rule.setContent { LimeTheme { ReportDialog(uniffi.lime_core.reportTargetGroup("grp:x", "Class"), model, group = draft, onDismiss = {}) } }
        rule.waitUntil(5_000) { count("report-message-a") > 0 }
        fun words(id: String) = rule.onNodeWithTag("report-message-$id", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertEquals("Include message from Ada: First words, on", words("a"))
        rule.onNodeWithTag("report-message-a", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { words("a") == "Include message from Ada: First words, off" }   // (a slow phone redraws a moment after the tap)
        assertEquals("Include message from Ada: First words, off", words("a"))
        assertEquals("Include message from Cleo: Second words, on", words("b"))
        assertEquals(1, count("report-group-leave"))
    }

    @Test fun aBlockedPersonLeavesTheListAndComesBackWithTheirMessages() {
        store.seedSampleDataIfEmpty()
        runBlocking { model.reload() }
        val chat = model.conversations.first { !it.isGroup }
        val before = store.listMessages(chat.id).size
        assertTrue(before > 0)
        assertTrue(runBlocking { model.block(chat.id) })
        assertTrue("a blocked chat is hidden", model.conversations.none { it.id == chat.id })
        assertEquals(listOf(chat.id), runBlocking { model.blockedPeople() }.map { it.conversationId })
        // The Blocked list: one TalkBack stop "<name>, blocked" whose action is Unblock.
        rule.setContent { LimeTheme { BlockedScreen(model) {} } }
        rule.waitUntil(5_000) { count("blocked-row-${chat.id}") > 0 }
        val row = rule.onNodeWithTag("blocked-row-${chat.id}", useUnmergedTree = true).fetchSemanticsNode()
        assertEquals("${chat.title}, blocked", row.config[SemanticsProperties.ContentDescription].joinToString())
        assertEquals(listOf("Unblock ${chat.title}"), row.config[SemanticsActions.CustomActions].map { it.label })
        rule.onNodeWithTag("unblock-${chat.id}", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("blocked-empty") > 0 }
        assertEquals("${chat.title} unblocked", rule.onNodeWithTag("blocked-said", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString(""))
        runBlocking { model.reload() }
        assertTrue("the chat is back", model.conversations.any { it.id == chat.id })
        assertEquals("what was stored before the block shows again", before, store.listMessages(chat.id).size)
        assertTrue(runBlocking { model.blockedPeople() }.isEmpty())
        // (unblocking something not blocked is refused, not a crash)
        assertFalse(runBlocking { model.unblock(chat.id) })
    }

    @Test fun theReportSheetAndTheBlockedListHoldAtTheLargestFont() {
        val target = uniffi.lime_core.reportTargetPerson("ben", "Ben Android", true)
        rule.setContent {
            val d = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(d.density, 2f)) { LimeTheme { ReportDialog(target, model, onDismiss = {}) } }
        }
        rule.waitUntil(5_000) { count("report-sheet") > 0 }
        // The last reason and the Also block switch can be reached by scrolling (the sheet scrolls).
        rule.onNodeWithTag("report-reason-other", useUnmergedTree = true).assertExists()
        rule.onNodeWithTag("report-also-block", useUnmergedTree = true).assertExists()
    }
}
