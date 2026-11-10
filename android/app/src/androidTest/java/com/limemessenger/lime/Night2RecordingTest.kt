package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.down
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.up
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
 * NOT a test of anything: the scripted walk-through of night 2 that `tools/record-night2.sh` films: a group with Ben and Cleo, a reaction and an edit,
 * a voice message, pin and search, Appearance and Privacy, with pauses so a person can follow it. REAL app session; needs the pushed accounts and both
 * partners running `group-echo --direct`. Screenshots go to files/shots (the script pulls them).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class Night2RecordingTest {
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
    private fun descriptions(): List<String> =
        rule.onAllNodes(SemanticsMatcher("message") { it.config.contains(SemanticsProperties.TestTag) && it.config[SemanticsProperties.TestTag].startsWith("message-") && it.config.contains(SemanticsProperties.ContentDescription) })
            .fetchSemanticsNodes().map { it.config[SemanticsProperties.ContentDescription].joinToString() }
    private fun tryIt(block: () -> Unit) { try { block() } catch (e: Throwable) { /* a best-effort step of a film: it never fails the take */ } }
    private fun back() = rule.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }

    @Test fun walkThrough() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val accounts = JSONObject(pushed.readText()).getJSONObject("accounts")
        val benId = accounts.getJSONObject("b").getString("user_id"); val cleoId = accounts.getJSONObject("c").getString("user_id")
        val session = (context.applicationContext as LimeApp).session

        rule.waitUntil(15_000) { count("welcome-continue") > 0 || count("my-avatar") > 0 }
        if (count("welcome-continue") > 0) {
            rule.onNodeWithTag("use-test-account").performClick(); pause(900)
            rule.onNodeWithTag("test-account-ada_android").performClick()
        }
        rule.waitUntil(60_000) { session.deviceRegistered }
        val core = session.store!!
        core.startDm(benId, "Ben Android"); core.startDm(cleoId, "Cleo Android")
        runBlocking {
            val token = session.accessToken()
            core.sendTextIdentified(session.transport!!, token, benId, "Hello Ben"); core.sendTextIdentified(session.transport!!, token, cleoId, "Hello Cleo")
        }
        rule.waitUntil(60_000) { count("conversation-row-dm:$benId") > 0 && count("conversation-row-dm:$cleoId") > 0 }
        pause(); shot("1-list")

        // A group with Ben and Cleo.
        rule.onNodeWithTag("new-message-button", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("new-group") > 0 }
        pause(700); rule.onNodeWithTag("new-group", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("group-pick-$benId") > 0 }
        pause(700); rule.onNodeWithTag("group-pick-$benId", useUnmergedTree = true).performClick()
        pause(500); rule.onNodeWithTag("group-pick-$cleoId", useUnmergedTree = true).performClick()
        pause(700); shot("2-new-group"); rule.onNodeWithTag("group-next", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("group-name-field") > 0 }
        pause(700)
        rule.onNodeWithTag("group-name-field", useUnmergedTree = true).performTextClearance()
        rule.onNodeWithTag("group-name-field", useUnmergedTree = true).performTextInput("Staff room")
        pause(700); rule.onNodeWithTag("group-create", useUnmergedTree = true).performClick()
        rule.waitUntil(60_000) { count("chat-title") > 0 }
        pause(700)
        rule.onNodeWithTag("composer-field").performTextInput("Hello team, lunch at noon?")
        pause(800); rule.onNodeWithTag("send-button").performClick()
        rule.waitUntil(180_000) {
            descriptions().any { it.startsWith("Ben Android, ") && it.contains("got \"Hello team") } && descriptions().any { it.startsWith("Cleo Android, ") && it.contains("got \"Hello team") }
        }
        pause(); shot("3-group-chat")

        // A reaction and an edit.
        val group = core.listConversations().first { it.isGroup }.id
        val echo = core.listMessages(group).first { it.senderId == benId }.id
        rule.onNodeWithTag("message-text-$echo", useUnmergedTree = true).performTouchInput { longClick() }
        rule.waitUntil(10_000) { count("message-actions") > 0 }
        pause(900); shot("4-message-menu"); rule.onNodeWithTag("react-👍", useUnmergedTree = true).performClick()
        pause(1500)
        val mine = core.listMessages(group).first { it.senderId == null && it.text.startsWith("Hello team") }.id
        rule.onNodeWithTag("message-text-$mine", useUnmergedTree = true).performTouchInput { longClick() }
        rule.waitUntil(10_000) { count("message-actions") > 0 }
        pause(600); rule.onNodeWithTag("action-edit", useUnmergedTree = true).performClick()
        pause(600)
        rule.onNodeWithTag("edit-field", useUnmergedTree = true).performTextClearance()
        rule.onNodeWithTag("edit-field", useUnmergedTree = true).performTextInput("Hello team, lunch at 12:30?")
        pause(600); rule.onNodeWithTag("edit-save", useUnmergedTree = true).performClick()
        pause(1800); shot("5-reaction-and-edit")

        // A voice message (the real microphone; best effort).
        tryIt {
            rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { down(center) }
            rule.waitUntil(8_000) { count("recording-bar") > 0 }
            pause(2200); shot("6-recording")
            rule.onNodeWithTag("voice-mic", useUnmergedTree = true).performTouchInput { up() }
            pause(2500)
        }

        // Back to the list: pin the group, then search.
        rule.onNodeWithTag("chat-back").performClick()
        rule.waitUntil(10_000) { count("messages-list") > 0 }
        val groupRow = "conversation-row-$group"
        pause(800); rule.onNodeWithTag(groupRow, useUnmergedTree = true).performTouchInput { longClick() }
        rule.waitUntil(10_000) { count("row-actions") > 0 }
        pause(900); shot("7-row-actions"); rule.onNodeWithTag("row-action-pin", useUnmergedTree = true).performClick()
        pause(1500)
        rule.onNodeWithTag("search-button", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("search-field") > 0 }
        pause(600); rule.onNodeWithTag("search-field", useUnmergedTree = true).performTextInput("lunch")
        rule.waitUntil(30_000) { count("search-results") > 0 }
        pause(1200); shot("8-search")
        back(); pause(800)

        // Appearance: Blue on Paper (then back to lime's own look), and Privacy with Lock lime.
        rule.onNodeWithTag("my-avatar", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("settings-profile") > 0 }
        pause(700); rule.onNodeWithTag("settings-row-appearance", useUnmergedTree = true).performScrollTo().performClick()
        rule.waitUntil(10_000) { count("appearance-screen") > 0 }
        pause(700); rule.onNodeWithTag("accent-4", useUnmergedTree = true).performScrollTo().performClick()
        pause(500); rule.onNodeWithTag("background-paper", useUnmergedTree = true).performScrollTo().performClick()
        pause(1500); shot("9-appearance")
        rule.onNodeWithTag("appearance-reset", useUnmergedTree = true).performScrollTo().performClick(); pause(700)
        back()
        pause(600); rule.onNodeWithTag("settings-row-privacy", useUnmergedTree = true).performScrollTo().performClick()
        rule.waitUntil(10_000) { count("privacy-screen") > 0 }
        pause(900); shot("10-privacy")
        back(); pause(500); back(); pause(800)
    }
}
