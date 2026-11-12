package com.limemessenger.lime

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.Samples
import com.limemessenger.lime.jam.JamDrafts
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.ui.jam.ComposeRoute
import com.limemessenger.lime.ui.jam.JamComposeScreen
import com.limemessenger.lime.ui.jam.YourJamScreen
import com.limemessenger.lime.ui.jam.CreateBandScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** NOT a test: the LIME-315a screenshots (the switcher, Create a band, Post as; light, dark, 200% font) into files/shots (`tools/shots-315a.sh`). `@Staging` only so the plain pass skips it. */
@Staging
@RunWith(AndroidJUnit4::class)
class BandShotsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var drafts: JamDrafts
    @Before fun setUp() { dir = File(context.cacheDir, "bandshots-${System.nanoTime()}").also { it.mkdirs() }; drafts = JamDrafts(dir) }
    @After fun tearDown() { dir.deleteRecursively() }
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private val own = Samples.jam("own", "Ada's notes", mine = true, created = 1_000)
    private val band = Samples.jam("band", "The Staff Room", mine = true, created = 2_000)
    private fun model() = JamModel({ null }, { "Ben" }, source = { listOf(own, band) to emptyList() }).also { runBlocking { it.reload() } }
    private fun shot(name: String) {
        rule.waitForIdle(); Thread.sleep(700)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(File(context.filesDir, "shots").also { it.mkdirs() }, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun themed(font: Float, dark: Boolean, content: @androidx.compose.runtime.Composable () -> Unit) = rule.setContent {
        val d = androidx.compose.ui.platform.LocalDensity.current
        androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(d.density, font)) { LimeTheme(dark = dark) { content() } }
    }

    private fun switcher(font: Float, dark: Boolean, open: Boolean, name: String) {
        val m = model()
        themed(font, dark) { YourJamScreen(m, drafts, onBack = {}, onCompose = {}) }
        rule.waitUntil(5_000) { count("jam-switcher") > 0 }
        if (open) { rule.onNodeWithTag("jam-switcher", useUnmergedTree = true).performClick(); rule.waitUntil(5_000) { count("jam-switcher-sheet") > 0 } }
        shot(name)
    }
    @Test fun yourJamWithSwitcher() = switcher(1f, false, false, "1-your-jam-switcher")
    @Test fun switcherSheet() = switcher(1f, false, true, "2-switcher-sheet")
    @Test fun switcherSheetDarkLargestFont() = switcher(2f, true, true, "3-switcher-sheet-dark-font-2")

    private fun create(font: Float, dark: Boolean, name: String) {
        val m = model()
        themed(font, dark) { CreateBandScreen(m, onClose = {}) }
        rule.waitUntil(5_000) { count("band-name") > 0 }
        rule.onNodeWithTag("band-name", useUnmergedTree = true).performTextInput("The Staff Room")
        shot(name)
    }
    @Test fun createBand() = create(1f, false, "4-create-band")
    @Test fun createBandDarkLargestFont() = create(2f, true, "5-create-band-dark-font-2")

    private fun postAs(font: Float, dark: Boolean, name: String) {
        val m = model()
        themed(font, dark) { JamComposeScreen(m, drafts, ComposeRoute("quick")) {} }
        rule.waitUntil(5_000) { count("jam-compose-body") > 0 }
        rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextInput("A post for the band")
        rule.onNodeWithTag("jam-compose-next", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("jam-postas-band") > 0 }
        rule.onNodeWithTag("jam-postas-band", useUnmergedTree = true).performClick()
        shot(name)
    }
    @Test fun postAsBand() = postAs(1f, false, "6-post-as")
    @Test fun postAsBandDarkLargestFont() = postAs(2f, true, "7-post-as-dark-font-2")
}
