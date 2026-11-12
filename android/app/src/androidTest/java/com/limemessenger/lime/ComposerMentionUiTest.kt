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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.test.performTextInputSelection
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.pressKey
/** LIME-406 B on a real local store (the core's sample group "Grade 4 Team" and a 1:1 chat): the @ list, a mention put in whole, deleted whole, and sent as markup. */
@RunWith(AndroidJUnit4::class)
class ComposerMentionUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var group: ChatModel
    private lateinit var dm: ChatModel
    private lateinit var dmId: String
    private val alias = "lime.test.composer.mention"

    @Before fun setUp() {
        dir = File(context.cacheDir, "mention-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("mention-user")).store
        store.seedSampleDataIfEmpty()
        dmId = store.startDm("ben-test", "Ben Test")
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        group = ChatModel(chats.conversations.first { it.isGroup }.id, chats, accountSignedIn = false)
        dm = ChatModel(dmId, chats, accountSignedIn = false)
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun show(model: ChatModel) {
        rule.setContent { LimeTheme { ChatScreen(model, chats, onBack = {}) } }
        rule.waitUntil(5_000) { count("composer-field") > 0 }
    }
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun field() = rule.onNodeWithTag("composer-field")
    private fun fieldText() = field().fetchSemanticsNode().config[SemanticsProperties.EditableText].text
    private fun type(text: String) { for (ch in text) { field().performTextInput(ch.toString()); rule.waitForIdle() } }
    private fun bounds(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
    private val members get() = chats.conversations.first { it.isGroup }.members

    @Test fun anAtInAGroupOffersItsPeople() {
        show(group)
        val before = bounds("composer-card")
        type("@")
        rule.waitUntil(5_000) { count("mention-suggestions") > 0 }
        for (m in members) assertEquals(1, count("mention-suggestion-${m.id}"))
        val label = rule.onNodeWithTag("mention-suggestions", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertTrue(label, label.startsWith("Suggestions, ") && (label.endsWith("people") || label.endsWith("person")))
        assertEquals("the card keeps its height while the list shows (the keyboard moves it, the list does not)", before.height, bounds("composer-card").height, 1f)
    }

    @Test fun aOneToOneChatOffersTheOtherPersonAndNeverEveryone() {
        show(dm)
        val other = chats.conversations.first { it.id == dm.conversationId }.members
        assertEquals("a 1:1 has one other person", 1, other.size)
        type("@")
        rule.waitUntil(5_000) { count("mention-suggestions") > 0 }
        assertEquals(1, count("mention-suggestion-${other.single().id}"))
        assertEquals("@everyone is for a group's owner or admin", 0, count("mention-suggestion-everyone"))
        val label = rule.onNodeWithTag("mention-suggestions", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertEquals("Suggestions, 1 person", label)
        rule.onNodeWithTag("mention-suggestion-${other.single().id}", useUnmergedTree = true).performClick()
        rule.waitForIdle()
        assertEquals("@${other.single().name} ", fieldText())
    }

    @Test fun aTappedPersonIsPutInWholeDeletedWholeAndSentAsMarkup() {
        show(group)
        val person = members.first()
        type("hi @" + person.name.take(2).lowercase())
        rule.waitUntil(5_000) { count("mention-suggestion-${person.id}") > 0 }
        rule.onNodeWithTag("mention-suggestion-${person.id}", useUnmergedTree = true).performClick()
        rule.waitForIdle()
        assertEquals("hi @${person.name} ", fieldText())
        assertEquals("the list closes", 0, count("mention-suggestions"))
        // Sent as the core's markup.
        val before = store.listMessages(group.conversationId).size
        rule.onNodeWithTag("send-button").performClick()
        rule.waitUntil(10_000) { store.listMessages(group.conversationId).size > before }
        assertEquals("hi [@${person.name}](mention:${person.id})", store.listMessages(group.conversationId).last { it.senderId == null }.text)
    }

    @Test fun backspaceTakesAMentionAsOneUnit() {
        show(group)
        val person = members.first()
        type("@" + person.name.take(1).lowercase())
        rule.waitUntil(5_000) { count("mention-suggestion-${person.id}") > 0 }
        rule.onNodeWithTag("mention-suggestion-${person.id}", useUnmergedTree = true).performClick()
        rule.waitForIdle()
        field().performKeyInput { pressKey(androidx.compose.ui.input.key.Key.Backspace) }   // the space after it
        rule.waitForIdle()
        assertEquals("@${person.name}", fieldText())
        field().performKeyInput { pressKey(androidx.compose.ui.input.key.Key.Backspace) }   // one more: the whole mention goes
        rule.waitForIdle()
        assertEquals("", fieldText())
    }
}
