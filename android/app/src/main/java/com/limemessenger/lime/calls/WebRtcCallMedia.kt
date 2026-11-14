package com.limemessenger.lime.calls

import android.content.Context
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import livekit.org.webrtc.AudioTrack
import livekit.org.webrtc.DataChannel
import livekit.org.webrtc.IceCandidate
import livekit.org.webrtc.MediaConstraints
import livekit.org.webrtc.MediaStream
import livekit.org.webrtc.PeerConnection
import livekit.org.webrtc.PeerConnectionFactory
import livekit.org.webrtc.RTCStatsReport
import livekit.org.webrtc.RtpReceiver
import livekit.org.webrtc.SdpObserver
import livekit.org.webrtc.SessionDescription
import livekit.org.webrtc.audio.JavaAudioDeviceModule
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

/** One ice server (a STUN or TURN url with the relay's short-lived credentials). */
data class CallIceServer(val urls: List<String>, val username: String? = null, val credential: String? = null)

/** One candidate from the other phone (`call.ice`). */
data class RemoteCandidate(val sdp: String, val mid: String?, val index: Int)

/** What a call's media reports. */
interface CallMediaEvents {
    /** A candidate found after the description went out: sent in batches (`call.ice`). */
    fun onLocalCandidate(sdp: String, mid: String?, index: Int)
    /** The media path is up (`true`) or has failed (`false`). */
    fun onConnection(up: Boolean)
}

/**
 * One 1:1 call's audio over WebRTC (iOS `CallMedia.swift`): a peer connection with lime's own offer and answer (carried by the call ops, with the DTLS fingerprint inside the signed
 * op), the relay's TURN servers, one audio track from the microphone, and the other person's audio played by WebRTC itself. The library is
 * `io.github.webrtc-sdk:android-prefixed` (the build LiveKit's SDK uses, so group calls add no second copy of the native code).
 */
class WebRtcCallMedia(context: Context, private val events: CallMediaEvents) {
    private val appContext = context.applicationContext
    private var pc: PeerConnection? = null
    private var track: AudioTrack? = null
    private var remoteReady = false
    private val waiting = mutableListOf<RemoteCandidate>()
    private var gathered = CompletableDeferred<Unit>()
    private var descriptionSent = false
    @Volatile private var closed = false

