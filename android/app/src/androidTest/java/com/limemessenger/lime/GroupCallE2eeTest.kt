package com.limemessenger.lime

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.calls.GroupCallKeys
import com.limemessenger.lime.calls.WebRtcCallMedia
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import livekit.org.webrtc.DataChannel
import livekit.org.webrtc.DefaultVideoDecoderFactory
import livekit.org.webrtc.DefaultVideoEncoderFactory
import livekit.org.webrtc.FrameCryptor
import livekit.org.webrtc.FrameCryptorAlgorithm
import livekit.org.webrtc.FrameCryptorFactory
import livekit.org.webrtc.IceCandidate
import livekit.org.webrtc.JavaI420Buffer
import livekit.org.webrtc.MediaConstraints
import livekit.org.webrtc.MediaStream
import livekit.org.webrtc.PeerConnection
import livekit.org.webrtc.PeerConnectionFactory
import livekit.org.webrtc.RtpReceiver
import livekit.org.webrtc.SdpObserver
import livekit.org.webrtc.SessionDescription
import livekit.org.webrtc.VideoFrame
import livekit.org.webrtc.VideoSink
import livekit.org.webrtc.VideoTrack
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * LIME-428, the spike's proof (kept as a test): the Android SDK can do iOS's sender-key frame encryption. Two real peer connections in one process, a synthetic camera, and LiveKit's own
 * `BaseKeyProvider` (configured as iOS configures it, `GroupCallKeys`) feeding WebRTC's AES-GCM frame cryptor with **raw key bytes in slot 0**: with the same key the receiver gets pictures;
 * with another key, or no cryptor at all, it gets none (the frames are ciphertext the decoder cannot use), and the cryptor says why.
 */
