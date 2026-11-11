package com.limemessenger.lime

import android.os.Build
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.GifFiles
import com.limemessenger.lime.chats.StickerPack
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chat.GifPanel
import com.limemessenger.lime.ui.chat.GifThumb
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore
import uniffi.lime_core.OutgoingAttachment

/** LIME-313 on a real local store: lime's 24 stickers, My GIFs (add by words, search, send, remove), a sticker named for TalkBack, and the Play button when animations are off. */
@RunWith(AndroidJUnit4::class)
class GifPanelUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var model: ChatsModel
    private val alias = "lime.test.gifs"
    /** The smallest valid GIF: one transparent pixel. */
    private val tiny = android.util.Base64.decode("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7", android.util.Base64.DEFAULT)

    @Before fun setUp() {
        dir = File(context.cacheDir, "gifs-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("gif-user")).store
        model = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun words(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()

    @Test fun theStickerPackHasTwentyFourAndASentStickerKeepsItsName() {
        val pack = StickerPack.entries(context)
        assertEquals(24, pack.size)
        val sent = mutableListOf<OutgoingAttachment>()
        rule.setContent { LimeTheme { GifPanel(model, onSend = { sent += it }, onDismiss = {}) } }
        rule.waitUntil(5_000) { count("gif-sticker-thank-you") > 0 }
        assertEquals("lime sticker: Thank you!", words("gif-sticker-thank-you"))
        // A word finds it (the core's rule); nothing matching says so.
        rule.onNodeWithTag("gif-search", useUnmergedTree = true).performTextInput("thanks")
        rule.waitUntil(5_000) { count("gif-sticker-hi") == 0 && count("gif-sticker-thank-you") > 0 }
        rule.onNodeWithTag("gif-sticker-thank-you", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { sent.isNotEmpty() }
        val gif = sent.single()
        assertEquals("lime-sticker-thank-you.gif", gif.name); assertEquals("image/gif", gif.mime)
        assertTrue("the same bytes as the file", gif.bytes.contentEquals(StickerPack.bytes(context, "thank-you")))
        assertNotNull(gif.width); assertTrue(gif.thumb.isNotEmpty())
        assertEquals("lime sticker: Thank you!", uniffi.lime_core.stickerSpokenName(gif.name, pack))
    }

    @Test fun aGifIsAddedByItsWordsFoundSentAndRemoved() {
        val id = store.addMyGif(tiny, "cat typing", "", "", 1u, 1u)
        val sent = mutableListOf<OutgoingAttachment>()
        rule.setContent { LimeTheme { GifPanel(model, onSend = { sent += it }, onDismiss = {}) } }
        rule.onNodeWithTag("gif-tab-gifs", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("gif-mine-$id") > 0 }
        assertEquals("GIF: cat typing", words("gif-mine-$id"))
        rule.onNodeWithTag("gif-search", useUnmergedTree = true).performTextInput("zzz")
        rule.waitUntil(5_000) { count("gif-mine-$id") == 0 }
        rule.onNodeWithTag("gif-search", useUnmergedTree = true).performTextInput("")
        // (clear and look again by a word that matches)
        rule.runOnIdle { }
        rule.onNodeWithTag("gif-tab-stickers", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("gif-tab-gifs", useUnmergedTree = true).performClick()
        // Sending: the same bytes, with its size and first frame.
        val made = GifFiles.attachment(tiny).getOrThrow()
        assertEquals(1u, made.width); assertTrue(made.thumb.isNotEmpty())
        assertTrue(GifFiles.attachment(byteArrayOf(1, 2, 3)).isFailure)
        store.removeMyGif(id)
        assertEquals(0, store.listMyGifs(10u).size)
    }

    @Test fun withAnimationsOffAGifWaitsForPlay() {
        assumeTrue("the platform's animated decoder is API 28+", Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
        val ui = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun scale(value: String) = ui.executeShellCommand("settings put global animator_duration_scale $value").use { java.io.FileInputStream(it.fileDescriptor).readBytes() }
        scale("0")
        try {
            rule.setContent { LimeTheme { GifThumb(tiny, null, 1f, "GIF", "gif-thumb") {} } }
            rule.waitUntil(5_000) { count("gif-thumb-toggle") > 0 }
            assertEquals("Play", words("gif-thumb-toggle"))
            rule.onNodeWithTag("gif-thumb-toggle", useUnmergedTree = true).performClick()
            rule.waitUntil(5_000) { words("gif-thumb-toggle") == "Stop" }
        } finally { scale("1") }
    }
}
