package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.isUnread
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chat.ChatScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore

/** LIME-409: inside a chat, Back says how many OTHER chats are unread (the core's sample data has two unread chats). */
@RunWith(AndroidJUnit4::class)
class BackCountUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private val alias = "lime.test.backcount"

    @Before fun setUp() {
        dir = File(context.cacheDir, "backcount-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("backcount-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun open(id: String) {
        rule.setContent { LimeTheme { ChatScreen(ChatModel(id, chats, accountSignedIn = false), chats, onBack = {}) } }
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("chat-back"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    }
    private fun state(): String? = rule.onNodeWithTag("chat-back", useUnmergedTree = true).fetchSemanticsNode().config.let { if (SemanticsProperties.StateDescription in it) it[SemanticsProperties.StateDescription] else null }

    @Test fun twoOtherUnreadChatsSayTwoUnreadChatsAndBackStaysOneStop() {
        assertEquals("the sample has two unread chats", 2, chats.unreadChatCount)
        val read = chats.chats.first { !it.isUnread }
        open(read.id)
        assertEquals("2 unread chats", state())
        val node = rule.onNodeWithTag("chat-back", useUnmergedTree = true).fetchSemanticsNode()
        assertEquals("Back", node.config[SemanticsProperties.ContentDescription].joinToString())
        rule.onNodeWithTag("chat-back-count", useUnmergedTree = true).assertExists()
    }

    @Test fun anUnreadChatDoesNotCountItself() {
        val unread = chats.chats.first { it.isUnread }
        open(unread.id)
        assertEquals("one other unread chat (this one is not counted)", "1 unread chat", state())
    }

    @Test fun nothingUnreadElsewhereMeansTheArrowAlone() {
        for (c in chats.chats.filter { it.isUnread }) runBlocking { chats.markRead(c.id) }
        runBlocking { chats.reload() }
        open(chats.chats.first().id)
        assertNull(state())
        rule.onAllNodes(hasTestTag("chat-back-count"), useUnmergedTree = true).fetchSemanticsNodes().let { assertEquals(0, it.size) }
    }
}