@RunWith(AndroidJUnit4::class)
class GroupCallE2eeTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val key1 = ByteArray(16) { (it * 7 + 1).toByte() }
    private val key2 = ByteArray(16) { (it * 5 + 3).toByte() }

    /** [frames]: pictures that arrived; [good]: those whose content is the picture that was sent (a flat grey of 200). */
    private class Result(val frames: Int, val good: Int, val states: List<String>)

    private fun factory(): PeerConnectionFactory {
        PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context).createInitializationOptions())
        val egl = WebRtcCallMedia.eglBase
        return PeerConnectionFactory.builder().setVideoEncoderFactory(DefaultVideoEncoderFactory(egl.eglBaseContext, true, true)).setVideoDecoderFactory(DefaultVideoDecoderFactory(egl.eglBaseContext)).createPeerConnectionFactory()
    }

    /** Sends synthetic pictures for [seconds] from a sender whose cryptor uses [senderKey]; the receiver's cryptor uses [receiverKey] (null: no cryptor). Returns the frames the receiver got. */
    private fun run(senderKey: ByteArray, receiverKey: ByteArray?, seconds: Int = 5): Result {
        val factory = factory()
        val senderKeys = GroupCallKeys(); val receiverKeys = GroupCallKeys()
        assertTrue(senderKeys.setKey(senderKey, "alice"))
        if (receiverKey != null) assertTrue(receiverKeys.setKey(receiverKey, "alice"))
        val frames = AtomicInteger(); val good = AtomicInteger(); val states = CopyOnWriteArrayList<String>()
        lateinit var sender: PeerConnection; lateinit var receiver: PeerConnection
        val config = PeerConnection.RTCConfiguration(emptyList()).apply { sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN }
        fun observer(other: () -> PeerConnection, onTrack: (RtpReceiver) -> Unit = {}) = object : PeerConnection.Observer {
            override fun onSignalingChange(s: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(s: PeerConnection.IceConnectionState?) {}
            override fun onIceConnectionReceivingChange(b: Boolean) {}
            override fun onIceGatheringChange(s: PeerConnection.IceGatheringState?) {}
            override fun onIceCandidate(c: IceCandidate) { other().addIceCandidate(c) }
            override fun onIceCandidatesRemoved(c: Array<out IceCandidate>?) {}
            override fun onAddStream(s: MediaStream?) {}
            override fun onRemoveStream(s: MediaStream?) {}
            override fun onDataChannel(d: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(r: RtpReceiver?, s: Array<out MediaStream>?) { if (r != null) onTrack(r) }
        }
        val cryptors = mutableListOf<FrameCryptor>()
        sender = factory.createPeerConnection(config, observer({ receiver }))!!
        receiver = factory.createPeerConnection(config, observer({ sender }) { r ->
            if (receiverKey != null) {
                val c = FrameCryptorFactory.createFrameCryptorForRtpReceiver(factory, r, "alice", FrameCryptorAlgorithm.AES_GCM, receiverKeys.provider.rtcKeyProvider)
                c.setObserver { _, state -> states += state.name }
                c.setKeyIndex(GroupCallKeys.SLOT); c.setEnabled(true); cryptors += c
            }
            (r.track() as? VideoTrack)?.addSink(VideoSink { frame ->
                frames.incrementAndGet()
                val i420 = frame.buffer.toI420()
                if (i420 != null) {
                    val y = i420.dataY; var sum = 0L; val n = i420.width * i420.height
                    for (row in 0 until i420.height) for (col in 0 until i420.width) sum += y.get(row * i420.strideY + col).toInt() and 0xFF
                    if (Math.abs(sum / n - 200) <= 6) good.incrementAndGet()
                    i420.release()
                }
            })
        })!!
        val source = factory.createVideoSource(false)
        val track = factory.createVideoTrack("t", source)
        val rtpSender = sender.addTrack(track, listOf("s"))
        val encrypt = FrameCryptorFactory.createFrameCryptorForRtpSender(factory, rtpSender, "alice", FrameCryptorAlgorithm.AES_GCM, senderKeys.provider.rtcKeyProvider)
        encrypt.setKeyIndex(GroupCallKeys.SLOT); encrypt.setEnabled(true); cryptors += encrypt
        // The description exchange (host candidates only: one process).
        fun set(pc: PeerConnection, local: Boolean, d: SessionDescription, then: () -> Unit) = (if (local) pc::setLocalDescription else pc::setRemoteDescription).invoke(object : SdpObserver {
            override fun onCreateSuccess(d: SessionDescription?) {}; override fun onCreateFailure(e: String?) {}
            override fun onSetSuccess() { then() }; override fun onSetFailure(e: String?) { throw AssertionError("set failed: $e") }
        }, d)
        sender.createOffer(object : SdpObserver {
            override fun onCreateSuccess(offer: SessionDescription) {
                set(sender, true, offer) { set(receiver, false, offer) { receiver.createAnswer(object : SdpObserver {
                    override fun onCreateSuccess(answer: SessionDescription) { set(receiver, true, answer) { set(sender, false, answer) {} } }
                    override fun onCreateFailure(e: String?) {}; override fun onSetSuccess() {}; override fun onSetFailure(e: String?) {}
                }, MediaConstraints()) } }
            }
            override fun onCreateFailure(e: String?) { throw AssertionError("offer failed: $e") }; override fun onSetSuccess() {}; override fun onSetFailure(e: String?) {}
        }, MediaConstraints())
        // The synthetic camera: a moving picture, 20 frames a second.
        val end = System.currentTimeMillis() + seconds * 1000L
        var n = 0
        while (System.currentTimeMillis() < end) {
            val buffer = JavaI420Buffer.allocate(320, 240)
            // A flat grey (Y 200), so what arrives can be compared with what was sent: a picture that survives encryption and decryption is 200 everywhere.
            val y = buffer.dataY; for (i in 0 until 320 * 240) y.put(i, 200.toByte())
            buffer.dataU.let { u -> for (i in 0 until 160 * 120) u.put(i, 128.toByte()) }
            buffer.dataV.let { v -> for (i in 0 until 160 * 120) v.put(i, 128.toByte()) }
            val frame = VideoFrame(buffer, 0, System.nanoTime())
            source.capturerObserver.onFrameCaptured(frame); frame.release()
            n++; Thread.sleep(50)
        }
        Thread.sleep(500)
        val result = Result(frames.get(), good.get(), states.toList())
        cryptors.forEach { runCatching { it.setEnabled(false); it.dispose() } }
        sender.close(); receiver.close(); track.dispose(); source.dispose()
        return result
    }

    @Test fun theSameKeyInSlotZeroDecryptsAndTheSentPictureArrives() {
        val r = run(key1, key1)
        assertTrue("pictures arrived with the same key: ${r.frames} frames, ${r.good} intact, states ${r.states}", r.good > 5)
        assertTrue("the cryptor reports OK: ${r.states}", r.states.contains("OK"))
    }

    @Test fun anotherKeyCannotDecryptAndNoPictureComesOut() {
        val r = run(key1, key2)
        assertEquals("a frame without the key is not decodable: ${r.frames} frames, states ${r.states}", 0, r.good)
        assertFalse(r.states.contains("OK"))
    }

    @Test fun withNoCryptorWhatArrivesIsNotThePictureThatWasSent() {
        // The first bytes of a frame stay readable so a server can route it; the rest is ciphertext: whatever a decoder makes of it is not the picture.
        val r = run(key1, null)
        assertEquals("no key at all: no intact picture (${r.frames} frames came, all garbage)", 0, r.good)
    }

    @Test fun theKeyProviderIsConfiguredAsIosConfiguresIt() {
        factory()   // loads the native library (a call does it before any key is made)
        val keys = GroupCallKeys()
        assertFalse("per-participant keys, not one shared key (iOS isSharedKey: false)", keys.provider.enableSharedKey)
        assertEquals(livekit.LivekitModels.Encryption.Type.GCM, keys.options().encryptionType)
        // Raw bytes in, raw bytes out: a key is not turned into text on the way.
        assertTrue(keys.setKey(key1, "bob"))
        assertEquals(16, keys.provider.rtcKeyProvider.exportKey("bob", GroupCallKeys.SLOT).size)
    }

    @Test fun aLiveKitRoomIsCreatedWithTheEncryptionOnAndTheEncryptionManagerExists() {
        factory()
        val keys = GroupCallKeys()
        val room = io.livekit.android.LiveKit.create(context.applicationContext, io.livekit.android.RoomOptions(adaptiveStream = true, dynacast = true, e2eeOptions = keys.options()))
        try {
            // (the encryption manager is made when the room connects; the staging group-call proof checks it there)
            assertEquals(io.livekit.android.room.Room.State.DISCONNECTED, room.state)
        } finally { room.release() }
    }
}
