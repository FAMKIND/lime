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

        // Ada starts a chat with Ben from New message (the real lookup on staging), then writes to him.
        rule.onNodeWithTag("new-message-button", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("new-message-field") > 0 }
        pause(800); rule.onNodeWithTag("new-message-field").performTextInput("ben_android")
        pause(800); shot("4-new-message"); rule.onNodeWithTag("new-message-next").performClick()
        rule.waitUntil(60_000) { count("lookup-result") > 0 }
        pause(); shot("5-found")
        rule.onNodeWithTag("lookup-result", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("chat-title") > 0 }
        pause(800)
        say("Hello Ben, are we still on for Friday?")
        waitEcho("""Ben here: got "Hello Ben, are we still on for Friday?"""")
        pause(); shot("6-chat")
        say("Can you cover my bus duty? **Thank you!**")
        pause(600); shot("7-sent")
        waitEcho("""Ben here: got "Can you cover my bus duty? Thank you!"""")
        pause(); shot("8-echo")

        // A photo with a description (the picker is a system screen, so it goes through the core), and Ben's photo back.
        val picture = android.graphics.Bitmap.createBitmap(640, 400, android.graphics.Bitmap.Config.ARGB_8888).also {
            android.graphics.Canvas(it).apply { drawColor(android.graphics.Color.rgb(163, 225, 138)); drawCircle(320f, 200f, 120f, android.graphics.Paint().apply { color = android.graphics.Color.rgb(9, 169, 80) }) }
        }
        val outgoing = com.limemessenger.lime.chats.AttachmentProcessing.photo(picture, "bulletin-board.jpg")!!.copy(alt = "A green circle on a light green background")
        val core = session.store!!
        core.sendAttachments("dm:$benId", "The new bulletin board", listOf(outgoing), null)
        runBlocking { core.deliverQueued(session.transport!!, session.accessToken()) }
        rule.waitUntil(120_000) { descriptions().any { it.contains("Photo: A green gradient fading to dark, from Ben") } }
        pause(2500); shot("9-photos")
        val bensPhoto = core.listMessages("dm:$benId").first { it.senderId != null && it.attachments.isNotEmpty() }.attachments.first()
        rule.waitUntil(60_000) { count("photo-${bensPhoto.id}") > 0 }
        rule.onNodeWithTag("photo-${bensPhoto.id}", useUnmergedTree = true).performClick()
        pause(2000); shot("10-photo-viewer")
        rule.onNodeWithTag("photo-close", useUnmergedTree = true).performClick()
        pause(600)
        rule.onNodeWithTag("chat-header", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("profile-username") > 0 }
        pause(); shot("11-profile")
        rule.onNodeWithTag("profile-back").performClick()
        rule.onNodeWithTag("chat-back").performClick()
        pause(); shot("12-list-with-chat")

        // Settings, then the jam tab.
        rule.onNodeWithTag("my-avatar", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("settings-profile") > 0 }
        pause(); shot("13-settings")
        rule.onNodeWithTag("settings-row-about", useUnmergedTree = true).performClick()
        pause(600); rule.onNodeWithTag("preset-Happy to help", useUnmergedTree = true).performClick()
        pause(600); shot("14-edit-about"); rule.onNodeWithTag("editor-save", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("field-editor") == 0 }
        pause(); shot("15-settings-saved")
        rule.onNodeWithTag("settings-close", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("tab-jam", useUnmergedTree = true).performClick()
        rule.waitUntil(30_000) { count("jam-feed-empty") > 0 }
        pause(); shot("16-jam")
        rule.onNodeWithTag("tab-link", useUnmergedTree = true).performClick()
        pause(600)
    }

    private fun say(text: String) {
        rule.onNodeWithTag("composer-field").performTextInput(text)
        pause(900); rule.onNodeWithTag("send-button").performClick()
    }

    private fun waitEcho(echo: String) = rule.waitUntil(120_000) { descriptions().any { it.contains(echo) } }

    private fun messageIds(): List<String> = rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("message") { it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.TestTag) && it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-") && !it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-text") && !it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-time") })
        .fetchSemanticsNodes().map { it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].removePrefix("message-") }

    private fun descriptions(): List<String> =
        rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("message with words") {
            it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.TestTag) && it.config[androidx.compose.ui.semantics.SemanticsProperties.TestTag].startsWith("message-") && it.config.contains(androidx.compose.ui.semantics.SemanticsProperties.ContentDescription)
        }).fetchSemanticsNodes().map { it.config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString() }
}
