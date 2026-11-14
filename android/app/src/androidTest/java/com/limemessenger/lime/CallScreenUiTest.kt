package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.calls.CallAudioPort
import com.limemessenger.lime.calls.CallIceServer
import com.limemessenger.lime.calls.CallMedia
import com.limemessenger.lime.calls.CallMediaEvents
import com.limemessenger.lime.calls.CallSession
import com.limemessenger.lime.calls.InboundAudio
import com.limemessenger.lime.calls.RemoteCandidate
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.calls.CallScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.CallMachineEvent
import uniffi.lime_core.CallPhaseKind
import uniffi.lime_core.LimeStore

/** LIME-425: the call screen's words, states and targets (the real session and the core's machine, a fake media): TalkBack names, "On"/"Off", 48 dp, the status line, the emoji. */
@RunWith(AndroidJUnit4::class)
class CallScreenUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var session: CallSession
    private val job = Job()
    private val alias = "lime.test.callscreen"
    private val spoken = mutableListOf<String>()

    private class FakeMedia(private val events: CallMediaEvents) : CallMedia {
        private val sdp = "v=0\r\na=fingerprint:sha-256 11:22:33:44\r\n"
        override fun start(servers: List<CallIceServer>, relayOnly: Boolean) {}
        override suspend fun makeOffer() = sdp
        override suspend fun accept(offer: String) = sdp
        override suspend fun apply(answer: String) {}
        override fun add(candidates: List<RemoteCandidate>) {}
        override fun setMuted(on: Boolean) {}
        override suspend fun inboundAudio(): InboundAudio? = null
        override fun close() {}
    }
    private object Quiet : CallAudioPort {
        var onSpeaker = false
        override fun start(speaker: Boolean) {}
        override fun setSpeaker(on: Boolean) { onSpeaker = on }
        override fun stop() {}
        override fun startRingback() {}
        override fun stopRingback() {}
        override fun startRinging() {}
        override fun stopRinging() {}
    }

    @Before fun setUp() {
        dir = File(context.cacheDir, "callscreen-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("callscreen-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        session = CallSession(context, { store }, { null }, { "t" }, { "me" }, CoroutineScope(Dispatchers.Main + job), nameOf = { "Autumn Reyes" }, announce = { spoken += it }, mediaFactory = { FakeMedia(it) }, audio = Quiet, useService = false, opSender = { _, _, _ -> true })
    }
    @After fun tearDown() { job.cancel(); store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun main(block: () -> Unit) = runBlocking(Dispatchers.Main) { block() }
    private fun desc(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
    private fun show() = rule.setContent { LimeTheme { CallScreen(session, chats) } }
    private fun ring() { main { session.driver.handle("call.offer", "in1", "ben", JSONObject().put("sdp", "v=0\r\na=fingerprint:sha-256 AA:BB\r\n")) } }

    @Test fun anIncomingCallShowsWhoIsCallingAndAcceptAndDeclineWithWordsAnd48dpTargets() {
        ring(); show()
        rule.waitUntil(5_000) { count("call-accept") > 0 }
        rule.onNodeWithTag("call-status", useUnmergedTree = true).assertTextEqualsSafe("lime voice call")
        assertEquals("Accept", desc("call-accept")); assertEquals("Decline", desc("call-decline"))
        // the word is under each button too (LIME-326's rule on iOS), and the targets are large
        assertEquals(1, count("call-accept-label")); assertEquals(1, count("call-decline-label"))
        rule.onNodeWithTag("call-accept", useUnmergedTree = true).assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
        rule.onNodeWithTag("call-decline", useUnmergedTree = true).assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
        rule.onNodeWithTag("call-decline", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { session.phase == CallPhaseKind.IDLE }
    }

    @Test fun anActiveCallHasMuteSpeakerAndEndWithOnOffStatesAndTheEmojiAreSpokenWithTheirNames() {
        main { session.call("ben", "Autumn Reyes") }
        rule.waitUntil(5_000) { session.driver.state.remoteRinging || session.driver.state.phase == CallPhaseKind.OUTGOING }
        val id = session.driver.state.callId
        main { session.driver.handle("call.answer", id, "ben", JSONObject().put("sdp", "v=0\r\nanswer")); session.driver.dispatch(CallMachineEvent.MediaUp) }
        show()
        rule.waitUntil(5_000) { count("call-mute") > 0 }
        assertEquals("Mute", desc("call-mute")); assertEquals("Speaker", desc("call-speaker")); assertEquals("End call", desc("call-end"))
        fun state(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.StateDescription]
        assertEquals("Off", state("call-mute")); assertEquals("Off", state("call-speaker"))
        rule.onNodeWithTag("call-mute", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { session.muted }
        assertEquals("On", state("call-mute"))
        rule.onNodeWithTag("call-speaker", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { session.speaker }
        assertEquals("On", state("call-speaker")); assertTrue("the route followed", Quiet.onSpeaker)
        for (tag in listOf("call-mute", "call-speaker", "call-end")) rule.onNodeWithTag(tag, useUnmergedTree = true).assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
        // the timer is the status line (a polite live region)
        rule.waitUntil(5_000) { count("call-status") > 0 }
        assertTrue(rule.onNodeWithTag("call-status", useUnmergedTree = true).fetchSemanticsNode().config.contains(SemanticsProperties.LiveRegion))
        rule.onNodeWithTag("call-end", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { session.phase == CallPhaseKind.IDLE }
        assertFalse(session.muted); assertFalse(session.speaker)
        assertTrue("each phase was said: $spoken", spoken.containsAll(listOf("Calling…", "Connecting…", "Connected", "Call ended")))
    }
}

private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertTextEqualsSafe(text: String) {
    val actual = fetchSemanticsNode().config[SemanticsProperties.Text].joinToString("")
    assertEquals(text, actual)
}
