package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.longClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore

/** A chat from a real core store (the core's sample chats): messages, one TalkBack stop each, typing and sending, formatting, replying. */
@RunWith(AndroidJUnit4::class)
class ChatUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var chat: ChatModel
    private val alias = "lime.test.chat"
    private var backed = false

    @Before fun setUp() {
        dir = File(context.cacheDir, "chat-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("chat-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        dmId = store.startDm("ben-test", "Ben Test")
        runBlocking { chats.reload() }
        chat = ChatModel(chats.chats.first { it.title == "Autumn Reyes" }.id, chats)
        dm = ChatModel(dmId, chats, accountSignedIn = false)
    }

    private lateinit var dmId: String
    private lateinit var dm: ChatModel

    /** Shows the sample chat (reading tests) or the locally made DM (sending tests). */
    private fun show(model: ChatModel) {
        rule.setContent { LimeTheme { ChatScreen(model, chats, onBack = { backed = true }) } }
        if (model === chat) rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun inner(tag: String) = rule.onNode(hasTestTag(tag), useUnmergedTree = true)
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun description(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
    private fun send(text: String) { rule.onNodeWithTag("composer-field").performTextInput(text); rule.onNodeWithTag("send-button").performClick() }

    @Test fun theHeaderAndTheMessagesAreShown() {
        show(chat)
        inner("chat-title").assertIsDisplayed()
        val first = chat.messages.first()
        rule.onNodeWithTag("message-${first.id}").assertExists()
        rule.waitUntil(5_000) { count("day-separator") > 0 }
        rule.onNodeWithTag("chat-back").performClick()
        assertTrue(backed)
    }

    @Test fun eachMessageIsOneTalkBackStopWithWhoWhatAndWhen() {
        show(chat)
        val theirs = chat.messages.first { it.senderId != null }
        val d = description("message-${theirs.id}")
        assertTrue(d, d.startsWith("Autumn Reyes, ") && d.contains(uniffi.lime_core.messagePlainText(theirs.text)))
        // The message actions (LIME-304: the core's list for someone else's sent message, minus Report) are TalkBack custom actions of that same element.
        val actions = rule.onNodeWithTag("message-${theirs.id}").fetchSemanticsNode().config[SemanticsProperties.Role]
        assertNotNull(actions)
        val custom = rule.onNodeWithTag("message-${theirs.id}").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsActions.CustomActions]
        assertEquals(listOf("React", "Reply", "Forward", "Copy", "Select", "Delete"), custom.map { it.label })
    }

    @Test fun sendingShowsTheMessageWithItsStateAndClearsTheField() {
        show(dm); val chat = dm
        // With nothing typed the microphone is where Send will be (as iOS); typing swaps it for Send.
        assertEquals(0, count("send-button")); assertEquals(1, count("voice-mic"))
        send("See you at the meeting")
        rule.waitUntil(5_000) { chat.banner != null || chat.messages.any { it.text == "See you at the meeting" } }
        assertEquals(null, chat.banner)
        rule.waitUntil(5_000) { chat.messages.any { it.text == "See you at the meeting" } }
        val mine = chat.messages.first { it.text == "See you at the meeting" }
        rule.waitUntil(5_000) { count("delivery-sent") > 0 }
        assertTrue(description("message-${mine.id}").startsWith("You, See you at the meeting, "))
        assertTrue(description("message-${mine.id}").endsWith("sent"))
        rule.waitUntil(5_000) { count("send-button") == 0 && count("voice-mic") == 1 }   // the field is empty again: the microphone is back
    }

    @Test fun formattedTextIsDrawnAndReadAsPlainWords() {
        show(dm); val chat = dm
        send("This is **bold** and *italic*")
        rule.waitUntil(5_000) { chat.messages.any { it.text.contains("**bold**") } }
        val mine = chat.messages.first { it.text.contains("**bold**") }
        rule.waitUntil(5_000) { count("message-text-${mine.id}") > 0 }
        assertTrue(description("message-${mine.id}"), description("message-${mine.id}").startsWith("You, This is bold and italic, "))
    }

    @Test fun cancellingAReplyClearsTheBar() {
        show(chat)
        val theirs = chat.messages.first { it.senderId != null }
        rule.onNodeWithTag("message-${theirs.id}").performTouchInput { longClick() }
        rule.onNodeWithTag("action-reply").performClick()
        rule.onNodeWithTag("reply-cancel").performClick()
        rule.waitUntil(5_000) { count("reply-bar") == 0 }
        assertEquals(null, chat.replyingTo)
        rule.onNodeWithTag("composer-field").assertIsEnabled()
    }
}
