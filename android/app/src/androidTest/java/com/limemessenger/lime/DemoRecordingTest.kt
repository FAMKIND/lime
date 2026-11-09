package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
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
 * NOT a test of anything: the scripted walk-through that `tools/record-demo.sh` films (launch, test sign-in as Ada, the chat list, Ben's chat,
 * two messages — one **bold** — and the echoes), with pauses so a person can follow it. It uses the REAL app session, so Ada stays signed in
 * afterwards (the script then takes the largest-font and dark-mode screenshots). Needs the pushed accounts and `partner echo` running.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class DemoRecordingTest {
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

    @Test fun walkThrough() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val benId = JSONObject(pushed.readText()).getJSONObject("accounts").getJSONObject("b").getString("user_id")
        val session = (context.applicationContext as LimeApp).session

        rule.waitUntil(15_000) { count("welcome-continue") > 0 || count("my-avatar") > 0 }
        if (count("welcome-continue") > 0) {
            pause(); shot("1-welcome")
            rule.onNodeWithTag("welcome-continue").performClick()
            pause(); shot("2-identifier")
            // Back out to the welcome screen for the debug shortcut (the real flow needs an emailed code).
            rule.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
            rule.onNodeWithTag("use-test-account").performClick(); pause(1000)
            rule.onNodeWithTag("test-account-ada_android").performClick()
        }
        rule.waitUntil(60_000) { session.deviceRegistered }
        rule.waitUntil(30_000) { count("empty-title") > 0 || count("messages-list") > 0 }
        pause(); shot("3-chat-list-empty")

        // Ada's first message to Ben (the new-chat screen is LIME-299; until then this goes through the core).
        runBlocking { session.store!!.sendTextIdentified(session.transport!!, session.accessToken(), benId, "Hello Ben, are we still on for Friday?") }
        val row = "conversation-row-dm:$benId"
        rule.waitUntil(120_000) { count(row) > 0 }
        pause(); shot("4-chat-list")
        rule.onNodeWithTag(row).performClick()
        rule.waitUntil(30_000) { count("chat-title") > 0 }
        pause()
        rule.waitUntil(120_000) { count("message-text-" + messageIds().firstOrNull { it.isNotEmpty() }.orEmpty()) > 0 && descriptions().any { it.startsWith("Ben Android, ") } }
        pause(); shot("5-chat")

        rule.onNodeWithTag("composer-field").performTextInput("Can you cover my bus duty? **Thank you!**")
        pause(1000); rule.onNodeWithTag("send-button").performClick()
        pause(); shot("6-sent")
        rule.waitUntil(120_000) { descriptions().any { it.contains("Ben here: got \"Can you cover my bus duty? Thank you!\"") } }
        pause(); shot("7-echo")

        rule.onNodeWithTag("chat-back").performClick()
        pause(); shot("8-list-with-chat")
    }

    private fun messageIds(): List<String> = rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("message") { it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.TestTag) && it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-") && !it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-text") && !it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-time") })
        .fetchSemanticsNodes().map { it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].removePrefix("message-") }

    private fun descriptions(): List<String> =
        rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("message with words") {
            it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.TestTag) && it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-") && it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription)
        }).fetchSemanticsNodes().map { it.config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString() }
}
