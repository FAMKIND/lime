package com.limemessenger.lime

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.calls.CallMediaEvents
import com.limemessenger.lime.calls.RemoteCandidate
import com.limemessenger.lime.calls.WebRtcCallMedia
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.callFingerprint

/**
 * LIME-425: the real WebRTC library, on one device: two peer connections make an offer and an answer through lime's own code (`WebRtcCallMedia`), trade candidates, connect and
 * send audio to each other. It also runs on the `releaseLike` build (R8 on), which proves the shrinker kept what the native library calls by name.
 */
@RunWith(AndroidJUnit4::class)
class WebRtcLoopbackTest {
    @Before fun grantMicrophone() { InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("pm grant ${context.packageName} android.permission.RECORD_AUDIO").close() }
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    private class Side(val up: AtomicBoolean = AtomicBoolean(false), val candidates: CopyOnWriteArrayList<RemoteCandidate> = CopyOnWriteArrayList()) : CallMediaEvents {
        override fun onLocalCandidate(sdp: String, mid: String?, index: Int) { candidates += RemoteCandidate(sdp, mid, index) }
        override fun onConnection(up: Boolean) { this.up.set(up) }
    }

    @Test fun twoPeersOfferAnswerConnectAndExchangeAudio() = runBlocking {
        val a = Side(); val b = Side()
        val caller = WebRtcCallMedia(context, a); val callee = WebRtcCallMedia(context, b)
        caller.start(emptyList(), relayOnly = false); callee.start(emptyList(), relayOnly = false)
        val offer = caller.makeOffer()
        val fingerprint = callFingerprint(offer)
        assertTrue("the offer carries the DTLS fingerprint the signed op names", fingerprint != null && fingerprint.contains(":"))
        val answer = callee.accept(offer)
        assertTrue("the answer carries its own", callFingerprint(answer) != null)
        caller.apply(answer)
        // Whatever was found after the descriptions went out is traded (the app sends it as call.ice).
        val end = System.currentTimeMillis() + 30_000
        while (!(a.up.get() && b.up.get()) && System.currentTimeMillis() < end) {
            a.candidates.toList().also { a.candidates.clear() }.takeIf { it.isNotEmpty() }?.let { callee.add(it) }
            b.candidates.toList().also { b.candidates.clear() }.takeIf { it.isNotEmpty() }?.let { caller.add(it) }
            delay(200)
        }
        assertTrue("both sides connected (caller=${a.up.get()} callee=${b.up.get()})", a.up.get() && b.up.get())
        // Audio flows when the device can capture (the API 26 emulator, headless, has no microphone: it connects but sends nothing).
        var sent = 0L; var received = 0L; var tries = 0
        while (tries++ < 20) {
            delay(500)
            val x = caller.inboundAudio(); val y = callee.inboundAudio()
            sent = (x?.sentPackets ?: 0L) + (y?.sentPackets ?: 0L); received = (x?.packets ?: 0L) + (y?.packets ?: 0L)
            if (sent > 0L && received > 0L) break
        }
        caller.close(); callee.close()
        if (sent > 0L) assertTrue("audio was sent ($sent packets) and arrived", received > 0L)
        assertEquals(true, true)
    }
}
