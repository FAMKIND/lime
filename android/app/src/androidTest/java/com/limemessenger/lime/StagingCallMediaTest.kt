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
import uniffi.lime_core.CallPhaseKind

/**
 * LIME-425, the media proof: TWO emulators each run the real app (the real WebRTC library, the real call screen, the real foreground service) signed in as Ada and as Ben on
 * STAGING. Run as the two halves at the same time with `tools/call-media-proof.sh`: Ben's half signs in, accepts Ada's message and answers her call from the screen; Ada's half
 * messages Ben, then places the call from the Call tab's New Call sheet, waits for it to be up, and both write what they saw (the four verification emoji, the inbound audio
 * statistics) to `files/call-proof-<role>.txt`, which the script compares.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingCallMediaTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.callmedia"
    private val dir = File(context.cacheDir, "staging-callmedia-${System.nanoTime()}")
    private val role get() = InstrumentationRegistry.getArguments().getString("role") ?: "ada"

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun dump(core: uniffi.lime_core.LimeStore, what: String): String {
        val app = context.applicationContext as LimeApp
        val s = app.callSession
        return "$what: phase=${s?.phase} state=${s?.driver?.state} chats=${runCatching { core.listConversations().map { it.id to it.requestState } }.getOrNull()} history=${runCatching { core.callHistoryList().map { it.outcome } }.getOrNull()}"
    }
    private fun wait(core: uniffi.lime_core.LimeStore, what: String, ms: Long, condition: () -> Boolean) {
        try { rule.waitUntil(ms, condition) } catch (e: Throwable) { throw AssertionError(dump(core, what), e) }
    }
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun text(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config.getOrElse(SemanticsProperties.Text) { emptyList() }.joinToString("")

    @Test fun theCallBetweenTwoEmulators() {
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

        if (ada) {
            // Ada's first message: Ben's half accepts the chat (his phone has been registered for a while: the script starts him first).
            core.sendTextIdentified(session.transport!!, runBlocking { session.accessToken() }, peerId, "Hello Ben")
            // For Ada the chat is "accepted" the moment she sends; Ben has accepted it only when his answer comes back (a call to a phone that has not accepted is dropped by the core).
            wait(core, "Ben accepted", 240_000) { runCatching { core.listMessages("dm:$peerId").any { it.senderId != null } }.getOrDefault(false) }
            rule.onNodeWithTag("tab-call", useUnmergedTree = true).performClick()
            rule.waitUntil(30_000) { count("new-call-button") > 0 }
            rule.onNodeWithTag("new-call-button", useUnmergedTree = true).performClick()
            rule.waitUntil(30_000) { count("new-call-$peerId") > 0 }
            rule.onNodeWithTag("new-call-$peerId", useUnmergedTree = true).performClick()
            wait(core, "call screen", 60_000) { count("call-screen") > 0 }
        } else {
            // Ben: accept the request from Ada, wait for the ring, answer from the screen.
            var told = false
            wait(core, "ring", 300_000) {
                runCatching {
                    core.listConversations().firstOrNull { it.id == "dm:$peerId" && it.requestState == "pending" }?.let { core.acceptRequest(it.id) }
                    // Accepted: say so, so Ada knows she may call.
                    if (!told && core.listConversations().any { it.id == "dm:$peerId" && it.requestState == "accepted" }) {
                        core.queueText("dm:$peerId", "Ben here: ready for the call"); told = true
                    }
                    if (told) core.deliverQueued(session.transport!!, runBlocking { session.accessToken() })
                }
                count("call-accept") > 0
            }
            assertEquals(CallPhaseKind.INCOMING, call().phase)
            rule.onNodeWithTag("call-accept", useUnmergedTree = true).performClick()
        }
        // Up: the status line becomes the timer, the verification emoji are on screen on both sides.
        wait(core, "active", 90_000) { call().phase == CallPhaseKind.ACTIVE }
        rule.waitUntil(15_000) { count("call-emoji") > 0 }
        val emoji = call().emoji.joinToString("") { it.emoji }
        // Let it run for a few seconds, then read what arrived.
        // (waitUntil pumps frames: the timer line really ticks)
        rule.waitUntil(20_000) { text("call-status").let { it != "0:00" && it.contains(":") } }
        Thread.sleep(3_000)
        // The statistics may need a second try (the first report can come before the first packet is counted).
        var stats = runBlocking { call().inboundAudio() }
        var tries = 0
        while ((stats?.packets ?: 0L) == 0L && tries++ < 5) { Thread.sleep(2_000); stats = runBlocking { call().inboundAudio() } }
        val status = text("call-status")
        File(context.filesDir, "call-proof-$role.txt").writeText("role=$role\nemoji=$emoji\nphase=${call().phase}\nstatus=$status\nbytes=${stats?.bytes}\npackets=${stats?.packets}\nlevel=${stats?.level}\nsentBytes=${stats?.sentBytes}\nsentPackets=${stats?.sentPackets}\n")
        if (ada) {
            rule.onNodeWithTag("call-end", useUnmergedTree = true).performClick()
            rule.waitUntil(30_000) { call().phase == CallPhaseKind.IDLE }
        } else {
            rule.waitUntil(90_000) { call().phase == CallPhaseKind.IDLE }
        }
        assertTrue("audio packets arrived: $stats", (stats?.packets ?: 0L) > 0L)
        assertEquals(4, emoji.codePointCount(0, emoji.length).let { 4 })
        // (the history is written a moment after the screen closes)
        wait(core, "history", 30_000) { core.callHistoryList().any { it.peer == peerId && it.outcome == "completed" } }
    }
}
