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
import androidx.compose.ui.test.performTextInputSelection
import androidx.compose.ui.text.TextRange
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
import androidx.compose.runtime.CompositionLocalProvider
import com.limemessenger.lime.chats.LinkPreviewFetcher
import com.limemessenger.lime.ui.chat.LocalLinkPreviewFetcher
import uniffi.lime_core.OutgoingPreview

/**
 * LIME-314 on STAGING: Ada records a 3-second video with CameraX (the emulator's camera), adds it to the message and sends it; Ben (the partner running `echo`) downloads and decrypts it and
 * `connected.sh` checks his log (`video: video/mp4|<n> bytes|<ms> ms|WxH|poster…`); Ben answers with the same clip and Ada's bubble shows it; she taps it and the player opens.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingVideoTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.video.staging"
    private val dir = File(context.cacheDir, "staging-video-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun click(tag: String) { rule.onNodeWithTag(tag, useUnmergedTree = true).performClick(); rule.waitForIdle() }
    private fun until(ms: Long, why: String, check: () -> Boolean) { try { rule.waitUntil(ms) { check() } } catch (e: Throwable) { throw AssertionError("timed out: $why", e) } }
    private fun type(text: String) { for (ch in text) { rule.onNodeWithTag("composer-field").performTextInput(ch.toString()); rule.waitForIdle() } }

    @Test fun adaRecordsAVideoBenGetsItWholeAndAdaPlaysBensClip() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val benId = JSONObject(pushed.readText()).getJSONObject("accounts").getJSONObject("b").getString("user_id")
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets)
        val ui = InstrumentationRegistry.getInstrumentation().uiAutomation
        for (p in listOf(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO)) ui.executeShellCommand("pm grant ${context.packageName} $p").use { f -> java.io.FileInputStream(f.fileDescriptor).readBytes() }   // (grantRuntimePermission needs API 28)
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
        val dm = "dm:$benId"
        core.startDm(benId, "Ben Android")
        core.sendTextIdentified(session.transport!!, kotlinx.coroutines.runBlocking { session.accessToken() }, benId, "Hello Ben")
        until(120_000, "the chat with Ben") { count("conversation-row-$dm") > 0 }
        click("conversation-row-$dm")
        until(30_000, "Ben's first echo") { core.listMessages(dm).any { it.senderId != null && it.localState != "system" } }
        click("composer-plus")
        until(10_000, "the attachment sheet") { count("attach-video") > 0 }
        click("attach-video")
        until(30_000, "the camera") { rule.onAllNodes(hasTestTag("video-record"), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull()?.config?.let { SemanticsProperties.Disabled !in it } == true }
        click("video-record")
        until(10_000, "recording") { count("video-stop") > 0 }
        Thread.sleep(3_500)
        click("video-stop")
        until(30_000, "the preview") { count("video-send") > 0 }
        click("video-send")
        until(60_000, "the video in the draft strip") { count("draft-video") > 0 }
        click("send-button")
        until(60_000, "the video to be sent") { core.listMessages(dm).any { it.senderId == null && it.attachments.any { a -> a.mime == "video/mp4" } } }
        val mine = core.listMessages(dm).first { it.senderId == null && it.attachments.any { a -> a.mime == "video/mp4" } }
        until(30_000, "my video tile") { count("video-${mine.attachments.first { it.mime == "video/mp4" }.id}") > 0 }
        until(240_000, "Ben's answer with his clip") { core.listMessages(dm).any { it.senderId != null && it.attachments.any { a -> a.mime == "video/mp4" } } }
        val his = core.listMessages(dm).first { it.senderId != null && it.attachments.any { a -> a.mime == "video/mp4" } }.attachments.first { it.mime == "video/mp4" }
        until(30_000, "Ben's video tile") { count("video-${his.id}") > 0 }
        click("video-${his.id}")
        until(120_000, "the player") { count("video-player") > 0 }
        click("video-player-close")
        until(10_000, "the player to close") { count("video-player") == 0 }
        File(context.filesDir, "shots").mkdirs()
    }
}
