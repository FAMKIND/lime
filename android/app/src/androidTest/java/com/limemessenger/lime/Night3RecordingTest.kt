package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * NOT a test of anything: the scripted walk-through of night 3 that `tools/record-night3.sh` films: subscribe to Ben's jam from his profile, read, like and comment, write
 * a post and an article, the GIF panel and a sticker, the Report sheet and Settings > Blocked. REAL app session; needs the pushed accounts and Ben running `jam-publish` then
 * `jam-echo`. Every step after sign-in is best-effort (a film never fails the take). Screenshots go to files/shots (the script pulls them).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class Night3RecordingTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val shots get() = File(context.filesDir, "shots").also { it.mkdirs() }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun pause(ms: Long = 1800) = Thread.sleep(ms)
    private fun shot(name: String) {
        rule.waitForIdle()
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(shots, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun tryIt(block: () -> Unit) { try { block() } catch (e: Throwable) { /* a best-effort step of a film */ } }
    private fun tap(tag: String, wait: Long = 20_000) { rule.waitUntil(wait) { count(tag) > 0 }; pause(700); rule.onNodeWithTag(tag, useUnmergedTree = true).performClick() }
    private fun back() = rule.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }

    @Test fun walkThrough() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val benId = JSONObject(pushed.readText()).getJSONObject("accounts").getJSONObject("b").getString("user_id")
        val session = (context.applicationContext as LimeApp).session

        rule.waitUntil(15_000) { count("welcome-continue") > 0 || count("my-avatar") > 0 }
        if (count("welcome-continue") > 0) {
            rule.onNodeWithTag("use-test-account").performClick(); pause(900)
            rule.onNodeWithTag("test-account-ada_android").performClick()
        }
        rule.waitUntil(60_000) { session.deviceRegistered }
        val core = session.store!!
        val dm = "dm:$benId"
        core.startDm(benId, "Ben Android")
        runBlocking { core.sendTextIdentified(session.transport!!, session.accessToken(), benId, "Hello Ben") }
        rule.waitUntil(120_000) { count("conversation-row-$dm") > 0 }
        pause(); shot("1-list")

        // Subscribe to Ben's jam from his profile, then read his posts.
        tryIt {
            tap("conversation-row-$dm"); tap("chat-header")
            rule.waitUntil(60_000) { count("profile-jam-subscribe") > 0 }; pause(); shot("2-profile-jam")
            if (rule.onAllNodes(hasTestTag("profile-jam-subscribe"), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()) tap("profile-jam-subscribe")
            pause(5000)
            tap("profile-back"); tap("chat-back")
            tap("tab-jam"); rule.waitUntil(240_000) { rule.onAllNodes(SemanticsMatcher("a post") { it.config.contains(SemanticsProperties.TestTag) && it.config[SemanticsProperties.TestTag].startsWith("jam-post-") }, useUnmergedTree = true).fetchSemanticsNodes().size >= 3 }
            pause(); shot("3-jam-feed")
        }
        tryIt {
            tap("jam-segment-Articles"); pause()
            rule.onAllNodes(SemanticsMatcher("a post") { it.config.contains(SemanticsProperties.TestTag) && it.config[SemanticsProperties.TestTag].startsWith("jam-post-") }, useUnmergedTree = true).onFirst().performClick()
            rule.waitUntil(20_000) { count("jam-reader") > 0 }; pause(2500); shot("4-reader")
            rule.onAllNodes(SemanticsMatcher("a like") { it.config.contains(SemanticsProperties.TestTag) && it.config[SemanticsProperties.TestTag].startsWith("jam-like-") }, useUnmergedTree = true).onFirst().performClick(); pause(1500)
            rule.onNodeWithTag("jam-comment-field", useUnmergedTree = true).performTextInput("Great bridge!"); pause(800)
            tap("jam-comment-send"); pause(6000)
            shot("5-comment")
            back(); pause(800)
        }

        // Write a post and an article of my own.
        tryIt {
            tap("jam-yours-open"); tap("jam-create-title", 10_000)
            rule.onNodeWithTag("jam-create-title", useUnmergedTree = true).performTextInput("Ada's lab notes")
            rule.onNodeWithTag("jam-create-about", useUnmergedTree = true).performTextInput("Experiments from Ada's class"); pause(800)
            tap("jam-create"); tap("jam-write-post", 30_000)
            rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextInput("First post from Ada's phone"); pause(900)
            tap("jam-compose-next"); pause(900); shot("6-before-you-post"); tap("jam-post"); pause(3000)
            tap("jam-write-article", 30_000)
            rule.onNodeWithTag("jam-compose-title", useUnmergedTree = true).performTextInput("How we built a bridge")
            rule.onNodeWithTag("jam-compose-body", useUnmergedTree = true).performTextInput("Bridges are strong."); pause(700)
            tap("jam-tool-bold"); pause(900); shot("7-article-toolbar")
            tap("jam-compose-next"); tap("jam-post"); pause(3000)
            back(); pause(1000)
        }

        // The GIF panel and a sticker; the Report sheet (cancelled: a film sends nothing); Settings > Blocked.
        tryIt {
            tap("tab-link"); tap("conversation-row-$dm"); tap("attach-gif"); pause(1800); shot("8-gif-panel")
            tap("gif-sticker-thank-you"); pause(5000); shot("9-sticker-sent")
        }
        tryIt {
            tap("chat-header"); tap("profile-report"); pause(1500); shot("10-report"); tap("report-cancel"); pause(800); back(); pause(500); back()
            tap("my-avatar"); tap("settings-row-blocked"); pause(1500); shot("11-blocked")
        }
    }

    /** The screens that need no partner: the GIF panel, a sticker, the Report sheet and Settings > Blocked (`tools/record-night3.sh` runs this after the film). */
    @Test fun extraShots() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val benId = JSONObject(pushed.readText()).getJSONObject("accounts").getJSONObject("b").getString("user_id")
        val session = (context.applicationContext as LimeApp).session
        rule.waitUntil(15_000) { count("welcome-continue") > 0 || count("my-avatar") > 0 }
        if (count("welcome-continue") > 0) {
            rule.onNodeWithTag("use-test-account").performClick(); pause(900)
            rule.onNodeWithTag("test-account-ada_android").performClick()
        }
        rule.waitUntil(60_000) { session.deviceRegistered }
        val core = session.store!!
        val dm = "dm:$benId"
        core.startDm(benId, "Ben Android")
        runBlocking { core.sendTextIdentified(session.transport!!, session.accessToken(), benId, "Hello Ben") }
        rule.waitUntil(120_000) { count("conversation-row-$dm") > 0 }
        pause()
        tryIt { tap("conversation-row-$dm"); tap("attach-gif"); pause(1800); shot("8-gif-panel"); tap("gif-sticker-thank-you"); pause(4000); shot("9-sticker-sent") }
        tryIt { tap("chat-header"); tap("profile-report"); pause(1500); shot("10-report"); tap("report-cancel"); pause(800); shot("10b-profile-block") ; back(); pause(500); back() }
        tryIt { tap("my-avatar"); tap("settings-row-blocked"); pause(1500); shot("11-blocked") }
    }
}
