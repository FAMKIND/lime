package com.limemessenger.lime

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.calls.CallDriver
import com.limemessenger.lime.calls.CallMediaPort
import com.limemessenger.lime.calls.CallsModel
import com.limemessenger.lime.calls.RemoteCandidate
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.CallMachineAction
import uniffi.lime_core.CallMachineEvent
import uniffi.lime_core.CallPhaseKind
import uniffi.lime_core.CallResult
import uniffi.lime_core.LimeStore

/**
 * LIME-425: the driver against the core's machine (`call_rules.rs`) with a fake media, real timers scaled down (the 45 s ring is under a second): every phase, every ending,
 * what is sent to the other phone and what the history says. No network: the sent ops are captured.
 */
@RunWith(AndroidJUnit4::class)
class CallDriverTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private val alias = "lime.test.driver"
    private val job = Job()
    private val sent = mutableListOf<Triple<String, String, String?>>()
    private val media = FakeMedia()
    private lateinit var driver: CallDriver
    private val announced = mutableListOf<String>()
    private val order = mutableListOf<String>()

    private inner class FakeMedia : CallMediaPort {
        val log = mutableListOf<String>()
        var candidates = mutableListOf<RemoteCandidate>()
        override fun startOutgoing(callId: String, video: Boolean) { log += "startOutgoing" }
        override fun showIncoming(callId: String, name: String, video: Boolean) { log += "showIncoming:$name" }
        override fun acceptIncoming(callId: String, offerSdp: String, video: Boolean) { log += "accept:${offerSdp.length}" }
        override fun applyAnswer(callId: String, answerSdp: String) { log += "applyAnswer:${answerSdp.length}" }
        override fun remoteCandidates(callId: String, list: List<RemoteCandidate>) { candidates += list }
        override fun startRingback() { log += "ringback" }
        override fun stopRingback() { log += "stopRingback" }
        override fun stopRinging() { log += "stopRinging" }
        override fun tearDown(callId: String) { log += "tearDown"; order += "tearDown" }
    }

    @Before fun setUp() {
        dir = File(context.cacheDir, "driver-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("driver-user")).store
        driver = CallDriver(
            store = { store }, transport = { null }, token = { "t" }, myId = { "me" }, scope = CoroutineScope(Dispatchers.Default + job), nameOf = { it.uppercase() },
            media = media, announce = { announced += it }, timerScale = 0.02, sender = { sent += Triple(it.op, it.callId, it.reason); order += it.op },
        )
    }
    @After fun tearDown() { job.cancel(); store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun until(what: String, ms: Long = 5_000, condition: () -> Boolean) = runBlocking {
        val end = System.currentTimeMillis() + ms
        while (!condition()) { if (System.currentTimeMillis() > end) throw AssertionError("timed out: $what; phase=${driver.state.phase} sent=$sent media=${media.log}"); delay(10) }
    }
    private fun history() = store.callHistoryList()
    private fun waitLogged(n: Int = 1) = until("history has $n") { history().size >= n }
    private fun placeOut() { driver.dispatch(CallMachineEvent.TapCall("c1", "ben", "Ben", false)); driver.dispatch(CallMachineEvent.OfferSent) }
    private fun offerFromBen(id: String = "in1", sdp: String = "v=0\r\na=fingerprint:sha-256 AA:BB\r\n") =
        driver.handle("call.offer", id, "ben", JSONObject().put("video", false).put("sdp", sdp))

    @Test fun anOutgoingCallRingsIsAnsweredConnectsAndEndsWithItsLength() {
        placeOut()
        assertEquals(CallPhaseKind.OUTGOING, driver.state.phase)
        assertTrue(media.log.containsAll(listOf("startOutgoing", "ringback")))
        driver.handle("call.ringing", "c1", "ben", JSONObject())
        assertTrue(driver.state.remoteRinging)
        driver.handle("call.answer", "c1", "ben", JSONObject().put("sdp", "v=0\r\nanswer"))
        assertEquals(CallPhaseKind.CONNECTING, driver.state.phase)
        until("applyAnswer") { media.log.any { it.startsWith("applyAnswer:") } }
        assertTrue("the ringback stopped", media.log.contains("stopRingback"))
        driver.dispatch(CallMachineEvent.MediaUp)
        assertEquals(CallPhaseKind.ACTIVE, driver.state.phase)
        runBlocking { delay(1_100) }
        driver.dispatch(CallMachineEvent.TapHangUp)
        assertEquals(CallPhaseKind.IDLE, driver.state.phase)
        assertEquals(listOf("call.end" to "c1"), sent.map { it.first to it.second })
        assertTrue(media.log.last() == "tearDown")
        assertEquals("the other phone is told before the media closes", listOf("call.end", "tearDown"), order)
        waitLogged()
        val row = history().single()
        assertEquals(CallResult.COMPLETED, CallsModel.toEntry(row).result)
        assertTrue(row.outgoing && row.durationMs >= 1_000)
        assertEquals("Calling\u2026", announced.first())
        assertTrue("Ringing…" in announced && "Connected" in announced && "Call ended" in announced)
    }

    @Test fun anIncomingCallRingsTellsTheCallerAndIsAnsweredWithTheOffersSdp() {
        offerFromBen()
        assertEquals(CallPhaseKind.INCOMING, driver.state.phase)
        assertTrue(media.log.any { it.startsWith("showIncoming:") })
        assertEquals("the callee tells the caller it is ringing", listOf("call.ringing"), sent.map { it.first })
        driver.dispatch(CallMachineEvent.TapAnswer)
        assertEquals(CallPhaseKind.CONNECTING, driver.state.phase)
        assertTrue("the media got the offer", media.log.any { it.startsWith("accept:") && it != "accept:0" })
        driver.dispatch(CallMachineEvent.AnswerSent)
        driver.dispatch(CallMachineEvent.MediaUp)
        assertEquals(CallPhaseKind.ACTIVE, driver.state.phase)
        driver.handle("call.end", "in1", "ben", JSONObject())
        assertEquals(CallPhaseKind.IDLE, driver.state.phase)
        waitLogged()
        assertEquals(CallResult.COMPLETED, CallsModel.toEntry(history().single()).result)
        assertTrue("the other phone ended it: nothing more is sent", sent.none { it.first == "call.end" })
    }

    @Test fun declineBusyAndUnansweredEveryEndingIsTheRightOutcomeAndTheRightOp() {
        // declined by the other phone
        placeOut(); driver.handle("call.decline", "c1", "ben", JSONObject())
        assertEquals(CallPhaseKind.IDLE, driver.state.phase); waitLogged(1)
        // busy
        sent.clear(); driver.dispatch(CallMachineEvent.TapCall("c2", "ben", "Ben", false)); driver.dispatch(CallMachineEvent.OfferSent)
        driver.handle("call.busy", "c2", "ben", JSONObject()); waitLogged(2)
        // I decline an incoming call: call.decline goes out
        sent.clear(); offerFromBen("in3"); driver.dispatch(CallMachineEvent.TapDecline)
        assertEquals(listOf("call.ringing", "call.decline"), sent.map { it.first }); waitLogged(3)
        // nobody picks up: after the (scaled) ring timeout the call is "No answer" and the other phone is told
        sent.clear(); driver.dispatch(CallMachineEvent.TapCall("c4", "ben", "Ben", false)); driver.dispatch(CallMachineEvent.OfferSent)
        until("no answer", 5_000) { driver.state.phase == CallPhaseKind.IDLE }
        until("the other phone is told") { sent.isNotEmpty() }
        assertEquals(listOf("call.end"), sent.map { it.first }); waitLogged(4)
        val results = history().map { CallsModel.toEntry(it) }.associate { it.id to it.result }
        assertEquals(CallResult.DECLINED, results["c1"]); assertEquals(CallResult.BUSY, results["c2"])
        assertEquals(CallResult.DECLINED, results["in3"]); assertEquals(CallResult.NO_ANSWER, results["c4"])
    }

    @Test fun anIncomingCallThatRingsOutIsMissedAndASecondCallerHearsBusy() {
        offerFromBen("in5")
        sent.clear()
        driver.handle("call.offer", "other", "sam", JSONObject().put("sdp", "v=0\r\na=fingerprint:sha-256 CC\r\n"))
        assertEquals(listOf("call.busy" to "other"), sent.map { it.first to it.second })
        assertEquals("the call that rings goes on", "in5", driver.state.callId)
        until("missed after the ring timeout", 5_000) { driver.state.phase == CallPhaseKind.IDLE }
        waitLogged()
        assertEquals(CallResult.MISSED, CallsModel.toEntry(history().single()).result)
        assertTrue("stopRinging" in media.log)
    }

    @Test fun theMediaNeverComingUpFailsTheCallAndTellsTheOtherPhone() {
        placeOut()
        driver.handle("call.answer", "c1", "ben", JSONObject().put("sdp", "v=0\r\nanswer"))
        until("connect timeout (30 s scaled)", 5_000) { driver.state.phase == CallPhaseKind.IDLE }
        until("the other phone is told") { sent.isNotEmpty() }
        assertEquals(listOf("call.end"), sent.map { it.first })
        waitLogged()
        assertEquals(CallResult.FAILED, CallsModel.toEntry(history().single()).result)
        // a failure of the media itself ends it the same way
        sent.clear(); media.log.clear()
        driver.dispatch(CallMachineEvent.TapCall("c6", "ben", "Ben", false)); driver.dispatch(CallMachineEvent.OfferSent)
        driver.handle("call.answer", "c6", "ben", JSONObject().put("sdp", "v=0\r\nanswer"))
        driver.dispatch(CallMachineEvent.AnswerApplyFailed)
        assertEquals(CallPhaseKind.IDLE, driver.state.phase)
        assertEquals(listOf("call.end"), sent.map { it.first })
    }

    @Test fun candidatesThatArriveBeforeTheirOfferAreKeptForTheCall() {
        driver.handle("call.ice", "in7", "ben", JSONObject().put("candidates", org.json.JSONArray().put(JSONObject().put("candidate", "candidate:1 1 udp 1 1.2.3.4 5 typ host").put("sdpMid", "0").put("sdpMLineIndex", 0))))
        assertTrue("nothing yet: there is no call", media.candidates.isEmpty())
        offerFromBen("in7")
        assertEquals(1, media.candidates.size)
        // later ones go straight to the media
        driver.handle("call.ice", "in7", "ben", JSONObject().put("candidate", "candidate:2 1 udp 1 5.6.7.8 9 typ host").put("sdpMid", "0").put("sdpMLineIndex", 0))
        assertEquals(2, media.candidates.size)
    }
}
