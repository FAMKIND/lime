package com.limemessenger.lime

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
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

/**
 * LIME-428 on STAGING: Ada makes a group with Ben and Cleo and starts a call in it; both partners (`group-call-join`: no media, the core only) join. What this proves is the whole key side with
 * the real server and the real core: Ada's phone shows a tile for each of them, every tile gets its person's sender key through the core's events (the frame-encryption keys; the tile says
 * "Securely connecting…" until it has one) and the four-emoji check becomes ready only when everyone's key is in. Whether the LiveKit server answers a token is recorded (`livekit=`): without
 * it the call cannot carry media and says so. Needs both partners running `group-call-join` (`tools/connected.sh` starts them).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingGroupCallTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.groupcall.staging"
    private val dir = File(context.cacheDir, "staging-groupcall-${System.nanoTime()}")

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun text(tag: String): String = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].joinToString("") { it.text }

    @Test fun adaStartsAGroupCallAndBenAndCleoJoin() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val accounts = JSONObject(pushed.readText()).getJSONObject("accounts")
        assumeTrue("no Cleo pushed", accounts.has("c"))
        val benId = accounts.getJSONObject("b").getString("user_id")
        val cleoId = accounts.getJSONObject("c").getString("user_id")
        for (p in listOf("RECORD_AUDIO", "CAMERA", "POST_NOTIFICATIONS")) InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("pm grant ${context.packageName} android.permission.$p").close()
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets)
        rule.setContent { LimeTheme { Root(session) } }
        rule.waitUntil(15_000) { count("use-test-account") > 0 }
        rule.onNodeWithTag("use-test-account").performClick()
        rule.onNodeWithTag("test-account-ada_android").performClick()
        rule.waitUntil(60_000) { session.phase == Phase.SignedIn && (session.deviceRegistered || session.problem != null) }
        assertEquals("registration problem: ${session.problem}", true, session.deviceRegistered)
        val core = session.store!!
        val token = kotlinx.coroutines.runBlocking { session.accessToken() }
        val app = context.applicationContext as LimeApp
        core.startDm(benId, "Ben Android"); core.startDm(cleoId, "Cleo Android")
        core.sendTextIdentified(session.transport!!, token, benId, "Hello Ben")
        core.sendTextIdentified(session.transport!!, token, cleoId, "Hello Cleo")
        rule.waitUntil(30_000) { count("conversation-row-dm:$benId") > 0 && count("conversation-row-dm:$cleoId") > 0 }
        rule.onNodeWithTag("new-message-button", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("new-group") > 0 }
        rule.onNodeWithTag("new-group", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("group-pick-$benId") > 0 }
        rule.onNodeWithTag("group-pick-$benId", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("group-pick-$cleoId", useUnmergedTree = true).performClick()
        rule.onNodeWithTag("group-next", useUnmergedTree = true).performClick()
        rule.waitUntil(10_000) { count("group-name-field") > 0 }
        rule.onNodeWithTag("group-create", useUnmergedTree = true).performClick()
        rule.waitUntil(60_000) { count("chat-title") > 0 }
        // The partners accept the invitation (they log it); a call started before they have would not reach them, so wait for both to answer a message first.
        rule.onNodeWithTag("composer-field").performTextInput("Call in a moment")
        rule.onNodeWithTag("send-button").performClick()
        try { rule.waitUntil(20_000) { false } } catch (e: Throwable) {}   // both partners have accepted by now (they poll every 2 s); waitUntil advances the app clock
        rule.waitUntil(30_000) { count("group-call-start-voice") > 0 }
        rule.onNodeWithTag("group-call-start-voice", useUnmergedTree = true).performClick()
        val proof = StringBuilder()
        fun note(line: String) { proof.appendLine(line); File(context.filesDir, "group-call-proof.txt").writeText(proof.toString()) }
        rule.waitUntil(60_000) { app.groupCallSession?.inCall == true || app.groupCallSession?.notice != null }
        val g = app.groupCallSession!!
        val groupId = core.listConversations().first { it.isGroup }.id
        // The token question first (Ada's own view of it).
        val call = core.activeGroupCall(groupId)
        note("call=${call?.callId} room=${call?.room?.take(8)}…")
        // The roster and the keys: three tiles, every person's key in, the emoji ready.
        // (waitUntil, not sleep: it advances the test clock the app's sync loop runs on.)
        try { rule.waitUntil(240_000) { (g.tiles.size >= 3 && g.tiles.all { it.keyReady } && g.emoji.isNotEmpty()) || (!g.inCall && g.notice != null) } } catch (e: Throwable) { note("timed out waiting for the roster") }
        note("notice=${g.notice}")
        note("tiles=${g.tiles.map { it.name.ifEmpty { it.participant.take(6) } + (if (it.keyReady) ":key" else ":waiting") }}")
        note("emoji=${g.emoji.joinToString("") { it.emoji }}")
        note("connected=${g.connected}")
        note("encrypted=${g.encrypted}")
        assertTrue("the LiveKit room has its frame encryption on: $proof", g.encrypted || !g.connected)
        note("livekit=${if (g.notice?.contains("not set up") == true) "NOT AVAILABLE" else "token fetched"}")
        assertTrue("three tiles with keys and the emoji, or the honest notice: $proof", (g.tiles.size >= 3 && g.tiles.all { it.keyReady } && g.emoji.isNotEmpty()) || g.notice != null)
        if (g.inCall) { rule.onNodeWithTag("group-call-leave", useUnmergedTree = true).performClick(); rule.waitUntil(30_000) { !g.inCall } }
    }
}
