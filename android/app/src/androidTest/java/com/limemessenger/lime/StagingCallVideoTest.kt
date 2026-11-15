package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.AccountSession.Phase
import com.limemessenger.lime.auth.AuthTokens
import com.limemessenger.lime.auth.LiveAuthService
import com.limemessenger.lime.auth.Profile
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.net.BackendConfig
import com.limemessenger.lime.net.HttpTransport
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.Root
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import com.limemessenger.lime.calls.VideoStats
import uniffi.lime_core.CallPhaseKind

/**
 * LIME-426, the video proof: TWO emulators run the real app (the real WebRTC library, the camera, the control channel) as Ada and Ben on STAGING; run as the two halves at the same
 * time with `PROOF=video tools/call-media-proof.sh`. Call 1 is a video call from the start; call 2 is a voice call Ada turns to video over the control channel (Ben's camera stays off
 * until he turns it on). Each half records what arrived (frames received, decoded and sent, the other side's mute and camera state, the route) to `files/video-proof-<role>.txt`.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingCallVideoTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.callvideoproof"
    private val dir = File(context.cacheDir, "staging-callvideo-${System.nanoTime()}")
    private val role get() = InstrumentationRegistry.getArguments().getString("role") ?: "ada"
    private val log = StringBuilder()

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun note(line: String) { log.appendLine(line); File(context.filesDir, "video-proof-$role.txt").writeText(log.toString()) }

    @Test fun theVideoCallBetweenTwoEmulators() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val ada = role == "ada"
        val accounts = JSONObject(pushed.readText()).getJSONObject("accounts")
        val me = accounts.getJSONObject(if (ada) "a" else "b")
        val peerId = accounts.getJSONObject(if (ada) "b" else "a").getString("user_id")
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets)
        rule.setContent { LimeTheme { Root(session) } }
        rule.waitUntil(15_000) { count("use-test-account") > 0 }
        rule.onNodeWithTag("use-test-account").performClick()
        rule.onNodeWithTag("test-account-${me.getString("username")}").performClick()
        rule.waitUntil(60_000) { session.phase == Phase.SignedIn && (session.deviceRegistered || session.problem != null) }
        assertEquals("registration problem: ${session.problem}", true, session.deviceRegistered)
        val core = session.store!!
        val app = context.applicationContext as LimeApp
        fun call() = app.callSession ?: error("no call session")
        rule.waitUntil(30_000) { app.callSession != null }
        fun state() = "phase=${app.callSession?.phase} video=${app.callSession?.video} remoteShowing=${app.callSession?.remoteVideoShowing} remoteMuted=${app.callSession?.remoteMuted} remoteCam=${app.callSession?.remoteCameraOn} cameraOn=${app.callSession?.cameraOn} local=${app.callSession?.hasLocalVideo} route=${app.callSession?.route}"
        fun wait(what: String, ms: Long, condition: () -> Boolean) { try { rule.waitUntil(ms, condition) } catch (e: Throwable) { throw AssertionError("$what: ${state()}\n$log", e) } }
        /** Frames until the other side's video is arriving (the statistics can lag a second or two). */
        fun framesIn(): VideoStats { var s: VideoStats? = null; var tries = 0; while ((s?.framesReceived ?: 0L) == 0L && tries++ < 12) { Thread.sleep(2_000); s = runBlocking { call().videoStats() } }; return s ?: VideoStats(0, 0, 0, 0, 0) }

        if (ada) {
            core.sendTextIdentified(session.transport!!, runBlocking { session.accessToken() }, peerId, "Hello Ben")
            wait("Ben accepted", 240_000) { runCatching { core.listMessages("dm:$peerId").any { it.senderId != null } }.getOrDefault(false) }
            rule.onNodeWithTag("tab-call", useUnmergedTree = true).performClick()
            rule.waitUntil(30_000) { count("new-call-button") > 0 }
            // ---- call 1: a video call from the start
            rule.onNodeWithTag("new-call-button", useUnmergedTree = true).performClick()
            rule.waitUntil(30_000) { count("new-call-video-$peerId") > 0 }
            rule.onNodeWithTag("new-call-video-$peerId", useUnmergedTree = true).performClick()
            wait("video call screen", 60_000) { count("call-screen") > 0 }
        } else {
            var told = false
            wait("ring", 300_000) {
                runCatching {
                    core.listConversations().firstOrNull { it.id == "dm:$peerId" && it.requestState == "pending" }?.let { core.acceptRequest(it.id) }
                    if (!told && core.listConversations().any { it.id == "dm:$peerId" && it.requestState == "accepted" }) { core.queueText("dm:$peerId", "Ben here: ready for the call"); told = true }
                    if (told) core.deliverQueued(session.transport!!, runBlocking { session.accessToken() })
                }
                count("call-accept") > 0
            }
            rule.onNodeWithTag("call-accept", useUnmergedTree = true).performClick()
        }
        wait("call 1 active", 90_000) { call().phase == CallPhaseKind.ACTIVE }
        note("call1.video=${call().video}"); assertTrue("a video call from the start", call().video)
        val one = framesIn()
        note("call1.framesReceived=${one.framesReceived}\ncall1.framesDecoded=${one.framesDecoded}\ncall1.bytesReceived=${one.bytesReceived}\ncall1.framesSent=${one.framesSent}\ncall1.bytesSent=${one.bytesSent}")
        note("call1.remoteShowing=${call().remoteVideoShowing}\ncall1.route=${call().route}")
        // The other side's mute arrives over the control channel.
        if (ada) { rule.onNodeWithTag("call-mute", useUnmergedTree = true).performClick(); Thread.sleep(2_500) } else { wait("Ada muted", 30_000) { call().remoteMuted }; note("call1.remoteMutedSeen=true") }
        if (ada) rule.onNodeWithTag("call-end", useUnmergedTree = true).performClick()
        wait("call 1 over", 60_000) { call().phase == CallPhaseKind.IDLE }
        assertTrue("video frames arrived in call 1: $one", one.framesReceived > 0)

        // ---- call 2: a voice call turned to video
        if (ada) {
            Thread.sleep(3_000)
            rule.onNodeWithTag("new-call-button", useUnmergedTree = true).performClick()
            rule.waitUntil(30_000) { count("new-call-$peerId") > 0 }
            rule.onNodeWithTag("new-call-$peerId", useUnmergedTree = true).performClick()
            wait("voice call screen", 60_000) { count("call-screen") > 0 }
        } else {
            wait("second ring", 120_000) { count("call-accept") > 0 }
            rule.onNodeWithTag("call-accept", useUnmergedTree = true).performClick()
        }
        wait("call 2 active", 90_000) { call().phase == CallPhaseKind.ACTIVE }
        assertTrue("call 2 starts as voice", !call().video)
        if (ada) {
            rule.waitUntil(15_000) { count("call-start-video") > 0 }
            Thread.sleep(2_000)
            rule.onNodeWithTag("call-start-video", useUnmergedTree = true).performClick()
            wait("Ada's call turned to video", 30_000) { call().video }
        } else {
            wait("the call turned to video", 60_000) { call().video }
            note("call2.cameraOnAtUpgrade=${call().cameraOn}")
            assertTrue("my camera stays off until I choose", !call().cameraOn)
            Thread.sleep(2_000)
            rule.onNodeWithTag("call-video", useUnmergedTree = true).performClick()
            wait("Ben's camera on", 30_000) { call().hasLocalVideo && call().cameraOn }
        }
        wait("both cameras seen", 60_000) { call().remoteCameraOn && call().hasLocalVideo || !ada }
        val two = framesIn()
        note("call2.video=${call().video}\ncall2.framesReceived=${two.framesReceived}\ncall2.framesDecoded=${two.framesDecoded}\ncall2.bytesReceived=${two.bytesReceived}\ncall2.framesSent=${two.framesSent}\ncall2.bytesSent=${two.bytesSent}\ncall2.route=${call().route}")
        note("call2.remoteShowing=${call().remoteVideoShowing}")
        if (ada) rule.onNodeWithTag("call-end", useUnmergedTree = true).performClick()
        wait("call 2 over", 60_000) { call().phase == CallPhaseKind.IDLE }
        assertTrue("video frames arrived after the upgrade: $two", two.framesReceived > 0)
        wait("history", 30_000) { core.callHistoryList().count { it.peer == peerId && it.outcome == "completed" } >= 2 }
    }
}
