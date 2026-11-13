package com.limemessenger.lime

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.Samples
import com.limemessenger.lime.chats.isOwn
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chat.BackWithCount
import com.limemessenger.lime.ui.chat.ChatScreen
import com.limemessenger.lime.ui.chats.ConversationRow
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore

/** LIME-422b: the Back pill holds the count; the date column has one right edge; a message's time line sits on its bubble's edge (the local core's sample chat). */
@RunWith(AndroidJUnit4::class)
class Alignment422bUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private val alias = "lime.test.align422b"

    @Before fun setUp() {
        dir = File(context.cacheDir, "align-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("align-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun bounds(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

    @Test fun theBackPillHoldsTheCountAndIsOneStop() {
        var shown by androidx.compose.runtime.mutableIntStateOf(0)
        rule.setContent { LimeTheme { BackWithCount(shown, onBack = {}) } }
        for ((n, words) in listOf(0 to null, 1 to "1", 12 to "12", 120 to "99+")) {
            shown = n
            rule.waitForIdle()
            val pill = bounds("chat-back")
            assertTrue("$n: the pill is 48 dp at least each way", pill.width >= 48f * rule.density.density - 0.5f && pill.height >= 48f * rule.density.density - 0.5f)
            if (words == null) assertEquals("no count: no text", 0, count("chat-back-count"))
            else {
                val text = bounds("chat-back-count")
                assertTrue("$n: the count is inside the pill", text.left >= pill.left && text.right <= pill.right && text.top >= pill.top && text.bottom <= pill.bottom)
                rule.onNodeWithTag("chat-back-count", useUnmergedTree = true).assertTextEquals(words)
                // One TalkBack node: the number is not a stop of its own in the merged tree.
                assertEquals("$n: one node", 1, rule.onAllNodes(hasTestTag("chat-back")).fetchSemanticsNodes().size)
                assertEquals("$n: the number alone is not a node", 0, rule.onAllNodes(hasText(words)).fetchSemanticsNodes().size)
            }
        }
    }

    @Test fun theDateColumnHasOneRightEdgeWhateverTheRowShows() {
        val last = { id: String, at: Long -> Samples.message("m-$id", "Hello there, this is a message", from = "ben", at = at) }
        val rows = listOf(
            Samples.conversation("dm:a", "Plain", last = last("a", 1_000L), activityAt = 1_000L),
            Samples.conversation("dm:b", "Unread friend", unread = 3, last = last("b", 2_000L), activityAt = 2_000L),
            Samples.conversation("dm:c", "Pinned", pinned = true, last = last("c", 3_000L), activityAt = 3_000L),
            Samples.conversation("grp:d", "A group with a longer name that gets cut", group = true, unread = 12, pinned = true, last = last("d", 4_000L), activityAt = 4_000L),
            Samples.conversation("dm:e", "Short", last = last("e", 5_000L), activityAt = 5_000L),
        )
        rule.setContent { LimeTheme { Column { rows.forEach { c -> ConversationRow(c, muted = c.id == "dm:c" || c.id == "grp:d", myName = "Ada", onClick = {}) } } } }
        rule.waitForIdle()
        val edges = rows.map { bounds("row-time-${it.id}").right }
        for (e in edges) assertEquals("every time ends at one right edge: $edges", edges.first(), e, 1f)
    }

    @Test fun theTimeLineSitsOnTheBubblesEdge() {
        val chat = ChatModel(chats.chats.first { it.title == "Autumn Reyes" }.id, chats)
        rule.setContent { LimeTheme { ChatScreen(chat, chats, onBack = {}) } }
        rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        var checkedOthers = false; var checkedOwn = false
        for (m in chat.messages) {
            if (count("message-footer-${m.id}") == 0) continue
            val footer = bounds("message-footer-${m.id}"); val column = bounds("message-${m.id}")
            if (m.isOwn) { assertEquals("mine: the time line ends at the bubble's right edge", column.right, footer.right, 1f); checkedOwn = true }
            else { assertEquals("theirs: the time line starts at the bubble's left edge", column.left, footer.left, 1f); checkedOthers = true }
        }
        assertTrue("an others' message with a time line was checked", checkedOthers)
        assertTrue("one of mine was checked", checkedOwn)
    }
}
