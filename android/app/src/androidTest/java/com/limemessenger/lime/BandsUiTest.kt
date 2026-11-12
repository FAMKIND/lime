package com.limemessenger.lime

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
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

/** LIME-315a: my jams as a list (my own space first, then bands), the switcher only when there is more than one, Create a band, and "Post as". Made-up jams (no network). */
@RunWith(AndroidJUnit4::class)
class BandsUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var drafts: JamDrafts

    @Before fun setUp() { dir = File(context.cacheDir, "bands-${System.nanoTime()}").also { it.mkdirs() }; drafts = JamDrafts(dir) }
    @After fun tearDown() { dir.deleteRecursively() }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private val own = Samples.jam("own", "Ada's notes", mine = true, created = 1_000)
    private val band = Samples.jam("band", "The Staff Room", mine = true, created = 2_000)
    private val followed = Samples.jam("other", "Ben's notes", mine = false, created = 500)
    private fun model(vararg jams: uniffi.lime_core.JamInfo) = JamModel({ null }, { "Ben" }, source = { jams.toList() to emptyList() }).also { runBlocking { it.reload() } }

    @Test fun oneJamIsUnchangedNoSwitcherNoPostAndMineIsThatJam() {
        val m = model(own, followed)
        assertEquals(listOf("own"), m.myJams.map { it.jamId })
        assertEquals("own", m.mine()?.jamId)
        rule.setContent { LimeTheme { YourJamScreen(m, drafts, onBack = {}, onCompose = {}) } }
        rule.waitUntil(5_000) { count("jam-yours-title") > 0 }
        assertEquals("no switcher with one jam", 0, count("jam-switcher"))
    }

    @Test fun myOwnSpaceComesFirstThenBandsAndAFollowedJamIsNotMine() {
        val m = model(band, followed, own)
        assertEquals("own space first (the oldest), then the band", listOf("own", "band"), m.myJams.map { it.jamId })
        assertTrue(m.isBand(band)); assertTrue(!m.isBand(own))
        assertEquals("the default choice is my own space", "own", m.mine()?.jamId)
    }

    @Test fun withTwoJamsTheSwitcherShowsTheCurrentOneAndChoosingABandMakesTheYourJamPageItsOwn() {
        val m = model(own, band)
        rule.setContent { LimeTheme { YourJamScreen(m, drafts, onBack = {}, onCompose = {}) } }
        rule.waitUntil(5_000) { count("jam-switcher") > 0 }
        assertEquals("Ada's notes", titleText())
        rule.onNodeWithTag("jam-switcher", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("jam-switcher-sheet") > 0 }
        rule.onNodeWithTag("jam-switch-band", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { titleText() == "The Staff Room" }
        assertEquals("the choice is kept for the session", "band", m.mine()?.jamId)
    }

    private fun titleText() = rule.onAllNodes(hasTestTag("jam-yours-title"), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull()
        ?.config?.getOrNull(androidx.compose.ui.semantics.SemanticsProperties.Text)?.joinToString { it.text }.orEmpty()

    private fun androidx.compose.ui.semantics.SemanticsConfiguration.getOrNull(key: androidx.compose.ui.semantics.SemanticsPropertyKey<List<androidx.compose.ui.text.AnnotatedString>>) =
        if (key in this) this[key] else null

    @Test fun createBandNeedsANameSaysThePublicNoteAndAFailureSaysSo() {
        val m = model(own)
        rule.setContent { LimeTheme { CreateBandScreen(m, onClose = {}) } }
        rule.waitUntil(5_000) { count("band-name") > 0 }
        assertTrue("the picture, name and about are public: said once", count("band-public-note") == 1)
        assertTrue("the band explainer is there", count("band-explainer") == 1)
        assertTrue("Create is off without a name", androidx.compose.ui.semantics.SemanticsProperties.Disabled in rule.onNodeWithTag("band-make", useUnmergedTree = true).fetchSemanticsNode().config)
        rule.onNodeWithTag("band-name", useUnmergedTree = true).performTextInput("The Staff Room")
        rule.waitUntil(5_000) { androidx.compose.ui.semantics.SemanticsProperties.Disabled !in rule.onNodeWithTag("band-make", useUnmergedTree = true).fetchSemanticsNode().config }
        rule.onNodeWithTag("band-make", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-failed") > 0 }   // no account in this store: the core refuses, the screen says so (never a crash)
    }

    @Test fun postAsOffersMyOwnSpaceAndEachBandAndPublishesToTheChosenOneWithItsDisplay() {
        val m = model(own, band)
        val published = mutableListOf<Pair<String, String>>()
        m.publishHook = { jamId, displayAs -> published += jamId to displayAs; true }
        var done = false
        rule.setContent { LimeTheme { JamComposeScreen(m, drafts, ComposeRoute("quick")) { done = true } } }
        rule.waitUntil(5_000) { count("jam-compose-body") > 0 }
        rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextInput("A post for the band")
        rule.onNodeWithTag("jam-compose-next", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("jam-postas-band") > 0 }
        assertEquals(1, count("jam-postas-own"))
        rule.onNodeWithTag("jam-postas-band", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("jam-post", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { done }
        assertEquals("to the band, shown as the band", listOf("band" to "jam"), published)
    }

    @Test fun postAsIsHiddenWithOneJamAndMyOwnSpaceIsPublishedAsMe() {
        val m = model(own)
        val published = mutableListOf<Pair<String, String>>()
        m.publishHook = { jamId, displayAs -> published += jamId to displayAs; true }
        var done = false
        rule.setContent { LimeTheme { JamComposeScreen(m, drafts, ComposeRoute("quick")) { done = true } } }
        rule.waitUntil(5_000) { count("jam-compose-body") > 0 }
        rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextInput("A post of mine")
        rule.onNodeWithTag("jam-compose-next", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("jam-post") > 0 }
        assertEquals("no Post as with one place to post", 0, count("jam-postas-own"))
        rule.onNodeWithTag("jam-post", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { done }
        assertEquals(listOf("own" to "person"), published)
    }
}
