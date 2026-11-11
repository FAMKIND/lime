package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
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
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInputSelection
import androidx.compose.ui.text.TextRange
import com.limemessenger.lime.chats.LinkPreviewFetcher
import com.limemessenger.lime.ui.chat.LinkCard
import com.limemessenger.lime.ui.chat.LocalLinkPreviewFetcher
import uniffi.lime_core.LinkPreview
import uniffi.lime_core.OutgoingPreview
/** LIME-407 on a real local store, with a fake fetcher (no internet): the draft card above the field, ✕ drops it, the setting, a photo in the draft, a link added with the Link button, send, and the card in a bubble. */
@RunWith(AndroidJUnit4::class)
class LinkPreviewUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var dm: ChatModel
    private val alias = "lime.test.linkpreview"
    private val asked = mutableListOf<String>()

    /** Makes a card for any address and remembers what it was asked (never touches the network). */
    private val fake = object : LinkPreviewFetcher() {
        override suspend fun make(address: String): OutgoingPreview? {
            asked += address
            val jpeg = java.io.ByteArrayOutputStream().also { out -> android.graphics.Bitmap.createBitmap(64, 34, android.graphics.Bitmap.Config.ARGB_8888).also { android.graphics.Canvas(it).drawColor(0xFF4CAF50.toInt()) }.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, out) }.toByteArray()
            return OutgoingPreview(address, "Fractions made visible", "example.org", jpeg, 64u, 34u)
        }
    }

    @Before fun setUp() {
        dir = File(context.cacheDir, "linkpreview-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("linkpreview-user")).store
        val id = store.startDm("ben-test", "Ben Test")
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        dm = ChatModel(id, chats, accountSignedIn = false)
        (context.applicationContext as LimeApp).linkPreviewPrefs.change(true)
    }

    @After fun tearDown() { (context.applicationContext as LimeApp).linkPreviewPrefs.change(true); store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun show(photos: List<uniffi.lime_core.OutgoingAttachment> = emptyList()) {
        rule.setContent { CompositionLocalProvider(LocalLinkPreviewFetcher provides fake) { LimeTheme { ChatScreen(dm, chats, onBack = {}, seedPhotos = photos) } } }
        rule.waitUntil(5_000) { count("composer-field") > 0 }
    }
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun type(text: String) { for (ch in text) { rule.onNodeWithTag("composer-field").performTextInput(ch.toString()); rule.waitForIdle() } }
    private fun text(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].joinToString("") { it.text }

    @Test fun aWrittenLinkMakesADraftCardAfterAPauseAndTheXDropsIt() {
        show()
        type("see https://example.org/lesson today")
        assertEquals("not before the pause", 0, count("link-draft"))
        rule.waitUntil(8_000) { count("link-draft") > 0 }
        assertEquals("Fractions made visible", text("link-draft-title"))
        assertEquals("example.org", text("link-draft-site"))
        assertEquals(listOf("https://example.org/lesson"), asked.distinct())
        // More typing after the card is there does not fetch again.
        val before = asked.size
        type(" ok")
        rule.waitForIdle(); Thread.sleep(1_200)
        assertEquals(before, asked.size)
        rule.onNodeWithTag("link-draft-remove", useUnmergedTree = true).performClick()
        rule.waitForIdle()
        assertEquals(0, count("link-draft"))
        type("!")
        Thread.sleep(1_200)
        assertEquals("a dropped card does not come back for the same link", 0, count("link-draft"))
    }

    @Test fun noLinkNoCardAndASettingOffMakesNoFetchAtAll() {
        show()
        type("no links here, just words")
        Thread.sleep(1_200)
        assertEquals(0, count("link-draft")); assertTrue(asked.isEmpty())
        rule.onNodeWithTag("composer-field").performTextClearance()
        (context.applicationContext as LimeApp).linkPreviewPrefs.change(false)
        type("https://example.org/off")
        Thread.sleep(1_500)
        assertEquals("the setting is off: nothing was fetched and no card was made", 0, count("link-draft"))
        assertTrue(asked.isEmpty())
    }

    @Test fun aPhotoInTheDraftMeansNoCard() {
        val photo = uniffi.lime_core.OutgoingAttachment(ByteArray(10), "a.jpg", "image/jpeg", 1u, 1u, null, ByteArray(0), ByteArray(0), "")
        show(photos = listOf(photo))
        type("https://example.org/photo")
        Thread.sleep(1_500)
        assertEquals(0, count("link-draft")); assertTrue(asked.isEmpty())
    }

    @Test fun aLinkAddedWithTheLinkButtonCountsAndRemovingItRemovesTheCard() {
        show()
        type("the plan")
        rule.onNodeWithTag("composer-field").performTextInputSelection(TextRange(0, 8))
        rule.waitUntil(5_000) { count("fmt-link") > 0 }
        rule.onNodeWithTag("fmt-link", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("link-url") > 0 }
        rule.onNodeWithTag("link-url", useUnmergedTree = true).performTextInput("example.org/plan")
        rule.onNodeWithTag("link-apply", useUnmergedTree = true).performClick()
        rule.waitUntil(8_000) { count("link-draft") > 0 }
        assertEquals(listOf("https://example.org/plan"), asked.distinct())
        rule.onNodeWithTag("fmt-link", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("link-remove") > 0 }
        rule.onNodeWithTag("link-remove", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("link-draft") == 0 }
    }

    @Test fun sendingGivesTheCardToTheMessageAndClearsEverything() {
        val sent = mutableListOf<Pair<String, OutgoingPreview>>()
        dm.previewHook = { text, preview -> sent += text to preview; true }
        show()
        type("read https://example.org/lesson")
        rule.waitUntil(8_000) { count("link-draft") > 0 }
        rule.onNodeWithTag("send-button").performClick()
        rule.waitUntil(5_000) { sent.isNotEmpty() }
        assertEquals("read https://example.org/lesson", sent.single().first)
        assertEquals("Fractions made visible", sent.single().second.title)
        rule.waitUntil(5_000) { count("link-draft") == 0 }
        assertEquals("", rule.onNodeWithTag("composer-field").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.EditableText].text)
    }

    @Test fun aCardInABubbleIsOneStopOpensAnHttpsLinkAtOnceAndAsksAboutAnyOther() {
        val opened = mutableListOf<String>()
        val handler = object : UriHandler { override fun openUri(uri: String) { opened += uri } }
        rule.setContent {
            CompositionLocalProvider(LocalUriHandler provides handler) {
                LimeTheme {
                    androidx.compose.foundation.layout.Column {
                        LinkCard("a", LinkPreview("https://example.org/lesson", "Fractions made visible", "example.org", null), false, dm)
                        LinkCard("b", LinkPreview("http://example.org/old", "An old page", "example.org", null), false, dm)
                    }
                }
            }
        }
        assertEquals("Link: Fractions made visible, example.org", rule.onNodeWithTag("link-card-a", useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString())
        rule.onNodeWithTag("link-card-a", useUnmergedTree = true).performClick()
        rule.waitForIdle()
        assertEquals(listOf("https://example.org/lesson"), opened)
        rule.onNodeWithTag("link-card-b", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("link-open-confirm") > 0 }
        assertEquals("nothing opened before the person said yes", 1, opened.size)
        rule.onNodeWithTag("link-open-confirm", useUnmergedTree = true).performClick()
        rule.waitForIdle()
        assertEquals(listOf("https://example.org/lesson", "http://example.org/old"), opened)
    }
}
