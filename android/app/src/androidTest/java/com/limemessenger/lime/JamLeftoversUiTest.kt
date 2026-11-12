package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.Samples
import com.limemessenger.lime.chats.StickerPack
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.jam.SavedPosts
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chat.GifPanel
import com.limemessenger.lime.ui.jam.JamFeedScreen
import com.limemessenger.lime.ui.jam.JamReaderScreen
import com.limemessenger.lime.ui.jam.jamPictureJpeg
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

/** LIME-412: Report on a jam post, the feed's filter sheet, the show-stickers switch and the jam picture's scaling, on made-up data (no network). */
@RunWith(AndroidJUnit4::class)
class JamLeftoversUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private val alias = "lime.test.jamleftovers"

    private class MemorySaved : SavedPosts {
        private var ids = emptySet<String>()
        override fun all() = ids
        override fun set(postId: String, on: Boolean) { ids = if (on) ids + postId else ids - postId }
    }
    private val posts = listOf(
        Samples.jamPost("quick", "j1", at = 3_000, plain = "A quick post about magnets"),
        Samples.jamPost("co", "j1", at = 2_000, plain = "A post written together", coauthors = listOf("writer2")),
        Samples.jamPost("article", "j1", at = 1_000, kind = "article", title = "How we built a bridge", plain = "We spent a week on bridges."),
    )
    private fun model() = JamModel({ store }, nameOf = { "Ben Android" }, source = { listOf(Samples.jam("j1", "Ben's classroom notes")) to posts }, savedStore = MemorySaved())
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun ids() = posts.map { it.postId }.filter { count("jam-post-$it") > 0 }

    @Before fun setUp() {
        dir = File(context.cacheDir, "jamleft-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("jamleft-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        StickerPack.setShown(context, true)
    }

    @After fun tearDown() { StickerPack.setShown(context, true); store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
    @Test fun theFilterSheetNarrowsTheFeedCountsWhatIsOnAndClearsIt() {
        val m = model()
        runBlocking { m.reload() }
        rule.setContent { LimeTheme { JamFeedScreen(m) {} } }
        rule.waitUntil(5_000) { count("jam-post-quick") > 0 }
        assertEquals(listOf("quick", "co", "article"), ids())
        assertEquals("Filter", words("jam-filter-button"))
        rule.onNodeWithTag("jam-filter-button", useUnmergedTree = true).performScrollTo().performClick()
        rule.waitUntil(5_000) { count("jam-filter-sheet") > 0 }
        rule.onNodeWithTag("jam-filter-coauthored", useUnmergedTree = true).performClick(); rule.waitForIdle()
        assertEquals("only the co-authored post is left", 1, m.shown.size); assertEquals("co", m.shown.single().postId)
        assertEquals(1, m.activeFilters)
        rule.onNodeWithTag("jam-filter-clear", useUnmergedTree = true).performClick(); rule.waitForIdle()
        assertEquals(0, m.activeFilters); assertEquals(3, m.shown.size)
        rule.onNodeWithTag("jam-filter-bands", useUnmergedTree = true).performClick(); rule.waitForIdle()
        assertEquals("none of these posts is shown as a band", 0, m.shown.size)
        rule.onNodeWithTag("jam-filter-done", useUnmergedTree = true).performClick(); rule.waitForIdle()
        assertTrue("the pill counts the filters on", words("jam-filter-button").contains("(1)") || words("jam-filter-button") == "Filter (1)")
    }

    private fun words(tag: String): String = rule.onNodeWithTag(tag).fetchSemanticsNode().config.let { c ->
        if (SemanticsProperties.Text in c) c[SemanticsProperties.Text].joinToString { it.text } else c[SemanticsProperties.ContentDescription].joinToString()
    }

    @Test fun aPostByAnotherTeacherCanBeReportedWithTheSameSheetAsAMessage() {
        val m = model()
        runBlocking { m.reload() }
        rule.setContent { LimeTheme { JamReaderScreen(posts[0], m, myId = "me", chats = chats, onBack = {}) } }
        rule.waitUntil(5_000) { count("jam-reader-report") > 0 }
        rule.onNodeWithTag("jam-reader-report", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("report-sheet") > 0 }
        assertEquals("the sheet shows what is being reported", 1, count("report-preview"))
    }

    @Test fun theShowStickersSwitchHidesTheStickerTabAndComesBack() {
        StickerPack.setShown(context, false)
        rule.setContent { LimeTheme { GifPanel(chats, onSend = {}, onDismiss = {}) } }
        rule.waitUntil(5_000) { count("gif-tab-gifs") > 0 }
        assertEquals("no sticker tab while the switch is off", 0, count("gif-tab-stickers"))
        StickerPack.setShown(context, true)
        assertTrue(StickerPack.shown(context))
    }

    @Test fun aJamPictureIsScaledToAJpegUnderOneMebibyte() {
        val big = android.graphics.Bitmap.createBitmap(2000, 1500, android.graphics.Bitmap.Config.ARGB_8888)
        val rnd = java.util.Random(7)
        val px = IntArray(2000 * 1500) { (0xFF shl 24) or rnd.nextInt(0xFFFFFF) }   // noise: the worst case for JPEG
        big.setPixels(px, 0, 2000, 0, 0, 2000, 1500)
        val jpeg = jamPictureJpeg(big)
        assertNotNull(jpeg)
        assertTrue("at most 1 MiB, was ${jpeg!!.size}", jpeg.size <= 1024 * 1024)
        val o = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
        android.graphics.BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, o)
        assertTrue("at most 1600 px on the long edge: ${o.outWidth}x${o.outHeight}", maxOf(o.outWidth, o.outHeight) <= 1600)
    }
}
