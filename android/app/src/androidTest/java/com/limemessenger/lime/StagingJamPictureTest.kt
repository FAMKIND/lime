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
 * LIME-412b on STAGING (class 2): Ada creates her jam, **adds a jam picture** (the core's `set_jam_picture`: the Photo Picker is a system UI; the model path is the app's own `JamModel.setPicture`'s core call) and
 * posts; Ben (the partner running `jam-echo`) follows the jam, **fetches the PUBLIC page's picture** (the title and the picture are public by design, like a profile photo) and prints its size
 * (`jam: Ada's jam picture N bytes`, checked by connected.sh); the send progress ("Sending to N of M": `jam_send_progress`) is watched while the post goes out and ends at nothing pending once Ben has
 * answered; then Ada **reports Ben's comment** with the reason **"Test (LIME-412b)"** (the core returns no report id: the kind and the time are recorded in the test's output).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingJamPictureTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.jampicture.staging"
    private val dir = File(context.cacheDir, "staging-jampicture-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun click(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).performClick()
    private fun until(ms: Long, why: String, check: () -> Boolean) { try { rule.waitUntil(ms) { check() } } catch (e: Throwable) { throw AssertionError("timed out: $why", e) } }
    private fun openFeed() { if (count("jam-feed") == 0) { until(30_000, "the jam tab") { count("tab-jam") > 0 }; click("tab-jam") }; until(30_000, "the feed") { count("jam-feed") > 0 } }

    @Test fun adaAddsAJamPictureBenFetchesItSendProgressSettlesAndAdaReportsBensComment() {
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

        // The jam's picture: a JPEG made here, set through the core as the app's model does; the Your jam page then shows it.
        val jpeg = com.limemessenger.lime.ui.jam.jamPictureJpeg(android.graphics.Bitmap.createBitmap(800, 420, android.graphics.Bitmap.Config.ARGB_8888).also { android.graphics.Canvas(it).drawColor(0xFF09A950.toInt()) })!!
        // The server refuses a picture for a page it has not got yet: the app delivers the new jam within seconds, so ask again (bounded) until it is accepted.
        var set = false
        var lastError: Throwable? = null
        val until = System.currentTimeMillis() + 90_000
        while (!set && System.currentTimeMillis() < until) {
            try { core.setJamPicture(session.transport!!, kotlinx.coroutines.runBlocking { session.accessToken() }, jam.jamId, jpeg); set = true } catch (e: Exception) { lastError = e; Thread.sleep(3_000) }
        }
        assertTrue("the picture was never accepted: $lastError", set)
        assertTrue("the core holds the picture it just set", core.jamPicture(jam.jamId)?.size == jpeg.size)
        click("jam-yours-back"); openFeed(); click("jam-yours-open")
        until(30_000, "the picture on the page") { count("jam-picture") > 0 && rule.onNodeWithTag("jam-picture", useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString() == "Your jam\u2019s picture" }

        // A post; watch the send progress while it goes out to Ben (who follows once he sees the page).
        click("jam-write-post")
        until(10_000, "the post sheet") { count("jam-compose-body") > 0 }
        rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextInput("A post with a picture on the jam")
        click("jam-compose-next")
        until(10_000, "step 2") { count("jam-post") > 0 }
        click("jam-post")
        until(60_000, "the post to go out") { count("jam-write-article") > 0 && core.listJamPosts(jam.jamId).size == 1 }
        val quick = core.listJamPosts(jam.jamId).single()
        var maxTotal = 0u
        var sawLine = false
        var commentSeen = false
        // (waitUntil, not a sleep: it is what lets the app's own sync run, so Ada's phone answers Ben's request to follow and then sends him the post.)
        try {
            rule.waitUntil(300_000) {
                val p = core.jamSendProgress(jam.jamId)
                if (p.total > maxTotal) maxTotal = p.total
                if (count("jam-send-progress") > 0) sawLine = true
                commentSeen = core.listJamComments(quick.postId).any { it.text.startsWith("Ben here: nice") }
                commentSeen
            }
        } catch (e: Throwable) { /* reported just below, with what was seen */ }
        assertTrue("Ben's comment on the post never came (max total seen $maxTotal)", commentSeen)
        until(120_000, "nothing left to send") { core.jamSendProgress(jam.jamId).pending == 0u }
        println("LIME-412b: send progress: largest total seen $maxTotal (0 = it went out between two looks), the line was on screen: $sawLine")

        // Report Ben's comment from the reader of the post (the same sheet as a message's), with the reason "Test (LIME-412b)".
        val benComment = core.listJamComments(quick.postId).first { it.text.startsWith("Ben here: nice") }
        click("jam-yours-back"); openFeed()
        until(30_000, "the post in the feed") { count("jam-post-${quick.postId}") > 0 }
        click("jam-post-${quick.postId}")
        until(30_000, "Ben's comment with its Report") { count("jam-comment-report-${benComment.commentId}") > 0 }
        assertEquals("my own comment would have no Report; his has", 1, count("jam-comment-report-${benComment.commentId}"))
        click("jam-comment-report-${benComment.commentId}")
        until(10_000, "the report sheet") { count("report-sheet") > 0 }
        click("report-reason-other")
        rule.onNodeWithTag("report-note", useUnmergedTree = true).performTextInput("Test (LIME-412b)")
        click("report-send")
        until(60_000, "the thanks") { count("report-thanks") > 0 }
        println("LIME-412b: REPORT SENT kind=comment comment=${benComment.commentId} post=${quick.postId} author=Ben at=${java.time.Instant.now()} reason=\"Test (LIME-412b)\" (the core returns no id)")
        click("report-done")
    }
}
