package com.limemessenger.lime

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.AccountSession.Phase
import com.limemessenger.lime.auth.AuthTokens
import com.limemessenger.lime.auth.LiveAuthService
import com.limemessenger.lime.auth.Profile
import com.limemessenger.lime.calls.CallAudioPort
import com.limemessenger.lime.calls.CallIceServer
import com.limemessenger.lime.calls.CallMedia
import com.limemessenger.lime.calls.CallMediaEvents
import com.limemessenger.lime.calls.CallSession
import com.limemessenger.lime.calls.CallsModel
import com.limemessenger.lime.calls.InboundAudio
import com.limemessenger.lime.calls.RemoteCandidate
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.net.BackendConfig
import com.limemessenger.lime.net.HttpTransport
import com.limemessenger.lime.storage.StorageBootstrap
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.CallPhaseKind
import uniffi.lime_core.CallResult

/**
 * LIME-425 on STAGING, signalling only: Ada's REAL call session (the core's machine, the real `call.*` ops through the server) with a fake media, against the host-side partner
 * running `call-script` (made-up SDPs): Ada calls and Ben answers and she hangs up (A); Ben calls and she answers (B); busy (C); decline (D); no answer after the timeout (E);
 * Ben calls and she declines (F). Needs the pushed test accounts and the partner started BEFORE Ada acts (`tools/connected.sh` does both).
 */
