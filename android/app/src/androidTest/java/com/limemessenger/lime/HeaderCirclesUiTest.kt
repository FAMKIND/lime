package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chat.ChatScreen
import com.limemessenger.lime.ui.chats.ChatListScreen
import com.limemessenger.lime.ui.shell.Shell
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore

/** LIME-422: the header circles (search and my avatar on Messages, Back in a chat) and the tab bar's badge have a TalkBack label and a 48 dp target. */
@RunWith(AndroidJUnit4::class)
class HeaderCirclesUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private val alias = "lime.test.circles"

    @Before fun setUp() {
        dir = File(context.cacheDir, "circles-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("circles-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun label(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config.getOrElse(SemanticsProperties.ContentDescription) { emptyList() }.joinToString()

    @Test fun theMessagesCirclesHaveLabelsAnd48dpTargets() {
        rule.setContent { LimeTheme { Shell(link = { ChatListScreen(chats, "Ada Android", onOpen = {}) }, linkUnread = chats.unreadChatCount) } }
        for (tag in listOf("search-button", "my-avatar", "new-message-button")) {
            assertTrue("$tag has a label", label(tag).isNotBlank())
            rule.onNodeWithTag(tag, useUnmergedTree = true).assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
        }
        // The tab bar says the unread count on the link tab (the badge is the accent's one live use there).
        rule.onNodeWithTag("tab-link-badge", useUnmergedTree = true).assertExists()
        for (tag in listOf("tab-link", "tab-call", "tab-jam")) rule.onNodeWithTag(tag).assertHeightIsAtLeast(48.dp)
    }

    @Test fun theChatBackCircleHasALabelAnd48dpTarget() {
        val chat = ChatModel(chats.chats.first { it.title == "Autumn Reyes" }.id, chats)
        rule.setContent { LimeTheme { ChatScreen(chat, chats, onBack = {}) } }
        rule.waitUntil(5_000) { rule.onAllNodes(androidx.compose.ui.test.hasTestTag("chat-back")).fetchSemanticsNodes().isNotEmpty() }
        assertTrue("Back has a label", label("chat-back").isNotBlank())
        rule.onNodeWithTag("chat-back", useUnmergedTree = true).assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
    }
}
