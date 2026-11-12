package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
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
 * NOT a test of anything: the scripted walk-through of night 4 that `tools/record-night4.sh` films: the chat's Back with the number of other unread chats (Cleo writes while Ada is in
 * Ben's chat), a video message (record with the emulator's camera, add, send, Ben answers with a clip, play it), and the jam feed's Filter sheet. REAL app session; needs the pushed accounts
 * and Ben and Cleo each running `echo`. Every step after sign-in is best-effort (a film never fails the take). Screenshots go to files/shots (the script pulls them).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class Night4RecordingTest {
    @get:Rule val rule = createAndroidComposeRule<MainActivity>()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val shots get() = File(context.filesDir, "shots").also { it.mkdirs() }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun pause(ms: Long = 1800) = Thread.sleep(ms)
    private fun shot(name: String) {
        rule.waitForIdle(); pause(500)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(shots, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun tryIt(block: () -> Unit) { try { block() } catch (e: Throwable) { /* a best-effort step of a film */ } }
    private fun tap(tag: String, wait: Long = 20_000) { rule.waitUntil(wait) { count(tag) > 0 }; pause(700); rule.onNodeWithTag(tag, useUnmergedTree = true).performClick() }
    private fun ready(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull()?.config?.let { SemanticsProperties.Disabled !in it } == true

    @Test fun walkThrough() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val accounts = JSONObject(pushed.readText()).getJSONObject("accounts")
        val benId = accounts.getJSONObject("b").getString("user_id")
        val cleoId = accounts.getJSONObject("c").getString("user_id")
        val session = (context.applicationContext as LimeApp).session
        val ui = InstrumentationRegistry.getInstrumentation().uiAutomation
        for (p in listOf(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO)) ui.executeShellCommand("pm grant ${context.packageName} $p").use { f -> java.io.FileInputStream(f.fileDescriptor).readBytes() }

        rule.waitUntil(15_000) { count("welcome-continue") > 0 || count("my-avatar") > 0 }
        if (count("welcome-continue") > 0) {
            rule.onNodeWithTag("use-test-account").performClick(); pause(900)
            rule.onNodeWithTag("test-account-ada_android").performClick()
        }
        rule.waitUntil(60_000) { session.deviceRegistered }
        val core = session.store!!
        val dm = "dm:$benId"
        core.startDm(benId, "Ben Android")
        core.startDm(cleoId, "Cleo Android")
        runBlocking { core.sendTextIdentified(session.transport!!, session.accessToken(), benId, "Hello Ben") }
        runBlocking { core.sendTextIdentified(session.transport!!, session.accessToken(), cleoId, "Hello Cleo") }
        rule.waitUntil(120_000) { count("conversation-row-$dm") > 0 }
        pause(); shot("1-list")

        // Open Ben's chat; Cleo's answer arrives meanwhile: Back shows 1 other unread chat.
        tryIt {
            tap("conversation-row-$dm")
            rule.waitUntil(240_000) { core.listMessages("dm:$cleoId").any { it.senderId != null && it.localState != "system" } }
            rule.waitUntil(60_000) { count("chat-back-count") > 0 }
            pause(); shot("2-back-count")
        }

        // A video message: record 3 seconds, add it, send it; Ben answers with the clip; play it.
        tryIt {
            tap("composer-plus"); tap("attach-video")
            rule.waitUntil(40_000) { ready("video-record") }
            pause(800); shot("3-video-camera")
            tap("video-record"); pause(3500); shot("4-video-recording")
            tap("video-stop"); rule.waitUntil(30_000) { count("video-send") > 0 }
            pause(2500); shot("5-video-preview")
            tap("video-send"); rule.waitUntil(60_000) { count("draft-video") > 0 }
            pause(); shot("6-video-draft")
            tap("send-button")
            rule.waitUntil(240_000) { core.listMessages(dm).count { it.attachments.any { a -> a.mime == "video/mp4" } } >= 2 }
            pause(3000); shot("7-video-bubbles")
            val his = core.listMessages(dm).first { it.senderId != null && it.attachments.any { a -> a.mime == "video/mp4" } }.attachments.first { it.mime == "video/mp4" }
            tap("video-${his.id}"); rule.waitUntil(120_000) { count("video-player") > 0 }
            pause(3500); shot("8-video-player")
            tap("video-player-close"); pause(800)
            tap("chat-back"); pause(1200)
        }

        // The jam feed's Filter sheet.
        tryIt {
            tap("tab-jam"); pause(1500)
            rule.onNodeWithTag("jam-filter-button", useUnmergedTree = true).performClick(); pause(1200)
            shot("9-jam-filter-sheet")
            tap("jam-filter-coauthored"); pause(800); shot("10-jam-filter-on")
        }
    }
}
