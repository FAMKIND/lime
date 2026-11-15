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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.CallMachineEvent
import uniffi.lime_core.CallPhaseKind
import uniffi.lime_core.CallRouteKind
import uniffi.lime_core.LimeStore

/**
 * LIME-426: video on the call. The real session and the core's rules with a fake media that records what goes over the control channel: the iOS cases (`CallTests`) for the
 * state messages, ignored messages, the voice call that turns to video, the offer from the other side, a swapped media key, a camera another app takes; the routes; and the
 * video call screen's words and targets.
 */
@RunWith(AndroidJUnit4::class)
class CallVideoTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var session: CallSession
    private val job = Job()
    private val alias = "lime.test.callvideo"
    private val spoken = mutableListOf<String>()
    private lateinit var media: FakeMedia

    private class FakeMedia(val events: CallMediaEvents, val camera: Boolean) : CallMedia {
        val sent = java.util.concurrent.CopyOnWriteArrayList<JSONObject>()
        var local = false
        var videoOn = true
        var videoCall = false
        var restarts = 0
        var flips = 0
        val accepted = java.util.concurrent.CopyOnWriteArrayList<String>()
        override fun configure(video: Boolean, camera: Boolean, lowData: Boolean) { this.videoCall = video; local = video && camera }
        override fun start(servers: List<CallIceServer>, relayOnly: Boolean) {}
        override suspend fun makeOffer() = "v=0\r\na=fingerprint:sha-256 AA:BB\r\n"
        override suspend fun accept(offer: String): String { accepted += offer; return "v=0\r\na=fingerprint:sha-256 AA:BB\r\n" }
        override suspend fun apply(answer: String) {}
        override fun add(candidates: List<RemoteCandidate>) {}
        override fun setMuted(on: Boolean) {}
        override suspend fun inboundAudio(): InboundAudio? = null
        override fun close() {}
        override val hasLocalVideo: Boolean get() = local
        override fun sendControl(text: String): Boolean { sent += JSONObject(text); return true }
        override fun addLocalVideo() { local = true }
        override suspend fun renegotiationOffer() = "v=0\r\na=fingerprint:sha-256 AA:BB\r\n"
        override fun setVideo(on: Boolean) { videoOn = on }
        override fun flipCamera() { flips++ }
        override fun restartCamera() { restarts++ }
    }

    private object Routes : CallAudioPort {
        var available = listOf(CallRouteKind.EARPIECE, CallRouteKind.SPEAKER)
        var now = CallRouteKind.EARPIECE
        var nearEar = false
        var onChanged: (() -> Unit)? = null
        override fun start(speaker: Boolean) { now = if (speaker) CallRouteKind.SPEAKER else CallRouteKind.EARPIECE }
        override fun setSpeaker(on: Boolean) { now = callChoice(on) }
        override fun stop() {}
        override fun startRingback() {}
        override fun stopRingback() {}
        override fun startRinging() {}
        override fun stopRinging() {}
        override fun available() = available
        override fun current() = now
        override fun choose(kind: CallRouteKind) { now = kind }
        override fun setProximity(on: Boolean) { nearEar = on }
        override var onRoutesChanged: (() -> Unit)?
            get() = onChanged
            set(value) { onChanged = value }
        private fun callChoice(speaker: Boolean) = uniffi.lime_core.callRouteChoice(available, speaker)
    }

    @Before fun setUp() {
        dir = File(context.cacheDir, "callvideo-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("callvideo-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        Routes.available = listOf(CallRouteKind.EARPIECE, CallRouteKind.SPEAKER); Routes.now = CallRouteKind.EARPIECE; Routes.nearEar = false
        newSession(camera = true)
    }

    private fun newSession(camera: Boolean) {
        session = CallSession(
            context, { store }, { null }, { "t" }, { "b-me" }, CoroutineScope(Dispatchers.Main + job), nameOf = { "Autumn Reyes" }, announce = { spoken += it },
            mediaFactory = { events -> FakeMedia(events, camera).also { media = it } }, audio = Routes, useService = false, opSender = { _, _, _ -> true }, cameraAllowed = { camera },
        )
    }
    @After fun tearDown() { job.cancel(); store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun main(block: () -> Unit) = runBlocking(Dispatchers.Main) { block() }
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun desc(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
    private fun state(m: JSONObject) = m.getString("t")
    private fun control(text: String) = runBlocking(Dispatchers.Main) { session.handleControl(text) }
    private fun stateMessage(muted: Boolean, camera: Boolean) = "{\"t\":\"state\",\"muted\":$muted,\"camera\":$camera}"
    private fun description(kind: String, fp: String) = JSONObject().put("t", kind).put("sdp", "v=0\r\na=fingerprint:sha-256 $fp\r\n").toString()

    /** An active call to Ben (who the core knows as the peer); the answer carries the media key CC:DD. */
    private fun connected(video: Boolean = false) {
        main { session.call("ben", "Autumn Reyes", video) }
        rule.waitUntil(5_000) { session.driver.state.phase == CallPhaseKind.OUTGOING }
        val id = session.driver.state.callId
        main { session.driver.handle("call.answer", id, "ben", JSONObject().put("sdp", "v=0\r\na=fingerprint:sha-256 CC:DD\r\n")); session.driver.dispatch(CallMachineEvent.MediaUp) }
        rule.waitUntil(5_000) { session.phase == CallPhaseKind.ACTIVE }
    }

    @Test fun theOtherSidesMuteAndCameraStateArrivesOverTheControlChannel() {
        connected(video = true)
        assertFalse(session.remoteMuted); assertTrue(session.remoteCameraOn)
        control(stateMessage(muted = true, camera = false))
        assertTrue(session.remoteMuted); assertFalse(session.remoteCameraOn)
        assertFalse("their camera is off: their avatar, not a frozen or black picture", session.remoteVideoShowing)
        control(stateMessage(muted = false, camera = true))
        assertFalse(session.remoteMuted); assertTrue(session.remoteCameraOn)
    }

    @Test fun unknownOversizedAndMalformedControlMessagesAreIgnored() {
        connected()
        control("{\"t\":\"wave\",\"x\":1}"); control("not json"); control("{\"muted\":true}")
        control("{\"t\":\"state\",\"muted\":true,\"pad\":\"" + "x".repeat(70_000) + "\"}")
        assertFalse(session.remoteMuted); assertEquals(CallPhaseKind.ACTIVE, session.phase)
    }

    @Test fun myStateIsSentWhenTheChannelOpensAndOnEveryChange() {
        connected(video = true)
        main { media.events.onControlOpen() }
        rule.waitUntil(5_000) { media.sent.isNotEmpty() }
        assertEquals("state", state(media.sent.last())); assertFalse(media.sent.last().getBoolean("muted")); assertTrue(media.sent.last().getBoolean("camera"))
        main { session.toggleMute() }
        assertTrue(media.sent.last().getBoolean("muted"))
        main { session.toggleCamera() }
        assertFalse(media.sent.last().getBoolean("camera")); assertFalse(media.videoOn)
        main { session.toggleCamera() }
        assertTrue(media.sent.last().getBoolean("camera")); assertTrue(media.videoOn)
    }

    @Test fun aVoiceCallTurnsIntoVideoOverTheControlChannelAndStaysOneCall() {
        connected()
        assertFalse(session.video); assertEquals(CallRouteKind.EARPIECE, session.route)
        runBlocking(Dispatchers.Main) { session.startVideo() }
        assertTrue(session.video); assertTrue(media.local)
        val offer = media.sent.firstOrNull { state(it) == "offer" }
        assertNotNull(offer); assertTrue(offer!!.getString("sdp").contains("AA:BB"))
        assertEquals("the sound moves to the speaker for video", CallRouteKind.SPEAKER, session.route)
        // Their answer carries the same media key: taken. The call is still one call, recorded as a video call.
        control(description("answer", "CC:DD"))
        assertEquals(CallPhaseKind.ACTIVE, session.phase)
        assertTrue(session.driver.state.video)
        main { session.hangUp() }
        rule.waitUntil(5_000) { session.phase == CallPhaseKind.IDLE }
    }

    @Test fun theOtherSideAddingVideoIsAnsweredAndMyCameraStaysOff() {
        connected()
        control(description("offer", "CC:DD"))
        assertTrue("the screen turns to video", session.video)
        assertFalse("they see no picture of me until I choose to", session.cameraOn); assertFalse(media.local)
        assertTrue(media.sent.any { state(it) == "answer" })
        main { session.toggleCamera() }
        rule.waitUntil(5_000) { media.local }
        rule.waitUntil(5_000) { media.sent.any { state(it) == "offer" } }
        assertTrue(session.cameraOn)
    }

    @Test fun aMidCallDescriptionWithAnotherMediaKeyEndsTheCall() {
        connected()
        control(description("offer", "EE:FF"))
        rule.waitUntil(5_000) { session.phase == CallPhaseKind.IDLE }
        assertFalse(media.sent.any { state(it) == "answer" })
    }

    @Test fun anAnswerWithAnotherMediaKeyEndsTheCallToo() {
        connected()
        runBlocking(Dispatchers.Main) { session.startVideo() }
        control(description("answer", "99:99"))
        rule.waitUntil(5_000) { session.phase == CallPhaseKind.IDLE }
    }

    @Test fun bothAddingVideoAtOnceTheLowerIdsOfferStands() {
        // I am "b-me" and they are "ben": "b-me" < "ben", so mine stands and theirs is dropped.
        connected()
        runBlocking(Dispatchers.Main) { session.startVideo() }
        val before = media.accepted.size
        control(description("offer", "CC:DD"))
        assertEquals("their offer was dropped", before, media.accepted.size)
        assertEquals(CallPhaseKind.ACTIVE, session.phase)
    }

    @Test fun anInterruptedCameraPausesMyPictureAndTellsTheOtherSide() {
        connected(video = true)
        main { media.events.onCameraInterrupted(true) }
        rule.waitUntil(5_000) { session.cameraHeld && media.sent.isNotEmpty() && !media.sent.last().getBoolean("camera") }
        assertFalse(media.videoOn)
        main { media.events.onCameraInterrupted(false) }
        rule.waitUntil(5_000) { !session.cameraHeld && media.sent.last().getBoolean("camera") }
    }

    @Test fun theBackgroundHoldsTheCameraAndComingBackRestartsIt() {
        connected(video = true)
        main { session.setBackgrounded(true) }
        assertTrue(session.cameraHeld); assertFalse(media.videoOn)
        main { session.setBackgrounded(false) }
        assertFalse(session.cameraHeld); assertTrue(media.videoOn); assertEquals(1, media.restarts)
    }

    @Test fun aVideoCallStartsOnTheSpeakerAndAVoiceCallAtTheEarWithTheSensorOnlyForVoice() {
        connected()
        assertEquals(CallRouteKind.EARPIECE, session.route); assertTrue("the sensor blanks the screen at the ear", Routes.nearEar)
        runBlocking(Dispatchers.Main) { session.startVideo() }
        assertFalse("never in video", Routes.nearEar)
        main { session.hangUp() }
        rule.waitUntil(5_000) { session.phase == CallPhaseKind.IDLE }
        assertFalse(Routes.nearEar)
        connected(video = true)
        assertEquals(CallRouteKind.SPEAKER, session.route); assertFalse(Routes.nearEar)
    }

    @Test fun withoutTheCameraPermissionAVideoCallStillReceivesAndMyCameraIsOff() {
        newSession(camera = false)
        connected(video = true)
        assertTrue(session.video); assertFalse(media.local); assertFalse(session.cameraOn)
    }

    @Test fun aHeadsetComingAndGoingMovesTheSoundAndSaysSo() {
        connected()
        Routes.available = listOf(CallRouteKind.EARPIECE, CallRouteKind.SPEAKER, CallRouteKind.BLUETOOTH)
        main { Routes.now = CallRouteKind.BLUETOOTH; Routes.onChanged?.invoke() }
        rule.waitUntil(5_000) { session.routeToast == "Audio now on Bluetooth" }
        assertTrue(spoken.contains("Audio now on Bluetooth"))
        rule.waitUntil(5_000) { session.routeToast == null }
    }

    // ---- the screen

    private fun show() = rule.setContent { LimeTheme { CallScreen(session, chats) } }

    @Test fun theVideoScreenHasCameraMuteRouteEndAndFlipWithWordsAndLargeTargets() {
        connected(video = true)
        show()
        rule.waitUntil(5_000) { count("call-video") > 0 }
        assertEquals("Camera", desc("call-video")); assertEquals("Mute", desc("call-mute")); assertEquals("End call", desc("call-end")); assertEquals("Flip camera", desc("call-flip"))
        assertEquals("Audio output, now Speaker", desc("call-route"))
        fun stateOf(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.StateDescription]
        assertEquals("Off", stateOf("call-video").let { if (media.local) "Off" else it })
        for (tag in listOf("call-video", "call-mute", "call-route", "call-end", "call-flip", "call-tile")) rule.onNodeWithTag(tag, useUnmergedTree = true).assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
        rule.onNodeWithTag("call-flip", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { media.flips == 1 }
        assertEquals(1, count("call-remote-camera-off"))
    }

    @Test fun theRemoteMutedLabelAndTheRouteListShowAndTheListHasTheRoutesTheyHave() {
        connected(video = true)
        Routes.available = listOf(CallRouteKind.EARPIECE, CallRouteKind.SPEAKER, CallRouteKind.WIRED)
        show()
        rule.waitUntil(5_000) { count("call-route") > 0 }
        control(stateMessage(muted = true, camera = true))
        rule.waitUntil(5_000) { count("call-remote-muted") > 0 }
        assertEquals("Autumn Reyes is muted", desc("call-remote-muted"))
        rule.onNodeWithTag("call-route", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("call-route-wired") > 0 }
        assertEquals(1, count("call-route-earpiece")); assertEquals(1, count("call-route-speaker")); assertEquals(0, count("call-route-bluetooth"))
        rule.onNodeWithTag("call-route-wired", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { session.route == CallRouteKind.WIRED }
        assertEquals("Audio output, now Headphones", desc("call-route"))
    }

    @Test fun theTileSwapsWithATapAndMovesWithAnAccessibilityAction() {
        connected(video = true)
        show()
        rule.waitUntil(5_000) { count("call-tile") > 0 }
        assertEquals("Your picture", desc("call-tile"))
        rule.onNodeWithTag("call-tile", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { desc("call-tile") == "Autumn Reyes" }
        val actions = rule.onNodeWithTag("call-tile", useUnmergedTree = true).fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsActions.CustomActions]
        assertEquals("Move to the other corner", actions.single().label)
    }

    @Test fun aVoiceCallShowsAVideoButtonThatTurnsTheCallToVideo() {
        connected()
        show()
        rule.waitUntil(5_000) { count("call-start-video") > 0 }
        assertEquals("Video", desc("call-start-video"))
        rule.onNodeWithTag("call-start-video", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { session.video }
        rule.waitUntil(5_000) { count("call-flip") > 0 }
    }
}
