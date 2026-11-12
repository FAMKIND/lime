package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import android.graphics.Bitmap
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

/** NOT a test: the LIME-412 screenshots (the feed with its Filter sheet, the post reader with Report, the report sheet; light, dark and 200% font) into files/shots (`tools/shots-412.sh`). `@Staging` only so the plain pass skips it. */
@Staging
@RunWith(AndroidJUnit4::class)
class JamShotsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private val alias = "lime.test.jamshots"

    private class MemorySaved : SavedPosts {
        private var ids = emptySet<String>()
        override fun all() = ids
        override fun set(postId: String, on: Boolean) { ids = if (on) ids + postId else ids - postId }
    }
    private val posts = listOf(
        Samples.jamPost("quick", "j1", at = 3_000, plain = "A quick post about magnets"),
        Samples.jamPost("co", "j1", at = 2_000, plain = "A post written together", coauthors = listOf("writer2")),
        Samples.jamPost("article", "j1", at = 1_000, kind = "article", title = "How we built a bridge", subtitle = "A week of engineering", plain = "We spent a week on bridges."),
    )
    private fun model() = JamModel({ store }, nameOf = { "Ben Android" }, source = { listOf(Samples.jam("j1", "Ben's classroom notes")) to posts }, savedStore = MemorySaved())
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun shot(name: String) {
        rule.waitForIdle(); Thread.sleep(700)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(File(context.filesDir, "shots").also { it.mkdirs() }, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Before fun setUp() {
        dir = File(context.cacheDir, "jamshots-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("jamshots-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun themed(font: Float, dark: Boolean, content: @androidx.compose.runtime.Composable () -> Unit) = rule.setContent {
        val d = androidx.compose.ui.platform.LocalDensity.current
        androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(d.density, font)) { LimeTheme(dark = dark) { content() } }
    }

    @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
    private fun filter(font: Float, dark: Boolean, name: String) {
        val m = model(); runBlocking { m.reload() }
        themed(font, dark) { JamFeedScreen(m) {} }
        rule.waitUntil(5_000) { count("jam-post-quick") > 0 }
        rule.onNodeWithTag("jam-filter-button", useUnmergedTree = true).performScrollTo().performClick()
        rule.waitUntil(5_000) { count("jam-filter-sheet") > 0 }
        rule.onNodeWithTag("jam-filter-coauthored", useUnmergedTree = true).performClick()
        shot(name)
    }
    @Test fun filterSheet() = filter(1f, false, "1-jam-filter-sheet")
    @Test fun filterSheetDarkLargestFont() = filter(2f, true, "2-jam-filter-sheet-dark-font-2")

    private fun reader(font: Float, dark: Boolean, openSheet: Boolean, name: String) {
        val m = model(); runBlocking { m.reload() }
        themed(font, dark) { JamReaderScreen(posts[2], m, myId = "me", chats = chats, onBack = {}) }
        rule.waitUntil(5_000) { count("jam-reader-report") > 0 }
        if (openSheet) { rule.onNodeWithTag("jam-reader-report", useUnmergedTree = true).performClick(); rule.waitUntil(5_000) { count("report-sheet") > 0 } }
        shot(name)
    }
    @Test fun readerWithReport() = reader(1f, false, false, "3-jam-reader-report")
    @Test fun reportSheet() = reader(1f, false, true, "4-jam-report-sheet")
    @Test fun reportSheetDarkLargestFont() = reader(2f, true, true, "5-jam-report-sheet-dark-font-2")
}
