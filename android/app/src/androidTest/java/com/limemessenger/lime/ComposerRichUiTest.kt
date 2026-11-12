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
/** LIME-405: the rich-text composer on a real local store: the strip, styled text, lists, links, and what is sent (the core's Markdown). No network. */
@RunWith(AndroidJUnit4::class)
class ComposerRichUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var dm: ChatModel
    private lateinit var dmId: String
    private val alias = "lime.test.composer.rich"

    @Before fun setUp() {
        dir = File(context.cacheDir, "rich-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("rich-user")).store
        dmId = store.startDm("ben-test", "Ben Test")
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        dm = ChatModel(dmId, chats, accountSignedIn = false)
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun show(fontScale: Float = 1f, model: ChatModel = dm) {
        rule.setContent {
            val d = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(d.density, fontScale)) { LimeTheme { ChatScreen(model, chats, onBack = {}) } }
        }
        rule.waitUntil(5_000) { count("composer-field") > 0 }
    }
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun field() = rule.onNodeWithTag("composer-field")
    /** Types one character at a time, as a keyboard does (a list starts when a marker and a space are typed, Return is its own key). */
    private fun type(text: String) { for (ch in text) { field().performTextInput(ch.toString()); rule.waitForIdle() } }
    private fun fieldText() = field().fetchSemanticsNode().config[SemanticsProperties.EditableText].text
    private fun click(tag: String) {
        // (On a narrow phone a strip button can be past the edge: scroll it in, as a thumb would.)
        runCatching { rule.onNodeWithTag(tag, useUnmergedTree = true).performScrollTo() }
        rule.onNodeWithTag(tag, useUnmergedTree = true).performClick(); rule.waitForIdle()
    }
    private fun words(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
    private fun selected(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Selected]
    private fun bounds(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
    /** Sends what is in the field and returns the text the core stored for it. */
    private fun send(): String {
        val before = store.listMessages(dmId).size
        click("send-button")
        rule.waitUntil(10_000) { store.listMessages(dmId).size > before }
        return store.listMessages(dmId).last { it.senderId == null }.text
    }

    @Test fun aSelectedWordMadeBoldIsSentAsBoldMarkdownAndTheBubbleShowsItBold() {
        show()
        field().performTextInput("hi")
        field().performTextInputSelection(TextRange(0, 2))
        rule.waitUntil(5_000) { count("fmt-bold") > 0 }   // a selection shows the strip
        click("fmt-bold")
        assertTrue(selected("fmt-bold"))
        assertEquals("Bold", words("fmt-bold"))
        assertEquals("**hi**", send())
        rule.waitUntil(5_000) { count("message-text-${store.listMessages(dmId).last { it.senderId == null }.id}") > 0 }
        val bold = rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("a bold hi") { n ->
            n.config.getOrNull(SemanticsProperties.Text)?.any { a -> a.text == "hi" && a.spanStyles.any { it.item.fontWeight == androidx.compose.ui.text.font.FontWeight.Bold } } == true
        }, useUnmergedTree = true).fetchSemanticsNodes()
        assertTrue("the bubble draws it bold", bold.isNotEmpty())
        assertEquals("the field is empty after sending", "", fieldText())
    }

    @Test fun aListContinuesOnReturnAndAnEmptyItemEndsItWithNoMarkerInTheText() {
        show()
        click("composer-aa")
        rule.waitUntil(5_000) { count("fmt-bullets") > 0 }
        click("fmt-bullets")
        assertTrue(selected("fmt-bullets"))
        type("one\ntwo")
        assertEquals("the field shows the markers it draws (what a screen reader reads)", "\u2022 one\n\u2022 two", fieldText())
        type("\n")      // an empty third item
        type("\n")      // Return on it ends the list
        assertEquals("\u2022 one\n\u2022 two\n", fieldText())
        assertFalse(selected("fmt-bullets"))
        type("after")
        assertEquals("- one\n- two\n\nafter", send())
    }

    @Test fun aTypedMarkerStartsAListAndNumbersCountOn() {
        show()
        type("1. first\nsecond")
        assertEquals("1. first\n2. second", fieldText())
        assertEquals("1. first\n2. second", send())
    }

    @Test fun styledTextCarriesOnWhileTypingAndEndsWhenTurnedOff() {
        show()
        click("composer-aa")
        click("fmt-italic")                    // pressed with nothing selected: the next typing is italic
        assertTrue(selected("fmt-italic"))
        type("slant")
        click("fmt-italic")
        type(" and plain")
        assertEquals("*slant* and plain", send())
    }

    @Test fun aLinkIsAddedByTheCoreCheckedDialogAndARefusedAddressSaysSo() {
        show()
        field().performTextInput("see the plan today")
        field().performTextInputSelection(TextRange(8, 12))
        rule.waitUntil(5_000) { count("fmt-link") > 0 }
        click("fmt-link")
        rule.waitUntil(5_000) { count("link-url") > 0 }
        rule.onNodeWithTag("link-url", useUnmergedTree = true).performTextInput("javascript:alert(1)")
        click("link-apply")
        assertEquals(1, count("link-error"))
        rule.onNodeWithTag("link-url", useUnmergedTree = true).performTextClearance()
        rule.onNodeWithTag("link-url", useUnmergedTree = true).performTextInput("limemessenger.com/plan")
        click("link-apply")
        rule.waitUntil(5_000) { count("link-url") == 0 }
        assertEquals("see the [plan](https://limemessenger.com/plan) today", send())
    }

    @Test fun aPlainMessageStaysPlain() {
        show()
        field().performTextInput("Hello team, lunch at noon?")
        assertEquals("Hello team, lunch at noon?", send())
    }

    @Test fun theStripSitsInsideTheCardUnderTheRowAndNeverCoversIt() {
        show()
        assertEquals(0, count("fmt-strip"))
        click("composer-aa")
        rule.waitUntil(5_000) { count("fmt-strip") > 0 }
        assertTrue("Aa is pressed while the strip shows", selected("composer-aa"))
        val card = bounds("composer-card"); val strip = bounds("fmt-strip"); val row = bounds("composer-plus")
        assertTrue("inside the card", strip.left >= card.left && strip.right <= card.right && strip.bottom <= card.bottom + 1f)
        assertTrue("under the tool row", strip.top >= row.bottom - 1f)
        for (tag in listOf("fmt-bold", "fmt-italic", "fmt-underline", "fmt-strike", "fmt-link", "fmt-code", "fmt-bullets", "fmt-numbers", "fmt-close")) {
            val h = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().size.height   // (a button scrolled out of view has empty bounds, not an empty size)
            assertTrue("$tag is 48 dp", h >= 48f * rule.density.density - 0.5f)
        }
        assertEquals(0, count("fmt-outdent")); // not in a list
        click("fmt-close")
        assertEquals(0, count("fmt-strip"))
        assertFalse(selected("composer-aa"))
    }

    @Test fun atTheLargestFontTheStripScrollsSidewaysAndKeepsItsButtons() {
        show(fontScale = 2f)
        click("composer-aa")
        rule.waitUntil(5_000) { count("fmt-strip") > 0 }
        val card = bounds("composer-card"); val strip = bounds("fmt-strip")
        assertTrue(strip.left >= card.left && strip.right <= card.right)
        assertEquals(1, count("fmt-scroll"))
        assertTrue(rule.onNodeWithTag("fmt-bold", useUnmergedTree = true).fetchSemanticsNode().size.height >= 48f * rule.density.density - 0.5f)
        assertEquals("Close formatting", words("fmt-close"))
    }

    @Test fun backspaceAtTheStartOfAnEmptyListItemEndsTheItemAndNotTheLineBefore() {
        show()
        type("a\n- b")
        assertEquals("a\n\u2022 b", fieldText())
        field().performKeyInput { pressKey(androidx.compose.ui.input.key.Key.Backspace) }   // deletes the b
        rule.waitForIdle()
        assertEquals("a\n\u2022 ", fieldText())
        field().performKeyInput { pressKey(androidx.compose.ui.input.key.Key.Backspace) }   // at the start of the item: the item becomes plain text
        rule.waitForIdle()
        assertEquals("the item ended and the line before is intact", "a\n", fieldText())
        assertEquals("a", send())
    }

    /** Runs the message's TalkBack action `label` (the same code as the long-press menu's). */
    private fun action(messageId: String, label: String) {
        val node = rule.onNodeWithTag("message-$messageId").fetchSemanticsNode()
        val all = node.config[androidx.compose.ui.semantics.SemanticsActions.CustomActions]
        val act = all.firstOrNull { it.label == label } ?: throw AssertionError("no \"$label\" among ${all.map { it.label }}; state ${store.listMessages(dmId).last { it.senderId == null }.localState}")
        rule.runOnUiThread { act.action() }
        rule.waitForIdle()
    }
    private fun ownId() = store.listMessages(dmId).last { it.senderId == null }.id

    // LIME-406 A (the edit itself, and that it is delivered, is the core's and `StagingActionsTest`'s; here: the composer's side)
    private fun showEditing(markdown: String, draft: String = ""): String {
        runBlocking { dm.send(markdown) }
        val message = store.listMessages(dmId).last { it.senderId == null }
        rule.setContent { LimeTheme { ChatScreen(dm, chats, onBack = {}, seedEdit = message) } }
        rule.waitUntil(5_000) { count("edit-banner") > 0 }
        return message.id
    }

    @Test fun editLoadsTheMessagesMarkdownWithItsFormattingAndSaveReplacesSend() {
        showEditing("**bold** word")
        assertEquals("the message's words, formatting kept (the bold word is drawn, not shown as asterisks)", "bold word", fieldText())
        assertEquals("Save", words("send-button"))
        assertEquals(0, count("voice-mic"))
        type(" and more")
        assertEquals("Save", words("send-button"))
    }

    @Test fun cancellingAnEditChangesNothingAndTheCancelButtonSaysSo() {
        showEditing("keep me")
        assertEquals("Cancel editing", words("edit-cancel"))
        click("edit-cancel")
        rule.waitUntil(5_000) { count("edit-banner") == 0 }
        assertEquals("", fieldText())
        assertEquals("keep me", store.listMessages(dmId).last { it.senderId == null }.text)
        assertFalse(store.listMessages(dmId).last { it.senderId == null }.edited)
        assertEquals("the microphone is back", 1, count("voice-mic"))
    }

    // ---- LIME-410: the composer's edges

    @Test fun aCaretAtTheStartOfAListItemTypesInsideTheItemWithoutANewMarker() {
        show()
        type("- one\nb")
        field().performKeyInput { pressKey(androidx.compose.ui.input.key.Key.DirectionLeft) }; rule.waitForIdle()
        type("x")
        assertEquals("the text goes in front of the item's words and the marker is not doubled", "\u2022 one\n\u2022 xb", fieldText())
        assertEquals("- one\n- xb", send())
    }

    private fun enabled(tag: String) = androidx.compose.ui.semantics.SemanticsProperties.Disabled !in rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config
    private fun ctrlZ(shift: Boolean = false) = field().performKeyInput {
        keyDown(androidx.compose.ui.input.key.Key.CtrlLeft); if (shift) keyDown(androidx.compose.ui.input.key.Key.ShiftLeft)
        pressKey(androidx.compose.ui.input.key.Key.Z)
        if (shift) keyUp(androidx.compose.ui.input.key.Key.ShiftLeft); keyUp(androidx.compose.ui.input.key.Key.CtrlLeft)
    }

    @Test fun undoAfterBoldTakesTheBoldBackAndRedoBringsItBackAndTheFieldAndTheMessageAlwaysAgree() {
        // LIME-414 (night 4 had turned undo off: the field's own undo changed the text without the document). Now the core's history undoes text AND styles in one step.
        show()
        type("hello")
        field().performTextInputSelection(TextRange(0, 5))
        rule.waitUntil(5_000) { count("fmt-bold") > 0 }
        click("fmt-bold")
        assertTrue(selected("fmt-bold"))
        ctrlZ()
        rule.waitForIdle()
        assertEquals("hello", fieldText())
        assertTrue("the bold is off again", !selected("fmt-bold"))
        ctrlZ(shift = true)
        rule.waitForIdle()
        assertEquals("hello", fieldText())
        assertTrue("redo brings the bold back", selected("fmt-bold"))
        assertEquals("**hello**", send())
    }

    @Test fun undoAndRedoButtonsAreInTheStripWithTheirEnabledStateAndDoTheSame() {
        show()
        click("composer-aa")
        rule.waitUntil(5_000) { count("fmt-undo") > 0 }
        assertTrue("nothing to undo yet", !enabled("fmt-undo")); assertTrue(!enabled("fmt-redo"))
        assertEquals("Undo", words("fmt-undo")); assertEquals("Redo", words("fmt-redo"))
        type("hello")
        assertTrue("typing can be undone", enabled("fmt-undo"))
        click("fmt-undo")
        assertEquals("the whole run of typing is one step", "", fieldText())
        assertTrue(enabled("fmt-redo")); assertTrue(!enabled("fmt-undo"))
        click("fmt-redo")
        assertEquals("hello", fieldText())
        assertTrue("a new edit clears redo", run { type("!"); !enabled("fmt-redo") })
        assertEquals("hello!", send())
    }

    @Test fun aListAndReturnAreStepsOfTheirOwnAndUndoTakesThemBackOneAtATime() {
        show()
        type("- one")
        assertEquals("\u2022 one", fieldText())
        type("\ntwo")
        assertEquals("\u2022 one\n\u2022 two", fieldText())
        ctrlZ()   // the typed "two"
        rule.waitForIdle()
        assertEquals("\u2022 one\n\u2022 ", fieldText())
        ctrlZ()   // Return
        rule.waitForIdle()
        assertEquals("\u2022 one", fieldText())
        ctrlZ(); ctrlZ()   // the typing of "one", then the "- " that made the list: back to nothing
        rule.waitForIdle()
        assertEquals("", fieldText())
        ctrlZ(shift = true); ctrlZ(shift = true); ctrlZ(shift = true); ctrlZ(shift = true)
        rule.waitForIdle()
        assertEquals("redo walks all the way forward, list levels included", "\u2022 one\n\u2022 two", fieldText())
        assertEquals("- one\n- two", send())
    }

    @Test fun sendingStartsWithAnEmptyHistory() {
        show()
        type("hi")
        send()
        click("composer-aa")
        rule.waitUntil(5_000) { count("fmt-undo") > 0 }
        assertTrue("nothing to undo after a send", !enabled("fmt-undo"))
    }
}
