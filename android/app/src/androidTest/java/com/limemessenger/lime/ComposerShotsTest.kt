package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.down
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInputSelection
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.up
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.VoiceCapture
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chat.ChatScreen
import com.limemessenger.lime.ui.chat.LocalVoiceCapture
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.ByteArrayOutputStream
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore
import uniffi.lime_core.OutgoingAttachment

/**
 * NOT a test of anything: takes the composer's screenshots (LIME-403) into files/shots for `tools/shots-403.sh`. A chat from the core's sample data, no network.
 * Marked `@Staging` only so the plain pass skips it (the script runs it by class name).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class ComposerShotsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val shots get() = File(context.filesDir, "shots").also { it.mkdirs() }
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var chat: ChatModel
    private lateinit var groupChat: ChatModel
    private val alias = "lime.test.composer.shots"

    @Before fun setUp() {
        dir = File(context.cacheDir, "composershots-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("shots-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        chat = ChatModel(chats.chats.first { it.title == "Autumn Reyes" }.id, chats, accountSignedIn = false)
        groupChat = ChatModel(chats.conversations.first { it.isGroup }.id, chats, accountSignedIn = false)
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private class FakeMic : VoiceCapture {
        override fun start(podcast: Boolean) = true
        override fun level() = 0.6f
        override fun stop(): ByteArray? = ByteArray(4_000) { 5 }
        override fun cancel() {}
    }
    private fun shot(name: String) {
        rule.waitForIdle()
        Thread.sleep(600)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(shots, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun photo(): OutgoingAttachment {
        val bitmap = Bitmap.createBitmap(240, 160, Bitmap.Config.ARGB_8888).also { b -> android.graphics.Canvas(b).drawColor(0xFF9AD4A8.toInt()) }
        val out = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }.toByteArray()
        return OutgoingAttachment(out, "a.jpg", "image/jpeg", 240u, 160u, null, ByteArray(0), ByteArray(0), "")
    }
    private fun show(fontScale: Float = 1f, dark: Boolean = false, photos: List<OutgoingAttachment> = emptyList(), model: ChatModel = chat, edit: uniffi.lime_core.MessageItem? = null) = rule.setContent {
        val d = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(d.density, fontScale), LocalVoiceCapture provides { FakeMic() }) {
            LimeTheme(dark = dark) { ChatScreen(model, chats, onBack = {}, seedPhotos = photos, seedEdit = edit) }
        }
        androidx.compose.runtime.LaunchedEffect(Unit) { model.reload() }
    }

    @Test fun empty() { show(); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }; shot("1-empty") }

    @Test fun longMessage() {
        show(); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        rule.onNodeWithTag("composer-field").performTextInput("Hello team,\nlunch at noon?\nPlease bring your notes\nfor the Friday review.\nThe room is 204.\nSee you there!")
        shot("2-six-lines")
    }

    @Test fun photoDraft() {
        show(photos = listOf(photo(), photo())); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        rule.onNodeWithTag("composer-field").performTextInput("Look at the bridges")
        shot("3-photo-draft")
    }

    @Test fun recording() {
        show(); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { down(center) }
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("recording-bar"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        Thread.sleep(1_200); shot("4-recording")
        rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { up() }
    }

    @Test fun largestFont() {
        show(fontScale = 2f); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        rule.onNodeWithTag("composer-field").performTextInput("Hello team, lunch at noon?")
        shot("5-font-2")
    }

    @Test fun dark() {
        show(dark = true); rule.waitUntil(5_000) { chat.messages.isNotEmpty() }
        rule.onNodeWithTag("composer-field").performTextInput("Hello")
        shot("6-dark")
    }

    private fun type(text: String) { for (ch in text) { rule.onNodeWithTag("composer-field").performTextInput(ch.toString()); rule.waitForIdle() } }
    private fun click(tag: String) {
        runCatching { rule.onNodeWithTag(tag, useUnmergedTree = true).performScrollTo() }   // a strip button may be past the edge: scroll it in, as a thumb would
        rule.onNodeWithTag(tag, useUnmergedTree = true).performClick(); rule.waitForIdle()
    }
    private fun ready() { rule.waitUntil(5_000) { chat.messages.isNotEmpty() } }

    @Test fun stripOpen() { show(); ready(); click("composer-aa"); shot("7-strip-open") }

    @Test fun boldInTheField() {
        show(); ready()
        type("Please read this word carefully")
        rule.onNodeWithTag("composer-field").performTextInputSelection(TextRange(12, 16))
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("fmt-bold"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        click("fmt-bold"); shot("8-bold-in-field")
    }

    @Test fun aList() {
        show(); ready()
        click("composer-aa")
        type("Bring to the staff meeting:\n- the unit plan\nthe exit tickets\n")
        click("fmt-indent"); type("blank copies"); shot("9-list")
    }

    @Test fun aLink() {
        show(); ready()
        type("Here is the plan: limemessenger.com")
        rule.onNodeWithTag("composer-field").performTextInputSelection(TextRange(19, 35))
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("fmt-link"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        click("fmt-link"); rule.onNodeWithTag("link-url", useUnmergedTree = true).performTextInput("limemessenger.com/plan"); click("link-apply")
        click("composer-aa"); shot("10-link")
    }

    @Test fun stripLargestFont() { show(fontScale = 2f); ready(); click("composer-aa"); type("Bold plan"); shot("11-strip-font-2") }

    @Test fun stripDark() {
        show(dark = true); ready(); click("composer-aa"); type("- one\ntwo")
        rule.onNodeWithTag("composer-field").performTextInputSelection(TextRange(0, 3))
        click("fmt-bold"); shot("12-strip-dark")
    }

    private fun ready(m: ChatModel) { rule.waitUntil(5_000) { m.messages.isNotEmpty() } }
    private val tiny = android.util.Base64.decode("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7", android.util.Base64.DEFAULT)

    @Test fun mentionPanel() { show(model = groupChat); ready(groupChat); type("Thanks @"); rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("mention-suggestions"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }; shot("13-mention-panel") }

    @Test fun mentionPanelDark() { show(dark = true, model = groupChat); ready(groupChat); type("@"); rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("mention-suggestions"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }; shot("13b-mention-panel-dark") }

    @Test fun expandedDraft() {
        show(); ready(chat)
        rule.onNodeWithTag("composer-field").performTextInput((1..14).joinToString("\n") { "Agenda item $it for Friday" })
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("composer-expand"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        shot("14a-long-draft-collapsed"); click("composer-expand"); shot("14-expanded")
    }

    /** Run with the emulator rotated to landscape (`tools/shots-406.sh` does that for this one test). */
    @Test fun landscapeExpanded() {
        show(); ready(chat)
        rule.onNodeWithTag("composer-field").performTextInput((1..14).joinToString("\n") { "Agenda item $it for Friday" })
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("composer-expand"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        click("composer-expand"); shot("15-landscape-expanded")
    }

    @Test fun editingBanner() {
        runBlocking { chat.send("**Bold** plan for Friday") }
        val mine = store.listMessages(chat.conversationId).last { it.senderId == null }
        show(model = chat, edit = mine); rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("edit-banner"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        shot("16-editing-banner")
    }

    @Test fun editingBannerLargestFontDark() {
        runBlocking { chat.send("**Bold** plan for Friday") }
        val mine = store.listMessages(chat.conversationId).last { it.senderId == null }
        show(fontScale = 2f, dark = true, model = chat, edit = mine); rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("edit-banner"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        shot("16b-editing-font-2-dark")
    }

    @Test fun slashStrip() {
        store.addMyGif(tiny, "cat typing", "", "", 1u, 1u)
        show(); ready(chat); type("/c")
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("gif-slash-strip"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        shot("17-slash-strip")
    }

    @Test fun slashStripFontDark() {
        show(fontScale = 2f, dark = true); ready(chat); type("/thank")
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("gif-slash-strip"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
        shot("17b-slash-font-2-dark")
    }
}
