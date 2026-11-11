package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.AccountSession.Phase
import com.limemessenger.lime.auth.LiveAuthService
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.net.BackendConfig
import com.limemessenger.lime.net.HttpTransport
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.Root
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * LIME-311 on STAGING: Ada subscribes to Ben's jam from his profile, reads his three posts (a quick post, an article with a captioned photo, a podcast), likes the
 * article, comments on it and sees Ben's reply (the partner running `jam-publish` then `jam-echo`), and the Podcasts segment narrows the feed to one card.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingJamTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.jam.staging"
    private val dir = File(context.cacheDir, "staging-jam-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun text(tag: String): String = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString("") { it.text }
    private fun cards() = rule.onAllNodes(SemanticsMatcher("is a jam card") { it.config.contains(SemanticsProperties.TestTag) && it.config[SemanticsProperties.TestTag].startsWith("jam-post-") }, useUnmergedTree = true).fetchSemanticsNodes()
    private fun described(words: String) = rule.onAllNodes(SemanticsMatcher("described $words") { it.config.contains(SemanticsProperties.ContentDescription) && it.config[SemanticsProperties.ContentDescription].any { d -> d == words } }, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    @Test fun adaSubscribesReadsLikesAndCommentsOnBensJam() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val benId = JSONObject(pushed.readText()).getJSONObject("accounts").getJSONObject("b").getString("user_id")
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets)
        rule.setContent { LimeTheme { Root(session) } }

        rule.waitUntil(15_000) { count("use-test-account") > 0 }
        rule.onNodeWithTag("use-test-account").performClick()
        rule.onNodeWithTag("test-account-ada_android").performClick()
        try {
            rule.waitUntil(60_000) { session.phase == Phase.SignedIn && (session.deviceRegistered || session.problem != null) }
        } catch (e: Throwable) {
            throw AssertionError("sign-in stalled: phase=${session.phase} registered=${session.deviceRegistered} problem=${session.problem}", e)
        }
        assertEquals("registration problem: ${session.problem}", true, session.deviceRegistered)

        // Ben's profile, from the chat with him: his jam and a Subscribe button.
        val core = session.store!!
        val dm = "dm:$benId"
        core.startDm(benId, "Ben Android")
        core.sendTextIdentified(session.transport!!, kotlinx.coroutines.runBlocking { session.accessToken() }, benId, "Hello Ben")
        rule.waitUntil(120_000) { count("conversation-row-$dm") > 0 }
        rule.onNodeWithTag("conversation-row-$dm").performClick()
        rule.waitUntil(30_000) { count("chat-header") > 0 }
        rule.onNodeWithTag("chat-header", useUnmergedTree = true).performClick()
        rule.waitUntil(60_000) { count("profile-jam-subscribe") > 0 }
        assertEquals("Ben's classroom notes", text("profile-jam-title"))
        // (A fresh phone of Ada's account may already follow Ben's jam from an earlier run: tap Subscribe only when it is offered.)
        Thread.sleep(3_000)
        if (rule.onAllNodesWithText("Subscribe", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()) rule.onNodeWithTag("profile-jam-subscribe", useUnmergedTree = true).performClick()
        try { rule.waitUntil(180_000) { rule.onAllNodesWithText("Subscribed", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() } } catch (e: Throwable) {
            throw AssertionError("never Subscribed; the button says '${runCatching { text("profile-jam-subscribe") }.getOrNull()}'; jams=${core.listJamSubscriptions().map { it.jamId.take(8) + ":" + it.status }}", e)
        }
        rule.onNodeWithTag("profile-back").performClick()
        rule.waitUntil(10_000) { count("chat-back") > 0 }
        rule.onNodeWithTag("chat-back", useUnmergedTree = true).performClick()

        // The jam tab: his three posts arrive through the welcome and the archive.
        rule.waitUntil(30_000) { count("tab-jam") > 0 }
        rule.onNodeWithTag("tab-jam", useUnmergedTree = true).performClick()
        try { rule.waitUntil(240_000) { cards().size >= 3 } } catch (e: Throwable) { throw AssertionError("expected 3 posts, saw ${cards().size}", e) }

        // The Podcasts segment narrows it to the one podcast.
        rule.onNodeWithTag("jam-segment-Podcasts", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { cards().size == 1 }
        rule.onNodeWithTag("jam-segment-All", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { cards().size == 3 }
        rule.onNodeWithTag("jam-segment-Articles", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { cards().size == 1 }

        // The article: its photo is read by its description; like it; comment; Ben answers.
        rule.onAllNodes(SemanticsMatcher("a card") { it.config.contains(SemanticsProperties.TestTag) && it.config[SemanticsProperties.TestTag].startsWith("jam-post-") }, useUnmergedTree = true).onFirst().performClick()
        rule.waitUntil(30_000) { count("jam-reader") > 0 }
        assertEquals("How we built a bridge", text("jam-reader-title"))
        try { rule.waitUntil(60_000) { described("Students testing the bridge") } } catch (e: Throwable) { throw AssertionError("the photo is not read by its caption", e) }
        val like = rule.onAllNodes(SemanticsMatcher("a like") { it.config.contains(SemanticsProperties.TestTag) && it.config[SemanticsProperties.TestTag].startsWith("jam-like-") }, useUnmergedTree = true).onFirst()
        like.performClick()
        // My heart is filled at once (the count of likes waits for the writer's phone to publish it).
        try { rule.waitUntil(30_000) { like.fetchSemanticsNode().config[SemanticsProperties.Selected] } } catch (e: Throwable) { throw AssertionError("the heart did not fill", e) }
        rule.onNodeWithTag("jam-comment-field", useUnmergedTree = true).performTextInput("Great bridge!")
        rule.onNodeWithTag("jam-comment-send", useUnmergedTree = true).performClick()
        try { rule.waitUntil(240_000) { rule.onAllNodesWithText("Ben here: thanks!", substring = true, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() } } catch (e: Throwable) { throw AssertionError("Ben's reply never showed; Ada follows ${core.listJamSubscriptions().map { it.jamId.take(8) + ":" + it.status }}; comments=${core.listJamComments(core.listJamPosts(core.listJamSubscriptions().first().jamId).first { it.kind == "article" }.postId).map { it.text.take(12) + "(" + it.state + ")" }}", e) }
        assertTrue(rule.onAllNodesWithText("Great bridge!", substring = true, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
    }
}
