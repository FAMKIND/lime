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

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.onNodeWithTag
/** LIME-403: the composer is ONE rounded card: the words on top at the card's full width, one tool row under them (+, face, keyboard, then send or the microphone). */
@RunWith(AndroidJUnit4::class)
class ComposerUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var dm: ChatModel
    private val alias = "lime.test.composer"

    @Before fun setUp() {
        dir = File(context.cacheDir, "composer-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("composer-user")).store
        val id = store.startDm("ben-test", "Ben Test")
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        dm = ChatModel(id, chats, accountSignedIn = false)
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun show(fontScale: Float = 1f) = rule.setContent {
        val d = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(d.density, fontScale)) { LimeTheme { ChatScreen(dm, chats, onBack = {}) } }
    }
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun bounds(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
    private fun words(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()

    @Test fun theFieldIsTheCardsWholeWidthWhateverTheRowHolds() {
        show()
        rule.waitUntil(5_000) { count("composer-card") > 0 }
        val padding = 24f * rule.density.density   // 12 dp inside on each side
        val empty = bounds("composer-field")
        assertEquals(bounds("composer-card").width - padding, empty.width, 1.5f)
        // The row changes (the microphone becomes send) and the field does not move or shrink.
        assertEquals(1, count("voice-mic")); assertEquals(0, count("send-button"))
        rule.onNodeWithTag("composer-field").performTextInput("Hello")
        rule.waitUntil(5_000) { count("send-button") > 0 }
        assertEquals(0, count("voice-mic"))
        val full = bounds("composer-field")
        assertEquals(empty.width, full.width, 0.5f); assertEquals(empty.left, full.left, 0.5f)
        assertEquals(bounds("composer-card").width - padding, full.width, 1.5f)
    }

    @Test fun everyToolHasItsWordsAndAtLeastA48dpTarget() {
        show()
        rule.waitUntil(5_000) { count("composer-card") > 0 }
        assertEquals("Add attachment", words("composer-plus"))
        assertEquals("Emoji, GIFs and stickers", words("attach-gif"))
        assertEquals("Show keyboard", words("composer-hide-keyboard"))
        assertEquals("Record a voice message", words("voice-mic"))
        val min = 48f * rule.density.density - 0.5f
        for (tag in listOf("composer-plus", "attach-gif", "composer-hide-keyboard", "voice-mic")) {
            val b = bounds(tag)
            assertTrue("$tag is ${b.width} x ${b.height}", b.width >= min && b.height >= min)
        }
        rule.onNodeWithTag("composer-field").performTextInput("Hi")
        rule.waitUntil(5_000) { count("send-button") > 0 }
        assertEquals("Send", words("send-button"))
        val send = bounds("send-button")
        assertTrue(send.width >= min && send.height >= min)
        // Send is on the card's right edge, the tools on its left: they never meet the field.
        assertTrue(bounds("composer-plus").left < bounds("composer-hide-keyboard").right && bounds("composer-hide-keyboard").right < send.left)
    }

    @Test fun thePlusOpensTheAttachmentSheetWithPhotoAndFile() {
        show()
        rule.waitUntil(5_000) { count("composer-plus") > 0 }
        rule.onNodeWithTag("composer-plus", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("attach-sheet") > 0 }
        assertEquals(1, count("attach-photo")); assertEquals(1, count("attach-file"))
        assertTrue(bounds("attach-photo").height >= 48f * rule.density.density - 0.5f)
    }

    @Test fun aLongMessageGrowsTheFieldToFiveLinesThenScrolls() {
        show()
        rule.waitUntil(5_000) { count("composer-field") > 0 }
        val one = bounds("composer-field").height
        rule.onNodeWithTag("composer-field").performTextInput("1\n2\n3\n4\n5")
        rule.waitForIdle()
        val five = bounds("composer-field").height
        assertTrue("five lines are taller than one", five > one + 3 * 20f * rule.density.density)
        rule.onNodeWithTag("composer-field").performTextInput("\n6")
        rule.waitForIdle()
        assertEquals("the sixth line scrolls, the field stops growing", five, bounds("composer-field").height, 1.5f)
        // The card and its tools are still on screen.
        assertTrue(bounds("composer-card").bottom >= bounds("composer-plus").bottom)
    }

    @Test fun atTheLargestFontTheRowKeepsItsIconsAndTheFieldGrows() {
        show(fontScale = 2f)
        rule.waitUntil(5_000) { count("composer-card") > 0 }
        val card = bounds("composer-card")
        for (tag in listOf("composer-plus", "attach-gif", "composer-hide-keyboard", "voice-mic")) {
            val b = bounds(tag)
            assertTrue("$tag stays inside the card", b.left >= card.left && b.right <= card.right && b.bottom <= card.bottom + 1f)
            assertTrue("$tag is still 48 dp", b.width >= 48f * rule.density.density - 0.5f)
        }
        assertEquals(card.width - 24f * rule.density.density, bounds("composer-field").width, 1.5f)
    }
}