@Staging
@RunWith(AndroidJUnit4::class)
class StagingCallSignallingTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "lime.test.callsignalling"
    private val dir = File(context.cacheDir, "staging-callsig-${System.nanoTime()}")
    private val job = Job()

    @After fun tearDown() { job.cancel(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private class FakeMedia(private val events: CallMediaEvents) : CallMedia {
        private val fp = "11:22:33:44:55:66:77:88:11:22:33:44:55:66:77:88:11:22:33:44:55:66:77:88:11:22:33:44:55:66:77:88"
        private val sdp = "v=0\r\na=fingerprint:sha-256 $fp\r\n"
        override fun start(servers: List<CallIceServer>, relayOnly: Boolean) {}
        override suspend fun makeOffer() = sdp
        override suspend fun accept(offer: String): String { Thread { Thread.sleep(300); events.onConnection(true) }.start(); return sdp }
        override suspend fun apply(answer: String) { events.onConnection(true) }
        override fun add(candidates: List<RemoteCandidate>) {}
        override fun setMuted(on: Boolean) {}
        override suspend fun inboundAudio(): InboundAudio? = null
        override fun close() {}
    }
    private object Quiet : CallAudioPort {
        override fun start(speaker: Boolean) {}
        override fun setSpeaker(on: Boolean) {}
        override fun stop() {}
        override fun startRingback() {}
        override fun stopRingback() {}
        override fun startRinging() {}
        override fun stopRinging() {}
    }

    @Test fun everyEndingOfACallWorksThroughStaging() {
        val pushed = File(context.filesDir, "test-accounts.json")
        assumeTrue("no pushed test accounts", pushed.exists())
        val backend = BackendConfig.current
        assumeTrue("no backend", backend != null)
        val all = JSONObject(pushed.readText()).getJSONObject("accounts")
        val benId = all.getJSONObject("b").getString("user_id")
        val a = all.getJSONObject("a")
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val session = AccountSession(LiveAuthService(HttpTransport(backend!!.url, backend.apiKey)), backend, StorageBootstrap(File(dir, "data"), secrets), secrets)
        runBlocking {
            session.completeSignIn(AuthTokens(a.getString("access_token"), a.getString("refresh_token"), a.getLong("expires_at") * 1000, a.getString("user_id")), Profile(a.getString("display_name"), a.getString("username")))
        }
        val registered = System.currentTimeMillis() + 60_000
        while (!(session.phase == Phase.SignedIn && (session.deviceRegistered || session.problem != null)) && System.currentTimeMillis() < registered) Thread.sleep(200)
        assertEquals("registration problem: ${session.problem}", true, session.deviceRegistered)
        val core = session.store!!
        val scope = CoroutineScope(Dispatchers.Main + job)
        val calls = CallsModel { core }
        val call = CallSession(
            context = context, store = { core }, transport = { session.transport }, token = { session.accessToken() }, myId = { session.userId }, scope = scope,
            nameOf = { "Ben Android" }, mediaFactory = { FakeMedia(it) }, timerScale = 0.5, audio = Quiet, useService = false,
        )
        // The sync loop the list model runs: fetch, then hand the call ops to the session.
        scope.launch { while (true) { withContext(Dispatchers.IO) { runCatching { core.sync(session.transport!!, session.accessToken()) } }; call.handleArrivals(); delay(600) } }

        fun phase() = runBlocking(Dispatchers.Main) { call.phase }
        fun until(what: String, ms: Long = 90_000, condition: () -> Boolean) {
            val end = System.currentTimeMillis() + ms
            while (!condition()) { if (System.currentTimeMillis() > end) throw AssertionError("timed out: $what; phase=${phase()} history=${core.callHistoryList().map { it.outcome }}"); Thread.sleep(200) }
        }
        fun lastOutcome() = core.callHistoryList().maxByOrNull { it.atMs }?.let { CallsModel.toEntry(it).result }
        fun onMain(block: () -> Unit) = runBlocking(Dispatchers.Main) { block() }

        // Ada's first message: Ben accepts the chat; from then on calls go between them.
        core.sendTextIdentified(session.transport!!, runBlocking { session.accessToken() }, benId, "Hello Ben")
        // A: Ada calls, Ben rings and answers, the (fake) media comes up, Ada hangs up.
        until("chat accepted") { runCatching { core.listConversations().any { it.id == "dm:$benId" && it.requestState == "accepted" } }.getOrDefault(false) }
        onMain { call.call(benId, "Ben Android") }
        until("A: active") { phase() == CallPhaseKind.ACTIVE }
        Thread.sleep(1_500)
        onMain { call.hangUp() }
        until("A: idle") { phase() == CallPhaseKind.IDLE }
        until("A: logged") { core.callHistoryList().size >= 1 }
        assertEquals(CallResult.COMPLETED, lastOutcome())
        // B: Ben calls Ada; she rings, tells him, answers; he hangs up after 2 s.
        until("B: ringing here") { phase() == CallPhaseKind.INCOMING }
        onMain { call.answer() }
        until("B: active") { phase() == CallPhaseKind.ACTIVE }
        until("B: ended by Ben") { phase() == CallPhaseKind.IDLE }
        until("B: logged") { core.callHistoryList().size >= 2 }
        assertEquals(CallResult.COMPLETED, lastOutcome())
        // C: busy.
        onMain { call.call(benId, "Ben Android") }
        until("C: busy") { phase() == CallPhaseKind.IDLE && core.callHistoryList().size >= 3 }
        assertEquals(CallResult.BUSY, lastOutcome())
        // D: declined.
        onMain { call.call(benId, "Ben Android") }
        until("D: declined") { phase() == CallPhaseKind.IDLE && core.callHistoryList().size >= 4 }
        assertEquals(CallResult.DECLINED, lastOutcome())
        // E: nobody picks up: after the (scaled) ring time it is "No answer" and Ben is told.
        onMain { call.call(benId, "Ben Android") }
        until("E: no answer", 120_000) { phase() == CallPhaseKind.IDLE && core.callHistoryList().size >= 5 }
        assertEquals(CallResult.NO_ANSWER, lastOutcome())
        // F: Ben calls; she declines.
        until("F: ringing here") { phase() == CallPhaseKind.INCOMING }
        onMain { call.decline() }
        until("F: idle") { phase() == CallPhaseKind.IDLE && core.callHistoryList().size >= 6 }
        assertEquals(CallResult.DECLINED, lastOutcome())
        assertTrue(core.callHistoryList().map { it.outcome }.toString(), core.callHistoryList().size == 6)
    }
}
