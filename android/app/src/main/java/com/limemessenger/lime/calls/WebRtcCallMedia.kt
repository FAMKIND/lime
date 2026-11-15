package com.limemessenger.lime.calls

import android.content.Context
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import livekit.org.webrtc.AudioTrack
import livekit.org.webrtc.Camera2Enumerator
import livekit.org.webrtc.CameraVideoCapturer
import livekit.org.webrtc.DataChannel
import livekit.org.webrtc.DefaultVideoDecoderFactory
import livekit.org.webrtc.DefaultVideoEncoderFactory
import livekit.org.webrtc.EglBase
import livekit.org.webrtc.IceCandidate
import livekit.org.webrtc.MediaConstraints
import livekit.org.webrtc.MediaStream
import livekit.org.webrtc.PeerConnection
import livekit.org.webrtc.PeerConnectionFactory
import livekit.org.webrtc.RTCStatsReport
import livekit.org.webrtc.RtpReceiver
import livekit.org.webrtc.SdpObserver
import livekit.org.webrtc.SessionDescription
import livekit.org.webrtc.SurfaceTextureHelper
import livekit.org.webrtc.VideoFrame
import livekit.org.webrtc.VideoSink
import livekit.org.webrtc.VideoSource
import livekit.org.webrtc.VideoTrack
import livekit.org.webrtc.audio.JavaAudioDeviceModule
import uniffi.lime_core.callVideoCapture
import uniffi.lime_core.callVideoMaxBitrate
import uniffi.lime_core.callVideoMaxFps
import java.nio.ByteBuffer
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
    /** The in-call control channel (`lime-ctl`) opened: send my state. */
    fun onControlOpen() {}
    /** A text message from the other phone over the control channel. */
    fun onControl(text: String) {}
    /** The other person's video is arriving (the first frame came) or stopped being drawn. */
    fun onRemoteVideo(receiving: Boolean) {}
    /** The camera was taken away (another app has it, or it failed) or is back. */
    fun onCameraInterrupted(held: Boolean) {}
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
    private var control: DataChannel? = null
    private var videoSource: VideoSource? = null
    private var videoTrack: VideoTrack? = null
    private var capturer: CameraVideoCapturer? = null
    private var helper: SurfaceTextureHelper? = null
    private var front = true
    private var lowData = false
    private var remoteSeen = false
    private val localProxy = ProxySink()
    private val remoteProxy = ProxySink { if (!remoteSeen && !closed) { remoteSeen = true; events.onRemoteVideo(true) } }

    val hasLocalVideo: Boolean get() = videoTrack != null

    /** Where my camera's picture is drawn (the call screen's small tile), or nothing. */
    fun attachLocal(sink: VideoSink?) { localProxy.target = sink }
    /** Where the other person's picture is drawn, or nothing. */
    fun attachRemote(sink: VideoSink?) { remoteProxy.target = sink }

    /** Starts the peer connection with the servers; `relayOnly` is "Always relay calls"; `video` adds the camera (a video call). */
    fun start(servers: List<CallIceServer>, relayOnly: Boolean, video: Boolean = false, camera: Boolean = video, lowData: Boolean = false) {
        this.lowData = lowData
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
            override fun onDataChannel(channel: DataChannel?) { if (channel != null && channel.label() == CONTROL_LABEL && control == null) watch(channel) }
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(receiver: RtpReceiver?, streams: Array<out MediaStream>?) {
                val remote = receiver?.track() as? VideoTrack ?: return
                remote.addSink(remoteProxy)
            }
        }) ?: error("no peer connection")
        pc = connection
        val source = factory.createAudioSource(MediaConstraints())
        val audio = factory.createAudioTrack("lime-audio", source)
        track = audio
        connection.addTrack(audio, listOf("lime-audio-stream"))
        if (video && camera) addLocalVideo()
        // A video call without a camera (no permission) still receives the other person's picture.
        else if (video) connection.addTransceiver(livekit.org.webrtc.MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO, livekit.org.webrtc.RtpTransceiver.RtpTransceiverInit(livekit.org.webrtc.RtpTransceiver.RtpTransceiverDirection.RECV_ONLY))
    }

    private fun watch(channel: DataChannel) {
        control = channel
        channel.registerObserver(object : DataChannel.Observer {
            override fun onBufferedAmountChange(previous: Long) {}
            override fun onStateChange() { if (channel.state() == DataChannel.State.OPEN && !closed) events.onControlOpen() }
            override fun onMessage(buffer: DataChannel.Buffer) {
                if (buffer.binary || closed) return
                val bytes = ByteArray(buffer.data.remaining()).also { buffer.data.get(it) }
                events.onControl(String(bytes, Charsets.UTF_8))
            }
        })
    }

    /** Sends a control message; false when the channel is not open. */
    fun sendControl(text: String): Boolean {
        val channel = control ?: return false
        if (channel.state() != DataChannel.State.OPEN) return false
        return channel.send(DataChannel.Buffer(ByteBuffer.wrap(text.toByteArray(Charsets.UTF_8)), false))
    }

    /** Adds my camera: a video track from the phone's camera at the size the settings choose (720p at 24 fps, Low Data 360p at 15), drawn in the local tile. */
    fun addLocalVideo() {
        val connection = pc ?: error("not started")
        if (videoTrack != null) return
        val factory = factory(appContext)
        val source = factory.createVideoSource(false)
        val track = factory.createVideoTrack("lime-video", source)
        videoSource = source; videoTrack = track
        track.addSink(localProxy)
        connection.addTrack(track, listOf("lime-video-stream"))
        applyLimits()
        startCapture(source)
    }

    private fun startCapture(source: VideoSource) {
        val enumerator = Camera2Enumerator(appContext)
        val names = enumerator.deviceNames
        val name = names.firstOrNull { if (front) enumerator.isFrontFacing(it) else enumerator.isBackFacing(it) } ?: names.firstOrNull() ?: return
        val handler = object : CameraVideoCapturer.CameraEventsHandler {
            override fun onCameraError(errorDescription: String?) { if (!closed) events.onCameraInterrupted(true) }
            override fun onCameraDisconnected() { if (!closed) events.onCameraInterrupted(true) }
            override fun onCameraFreezed(errorDescription: String?) {}
            override fun onCameraOpening(cameraName: String?) {}
            override fun onFirstFrameAvailable() { if (!closed) events.onCameraInterrupted(false) }
            override fun onCameraClosed() {}
        }
        val capture = enumerator.createCapturer(name, handler) ?: return
        val textureHelper = SurfaceTextureHelper.create("lime-capture", eglBase.eglBaseContext)
        helper = textureHelper
        capture.initialize(textureHelper, appContext, source.capturerObserver)
        val plan = callVideoCapture(lowData, false, false)
        capture.startCapture(plan.width.toInt(), plan.height.toInt(), plan.fps.toInt())
        capturer = capture
    }

    /** Low Data Mode caps what the video sender may use. */
    private fun applyLimits() {
        val connection = pc ?: return
        connection.senders.filter { it.track()?.kind() == "video" }.forEach { sender ->
            val parameters = sender.parameters
            parameters.encodings.forEach { e ->
                e.maxBitrateBps = callVideoMaxBitrate(lowData)?.toInt()
                e.maxFramerate = callVideoMaxFps(lowData)?.toInt()
            }
            sender.parameters = parameters
        }
    }

    /** The camera sends (true) or shows nothing (false: the other side sees my avatar, not a black picture). */
    fun setVideo(on: Boolean) { videoTrack?.setEnabled(on) }

    /** The camera comes back after another app or the background had it: capture starts again from a clean capturer. */
    fun restartCamera() {
        val source = videoSource ?: return
        runCatching { capturer?.stopCapture(); capturer?.dispose() }
        runCatching { helper?.dispose() }
        capturer = null; helper = null
        startCapture(source)
    }

    /** The other camera, front to back or back to front. */
    fun flipCamera() {
        front = !front
        capturer?.switchCamera(null)
    }

    /** My description with the camera added, to send over the control channel (no new gathering: the media rides the same connection). */
    suspend fun renegotiationOffer(): String {
        val connection = pc ?: error("not started")
        setLocal(create(offer = true, video = true))
        return connection.localDescription.description
    }

    private suspend fun create(offer: Boolean, video: Boolean = videoTrack != null): SessionDescription = suspendCancellableCoroutine { cont ->
        val observer = object : SdpObserver {
            override fun onCreateSuccess(description: SessionDescription) { cont.resume(description) }
            override fun onCreateFailure(error: String?) { cont.resumeWithException(IllegalStateException("create failed: $error")) }
            override fun onSetSuccess() {}
            override fun onSetFailure(error: String?) {}
        }
        val connection = pc ?: run { cont.resumeWithException(IllegalStateException("not started")); return@suspendCancellableCoroutine }
        if (offer) connection.createOffer(observer, MediaConstraints().also {
            it.mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            it.mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", if (video) "true" else "false"))
        })
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
        // The control channel is made before the offer so it is in the description.
        if (control == null) pc?.createDataChannel(CONTROL_LABEL, DataChannel.Init().also { it.ordered = true })?.let { watch(it) }
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

    /** What the call received and sent as video so far (the proof and the diagnostics line). */
    suspend fun videoStats(): VideoStats? = withTimeoutOrNull(6_000) {
        val connection = pc ?: return@withTimeoutOrNull null
        suspendCancellableCoroutine<VideoStats?> { cont ->
            connection.getStats { report: RTCStatsReport ->
                fun video(type: String) = report.statsMap.values.firstOrNull { it.type == type && (it.members["kind"] == "video" || it.members["mediaType"] == "video") }
                val inbound = video("inbound-rtp"); val outbound = video("outbound-rtp")
                fun num(o: livekit.org.webrtc.RTCStats?, k: String) = (o?.members?.get(k) as? Number)?.toLong() ?: 0L
                if (inbound == null && outbound == null) cont.resume(null) else cont.resume(
                    VideoStats(framesReceived = num(inbound, "framesReceived"), framesDecoded = num(inbound, "framesDecoded"), bytesReceived = num(inbound, "bytesReceived"), framesSent = num(outbound, "framesSent"), bytesSent = num(outbound, "bytesSent")),
                )
            }
        }
    }

    fun close() {
        closed = true
        runCatching { track?.setEnabled(false) }
        runCatching { capturer?.stopCapture() }
        runCatching { capturer?.dispose() }
        runCatching { videoTrack?.removeSink(localProxy); videoTrack?.dispose() }
        runCatching { videoSource?.dispose() }
        runCatching { helper?.dispose() }
        localProxy.target = null; remoteProxy.target = null
        runCatching { control?.close(); control?.dispose() }
        runCatching { pc?.close() }
        pc = null; track = null; control = null; capturer = null; videoTrack = null; videoSource = null; helper = null
    }

    companion object {
        /** The most the description waits for candidates (it also goes as soon as gathering is complete). */
        var gatherMillis = 1_000L
        /** The one EGL context the camera, the encoder, the decoder and the video views share. */
        val eglBase: EglBase by lazy { EglBase.create() }
        /** Loads WebRTC's native code (a group call's key provider needs it before any peer connection exists). */
        fun ensureLoaded(context: Context) { factory(context.applicationContext) }
        const val CONTROL_LABEL = "lime-ctl"
        @Volatile private var factory: PeerConnectionFactory? = null
        private fun factory(context: Context): PeerConnectionFactory = factory ?: synchronized(this) {
            factory ?: run {
                PeerConnectionFactory.initialize(PeerConnectionFactory.InitializationOptions.builder(context).createInitializationOptions())
                val audio = JavaAudioDeviceModule.builder(context).setUseHardwareAcousticEchoCanceler(true).setUseHardwareNoiseSuppressor(true).createAudioDeviceModule()
                PeerConnectionFactory.builder().setAudioDeviceModule(audio)
                    .setVideoEncoderFactory(DefaultVideoEncoderFactory(eglBase.eglBaseContext, true, true))
                    .setVideoDecoderFactory(DefaultVideoDecoderFactory(eglBase.eglBaseContext))
                    .createPeerConnectionFactory().also { factory = it }
            }
        }
    }
}

/** The inbound audio statistics of a call. */
data class InboundAudio(val bytes: Long, val packets: Long, val level: Double, val sentBytes: Long = 0L, val sentPackets: Long = 0L)

/** The video statistics of a call. */
data class VideoStats(val framesReceived: Long, val framesDecoded: Long, val bytesReceived: Long, val framesSent: Long, val bytesSent: Long)

/** A video sink whose target can change (the call screen's views come and go; the track stays). */
class ProxySink(private val seen: (() -> Unit)? = null) : VideoSink {
    @Volatile var target: VideoSink? = null
    override fun onFrame(frame: VideoFrame) { seen?.invoke(); target?.onFrame(frame) }
}