    /** Starts the peer connection with the servers; `relayOnly` is "Always relay calls". */
    fun start(servers: List<CallIceServer>, relayOnly: Boolean) {
        val factory = factory(appContext)
        val ice = servers.map { s ->
            PeerConnection.IceServer.builder(s.urls).also { b -> if (s.username != null) b.setUsername(s.username); if (s.credential != null) b.setPassword(s.credential) }.createIceServer()
        }
        val config = PeerConnection.RTCConfiguration(ice).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            iceTransportsType = if (relayOnly) PeerConnection.IceTransportsType.RELAY else PeerConnection.IceTransportsType.ALL
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_ONCE
        }
        val connection = factory.createPeerConnection(config, object : PeerConnection.Observer {
            override fun onSignalingChange(state: PeerConnection.SignalingState?) {}
            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {}
            override fun onConnectionChange(state: PeerConnection.PeerConnectionState?) {
                if (closed) return
                when (state) {
                    PeerConnection.PeerConnectionState.CONNECTED -> events.onConnection(true)
                    PeerConnection.PeerConnectionState.FAILED -> events.onConnection(false)
                    else -> {}
                }
            }
            override fun onIceConnectionReceivingChange(receiving: Boolean) {}
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) {
                if (state == PeerConnection.IceGatheringState.COMPLETE) gathered.complete(Unit)
            }
            override fun onIceCandidate(candidate: IceCandidate) {
                // Before my description has gone out the candidates are inside it; later ones are sent on their own.
                if (descriptionSent && !closed) events.onLocalCandidate(candidate.sdp, candidate.sdpMid, candidate.sdpMLineIndex)
            }
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {}
            override fun onAddStream(stream: MediaStream?) {}
            override fun onRemoveStream(stream: MediaStream?) {}
            override fun onDataChannel(channel: DataChannel?) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(receiver: RtpReceiver?, streams: Array<out MediaStream>?) {}
        }) ?: error("no peer connection")
        pc = connection
        val source = factory.createAudioSource(MediaConstraints())
        val audio = factory.createAudioTrack("lime-audio", source)
        track = audio
        connection.addTrack(audio, listOf("lime-call"))
    }

    private suspend fun create(offer: Boolean): SessionDescription = suspendCancellableCoroutine { cont ->
        val observer = object : SdpObserver {
            override fun onCreateSuccess(description: SessionDescription) { cont.resume(description) }
            override fun onCreateFailure(error: String?) { cont.resumeWithException(IllegalStateException("create failed: $error")) }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String?) {}
        }
        val connection = pc ?: run { cont.resumeWithException(IllegalStateException("not started")); return@suspendCancellableCoroutine }
        if (offer) connection.createOffer(observer, MediaConstraints().also { it.mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true")) })
        else connection.createAnswer(observer, MediaConstraints())
    }

    private suspend fun setLocal(description: SessionDescription) = suspendCancellableCoroutine<Unit> { cont ->
        val connection = pc ?: run { cont.resumeWithException(IllegalStateException("not started")); return@suspendCancellableCoroutine }
        connection.setLocalDescription(object : SdpObserver {
            override fun onCreateSuccess(description: SessionDescription?) {}
            override fun onCreateFailure(error: String?) {}
            override fun onSetSuccess() { cont.resume(Unit) }
            override fun onSetFailure(error: String?) { cont.resumeWithException(IllegalStateException("set local failed: $error")) }
        }, description)
    }

    private suspend fun setRemote(description: SessionDescription) = suspendCancellableCoroutine<Unit> { cont ->
        val connection = pc ?: run { cont.resumeWithException(IllegalStateException("not started")); return@suspendCancellableCoroutine }
        connection.setRemoteDescription(object : SdpObserver {
            override fun onCreateSuccess(description: SessionDescription?) {}
            override fun onCreateFailure(error: String?) {}
            override fun onSetSuccess() { cont.resume(Unit) }
            override fun onSetFailure(error: String?) { cont.resumeWithException(IllegalStateException("set remote failed: $error")) }
        }, description)
    }

    /** Waits for the first candidates (at most [gatherMillis], and as soon as gathering is complete) so the description carries them. */
    private suspend fun described(): String {
        withTimeoutOrNull(gatherMillis) { gathered.await() }
        descriptionSent = true
        return pc?.localDescription?.description ?: error("no local description")
    }

    /** My offer, as SDP text, with the candidates gathered so far. */
    suspend fun makeOffer(): String {
        setLocal(create(offer = true))
        return described()
    }

    /** Takes the other phone's offer and returns my answer. */
    suspend fun accept(offer: String): String {
        setRemote(SessionDescription(SessionDescription.Type.OFFER, offer))
        remoteReady = true
        flush()
        setLocal(create(offer = false))
        return described()
    }

    suspend fun apply(answer: String) {
        setRemote(SessionDescription(SessionDescription.Type.ANSWER, answer))
        remoteReady = true
        flush()
    }

    /** Candidates from the other phone: kept until its description is in. */
    fun add(candidates: List<RemoteCandidate>) {
        if (closed) return
        if (remoteReady) candidates.forEach { pc?.addIceCandidate(IceCandidate(it.mid, it.index, it.sdp)) } else waiting += candidates
    }

    private fun flush() {
        val list = waiting.toList(); waiting.clear()
        list.forEach { pc?.addIceCandidate(IceCandidate(it.mid, it.index, it.sdp)) }
    }

    fun setMuted(on: Boolean) { track?.setEnabled(!on) }

    /** What the call received so far (for tests and the diagnostics line): inbound audio bytes, packets and the level (0 to 1). */
    suspend fun inboundAudio(): InboundAudio? = withTimeoutOrNull(6_000) {
        val connection = pc ?: return@withTimeoutOrNull null
        suspendCancellableCoroutine<InboundAudio?> { cont ->
            connection.getStats { report: RTCStatsReport ->
                fun audio(type: String) = report.statsMap.values.firstOrNull { it.type == type && (it.members["kind"] == "audio" || it.members["mediaType"] == "audio") }
                val inbound = audio("inbound-rtp"); val outbound = audio("outbound-rtp")
                if (inbound == null && outbound == null) cont.resume(null) else cont.resume(
                    InboundAudio(
                        bytes = (inbound?.members?.get("bytesReceived") as? Number)?.toLong() ?: 0L,
                        packets = (inbound?.members?.get("packetsReceived") as? Number)?.toLong() ?: 0L,
                        level = (inbound?.members?.get("audioLevel") as? Number)?.toDouble() ?: 0.0,
                        sentBytes = (outbound?.members?.get("bytesSent") as? Number)?.toLong() ?: 0L,
                        sentPackets = (outbound?.members?.get("packetsSent") as? Number)?.toLong() ?: 0L,
                    ),
                )
            }
        }
    }

    fun close() {
        closed = true
        runCatching { track?.setEnabled(false) }
        runCatching { pc?.close() }
        pc = null; track = null
    }

    companion object {
        /** The most the description waits for candidates (it also goes as soon as gathering is complete). */
        var gatherMillis = 1_000L
        @Volatile private var factory: PeerConnectionFactory? = null
        private fun factory(context: Context): PeerConnectionFactory = factory ?: synchronized(this) {
            factory ?: run {
                PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context).createInitializationOptions())
                val audio = JavaAudioDeviceModule.builder(context).setUseHardwareAcousticEchoCanceler(true).setUseHardwareNoiseSuppressor(true).createAudioDeviceModule()
                PeerConnectionFactory.builder().setAudioDeviceModule(audio).createPeerConnectionFactory().also { factory = it }
            }
        }
    }
}

/** The inbound audio statistics of a call. */
data class InboundAudio(val bytes: Long, val packets: Long, val level: Double, val sentBytes: Long = 0L, val sentPackets: Long = 0L)
