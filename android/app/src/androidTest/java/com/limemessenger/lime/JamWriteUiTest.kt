package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.jam.JamDrafts
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.ui.jam.ComposeRoute
import com.limemessenger.lime.ui.jam.JamComposeScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.OutgoingAttachment

/** LIME-312 without the network: the drafts kept on the phone, and the two steps of writing an article. */
@RunWith(AndroidJUnit4::class)
class JamWriteUiTest {
    @get:Rule val rule = createComposeRule()
    private val dir = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "jam-drafts-${System.nanoTime()}")
    private val drafts = JamDrafts(dir)

    @After fun tearDown() { dir.deleteRecursively() }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size

    @Test fun aDraftKeepsItsWordsAndItsPhotosWithTheirDescriptions() {
        val photo = OutgoingAttachment(ByteArray(300) { 7 }, "a.jpg", "image/jpeg", 40u, 30u, null, ByteArray(10) { 1 }, ByteArray(0), "A green bridge of straws")
        assertTrue(drafts.save("d1", "quick", "", "", "First line\nsecond line", listOf(photo), now = 1_000))
        assertTrue(drafts.save("d2", "article", "Bridges", "A week", "Body", emptyList(), now = 2_000))
        assertEquals(listOf("d2", "d1"), drafts.list().map { it.id })
        val one = drafts.read("d1")!!
        assertEquals("First line", one.headline)
        assertEquals("Bridges", drafts.read("d2")!!.headline)
        val back = drafts.photos(one).single()
        assertEquals(300, back.bytes.size); assertEquals("A green bridge of straws", back.alt); assertEquals(10, back.thumb.size)
        drafts.delete("d1")
        assertEquals(listOf("d2"), drafts.list().map { it.id })
        assertEquals(null, JamDrafts(File(dir, "nothing")).read("x"))
    }

    @Test fun anArticleIsWrittenWithTheToolbarThenReviewedAndAFailedPublishKeepsTheDraft() {
        val model = JamModel({ null }, { null })
        var done = false
        rule.setContent { LimeTheme { JamComposeScreen(model, drafts, ComposeRoute("article")) { done = true } } }
        rule.onNodeWithTag("jam-compose-title").performTextInput("Bridges")
        rule.onNodeWithTag("jam-compose-body").performTextInput("We built bridges.")
        rule.onNodeWithTag("jam-tool-bold").performClick()
        rule.waitForIdle()
        val text = rule.onNodeWithTag("jam-compose-body").fetchSemanticsNode().config[SemanticsProperties.EditableText].text
        assertTrue(text, text.contains("**bold**"))
        rule.onNodeWithTag("jam-compose-next").performClick()
        rule.waitUntil(5_000) { count("jam-before-audience") > 0 }
        // Step 2 reads as one stop and says who can read it.
        assertEquals("Audience, Subscribers", rule.onNodeWithTag("jam-before-audience").fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString())
        rule.onNodeWithTag("jam-post").performClick()
        rule.waitUntil(5_000) { count("jam-before-problem") > 0 }
        // Back to writing loses nothing; leaving keeps a draft.
        rule.onNodeWithTag("jam-compose-back").performClick()
        rule.waitUntil(5_000) { count("jam-compose-body") > 0 }
        rule.onNodeWithTag("jam-compose-back").performClick()
        rule.waitUntil(5_000) { done }
        val kept = drafts.list().single()
        assertEquals("Bridges", kept.title); assertEquals("article", kept.kind); assertTrue(kept.words.contains("**bold**"))
    }
}
