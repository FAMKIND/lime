package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.limemessenger.lime.chats.Samples
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.jam.SavedPosts
import com.limemessenger.lime.ui.jam.JamFeedScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** LIME-311: the jam feed's segments (the core's rules), the Saved bookmarks and the cards' words, against a made-up feed. */
@RunWith(AndroidJUnit4::class)
class JamSegmentsUiTest {
    @get:Rule val rule = createComposeRule()

    private class MemorySaved : SavedPosts {
        private var ids = emptySet<String>()
        override fun all() = ids
        override fun set(postId: String, on: Boolean) { ids = if (on) ids + postId else ids - postId }
    }

    private val posts = listOf(
        Samples.jamPost("quick", "j1", at = 3_000, plain = "A quick post about magnets"),
        Samples.jamPost("article", "j1", at = 2_000, kind = "article", title = "How we built a bridge", subtitle = "A week of engineering", plain = "We spent a week on bridges."),
        Samples.jamPost("record", "j1", at = 1_000, kind = "record", title = "Ben's quick physics tip", plain = ""),
    )

    private fun model() = JamModel({ null }, nameOf = { "Ben Android" }, source = { listOf(Samples.jam("j1", "Ben's classroom notes")) to posts }, savedStore = MemorySaved())
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun ids() = posts.map { it.postId }.filter { count("jam-post-$it") > 0 }

    @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
    @Test fun theSegmentsNarrowTheFeedByKindAndSavedKeepsTheBookmarks() {
        val m = model()
        runBlocking { m.reload() }
        rule.setContent { LimeTheme { JamFeedScreen(m) {} } }
        rule.waitUntil(5_000) { count("jam-post-quick") > 0 }
        assertEquals(listOf("quick", "article", "record"), ids())
        rule.onNodeWithTag("jam-segment-Posts").performClick(); rule.waitForIdle()
        assertEquals(listOf("quick"), ids())
        rule.onNodeWithTag("jam-segment-Articles").performClick(); rule.waitForIdle()
        assertEquals(listOf("article"), ids())
        rule.onNodeWithTag("jam-segment-Podcasts").performClick(); rule.waitForIdle()
        assertEquals(listOf("record"), ids())
        // The segment pills say "selected" to TalkBack.
        assertTrue(rule.onNodeWithTag("jam-segment-Podcasts").fetchSemanticsNode().config[SemanticsProperties.Selected])
        // Bookmark one post; Saved shows only it; nothing saved says so.
        rule.onNodeWithTag("jam-segment-All").performClick(); rule.waitForIdle()
        rule.onNodeWithTag("jam-segment-saved").performClick(); rule.waitForIdle()
        assertTrue(count("jam-feed-none") > 0)
        rule.onNodeWithTag("jam-segment-All").performClick(); rule.waitForIdle()
        rule.onNodeWithTag("jam-save-article").performClick(); rule.waitForIdle()
        rule.onNodeWithTag("jam-segment-saved").performClick(); rule.waitForIdle()
        assertEquals(listOf("article"), ids())
    }

    @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
    @Test fun aCardIsOneTalkBackStopWithWhoWhatAndWhen() {
        val m = model()
        runBlocking { m.reload() }
        rule.setContent { LimeTheme { JamFeedScreen(m) {} } }
        rule.waitUntil(5_000) { count("jam-post-article") > 0 }
        val words = rule.onNodeWithTag("jam-post-article").fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertTrue(words, words.startsWith("Ben Android, ") && words.contains("How we built a bridge") && words.contains("A week of engineering"))
    }
}
