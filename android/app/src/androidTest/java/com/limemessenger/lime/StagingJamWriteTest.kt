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
import androidx.compose.ui.test.performTextClearance
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
import uniffi.lime_core.HeaderPair
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * LIME-312 on STAGING: Ada creates her jam, writes a post and an article (with the toolbar), Ben (the partner running `jam-echo`) follows the jam, receives both and comments;
 * Ada edits the post, deletes the article, sees Ben in her subscribers, removes him and ends the jam.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingJamWriteTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.jamwrite.staging"
    private val dir = File(context.cacheDir, "staging-jamwrite-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun click(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).performClick()
    private fun until(ms: Long, why: String, check: () -> Boolean) { try { rule.waitUntil(ms) { check() } } catch (e: Throwable) { throw AssertionError("timed out: $why", e) } }
    private fun openFeed() { if (count("jam-feed") == 0) { until(30_000, "the jam tab") { count("tab-jam") > 0 }; click("tab-jam") }; until(30_000, "the feed") { count("jam-feed") > 0 } }

    @Test fun adaWritesPostsAndArticlesAndBenFollowsThem() {
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
        val core = session.store!!

        // Ada writes to Ben first, as a teacher meets another (Ben's phone accepts it): a subscription travels like a message, so each needs the other's key.
        core.startDm(benId, "Ben Android")
        core.sendTextIdentified(session.transport!!, kotlinx.coroutines.runBlocking { session.accessToken() }, benId, "Hello Ben")

        // Pages left by earlier runs (their phones are gone) would be served first: end them (Ada's own test jams).
        fun page(json: String): String = session.transport!!.request(
            "POST", "/functions/v1/jam-page", listOf(HeaderPair("content-type", "application/json"), HeaderPair("authorization", "Bearer " + kotlinx.coroutines.runBlocking { session.accessToken() })), json.toByteArray(),
        ).body.decodeToString()
        Regex(""""jam_id":"([0-9a-f-]{36})"""").findAll(page("""{"action":"by_writer","writer_id":"${session.userId}"}""")).map { it.groupValues[1] }.toSet().forEach { page("""{"action":"end","jam_id":"$it"}""") }

        // Create the jam.
        openFeed()
        click("jam-yours-open")
        until(10_000, "the create form") { count("jam-create") > 0 }
        rule.onNodeWithTag("jam-create-title", useUnmergedTree = true).performTextInput("Ada's lab notes")
        rule.onNodeWithTag("jam-create-about", useUnmergedTree = true).performTextInput("Experiments from Ada's class")
        rule.onNodeWithTag("jam-create-topics", useUnmergedTree = true).performTextInput("science, grade 5")
        click("jam-create")
        until(30_000, "the jam to exist") { count("jam-write-post") > 0 }
        val jam = core.listMyJams().single { !it.ended }
        assertEquals(listOf("science", "grade 5"), jam.topics)

        // A post, then an article with the toolbar's bold.
        click("jam-write-post")
        until(10_000, "the post sheet") { count("jam-compose-body") > 0 }
        rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextInput("First post from Ada's phone")
        click("jam-compose-next")
        until(10_000, "step 2") { count("jam-post") > 0 }
        click("jam-post")
        until(60_000, "the post to go out") { count("jam-write-article") > 0 && core.listJamPosts(jam.jamId).size == 1 }
        click("jam-write-article")
        until(10_000, "the article sheet") { count("jam-compose-title") > 0 }
        rule.onNodeWithTag("jam-compose-title", useUnmergedTree = true).performTextInput("How we built a bridge")
        rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextInput("Bridges are strong.")
        click("jam-tool-bold")
        click("jam-compose-next")
        until(10_000, "step 2 of the article") { count("jam-post") > 0 }
        click("jam-post")
        until(60_000, "the article to go out") { core.listJamPosts(jam.jamId).size == 2 }
        val posts = core.listJamPosts(jam.jamId)
        val quick = posts.first { it.kind == "quick" }
        val article = posts.first { it.kind == "article" }
        assertTrue(article.markdown, article.markdown.contains("**bold**"))
        assertEquals(listOf("free", "subscribers"), listOf(quick.tier, quick.audience))

        // Ben follows the jam (the partner), receives both and comments on each; Ada sees him in her subscribers.
        try { rule.waitUntil(240_000) { count("jam-subscriber-$benId") > 0 } } catch (e: Throwable) {
            throw AssertionError("Ben never appeared in the subscribers; core says ${runCatching { core.listJamSubscribers(jam.jamId).map { it.userId.take(8) + ':' + it.status } }.getOrNull()}; my jams ${core.listMyJams().map { it.jamId.take(8) + " subs=" + it.subscriberCount }}; Ben is ${benId.take(8)}", e)
        }
        until(240_000, "Ben's comment on the post (send progress ${runCatching { core.jamSendProgress(jam.jamId) }})") { core.listJamComments(quick.postId).any { it.text.startsWith("Ben here: nice") } }

        // Edit the post from its page: the new words reach Ben (the partner prints "edited").
        click("jam-yours-back")
        openFeed()
        until(30_000, "the post in the feed") { count("jam-post-${quick.postId}") > 0 }
        click("jam-post-${quick.postId}")
        until(30_000, "the reader") { count("jam-reader-edit") > 0 }
        click("jam-reader-edit")
        until(10_000, "the edit sheet") { count("jam-compose-body") > 0 }
        rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextClearance()
        rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextInput("First post from Ada's phone (edited)")
        click("jam-compose-next")
        until(10_000, "step 2 of the edit") { count("jam-post") > 0 }
        click("jam-post")
        until(60_000, "the edit to be saved") { core.listJamPosts(jam.jamId).first { it.postId == quick.postId }.markdown.endsWith("(edited)") }
        Thread.sleep(10_000)   // (give Ben's phone time to see it before the delete)

        // Delete the article from its page.
        openFeed()
        until(30_000, "the article in the feed") { count("jam-post-${article.postId}") > 0 }
        click("jam-post-${article.postId}")
        until(30_000, "the article's page") { count("jam-reader-delete") > 0 }
        click("jam-reader-delete")
        until(10_000, "the confirmation") { count("jam-delete-confirm") > 0 }
        click("jam-delete-confirm")
        until(60_000, "the article to be gone") { core.listJamPosts(jam.jamId).none { it.postId == article.postId && it.state != "gone" } }
        Thread.sleep(15_000)   // (give Ben's phone time to see the delete before he is removed)

        // Remove Ben, then end the jam.
        openFeed()
        click("jam-yours-open")
        until(30_000, "Ben in the list again") { count("jam-sub-remove-$benId") > 0 }
        click("jam-sub-remove-$benId")
        until(10_000, "the confirmation") { count("jam-sub-remove-confirm") > 0 }
        click("jam-sub-remove-confirm")
        until(60_000, "Ben to leave the list") { count("jam-subscriber-$benId") == 0 }
        click("jam-end")
        until(10_000, "the confirmation") { count("jam-end-confirm") > 0 }
        click("jam-end-confirm")
        until(60_000, "the jam to end") { count("jam-create") > 0 }
    }
}
