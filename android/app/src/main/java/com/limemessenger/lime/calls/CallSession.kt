package com.limemessenger.lime.calls

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.limemessenger.lime.net.HttpTransport
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import livekit.org.webrtc.VideoSink
import uniffi.lime_core.CallControlMessage
import uniffi.lime_core.CallEmoji
import uniffi.lime_core.CallMachineEvent
import uniffi.lime_core.CallPhaseKind
import uniffi.lime_core.CallRouteKind
import uniffi.lime_core.LimeStore
import uniffi.lime_core.RenegotiationVerdict
import uniffi.lime_core.callEmoji
import uniffi.lime_core.callCameraSending
import uniffi.lime_core.callControlDescription
import uniffi.lime_core.callControlState
import uniffi.lime_core.callFingerprint
import uniffi.lime_core.callProximityOn
import uniffi.lime_core.callRemoteVideoShowing
import uniffi.lime_core.callRenegotiationAnswer
import uniffi.lime_core.callRenegotiationOffer
import uniffi.lime_core.callRouteChoice
import uniffi.lime_core.callRouteToast
import uniffi.lime_core.callSpeakerByDefault
import uniffi.lime_core.parseCallControl
import uniffi.lime_core.callRelayAllowed
import uniffi.lime_core.callRelayUnavailableWords

/**
 * One phone's calls (iOS `CallManager`): the thin driver of the core's machine plus what the machine cannot do, the media. It places and answers 1:1 audio calls
 * over WebRTC, sends and receives the `call.*` ops, runs the audio (earpiece or speaker, ringback, the ring of an incoming call) and the foreground service, and
 * keeps what the call screen shows (muted, speaker, the four verification emoji). Every decision (phases, timeouts, busy, glare, outcomes) is the core's `call_rules.rs`.
 * All calls come on the main thread.
 */
class CallSession(
    private val context: Context,
    private val store: () -> LimeStore?,
    private val transport: () -> HttpTransport?,
    private val token: suspend () -> String,
    private val myId: () -> String?,
    private val scope: CoroutineScope,
    nameOf: (String) -> String = { it },
    onLogged: () -> Unit = {},
    private val announce: (String) -> Unit = {},
    /** Replaces the WebRTC media (tests give a fake one). */
    private val mediaFactory: (CallMediaEvents) -> CallMedia = { events -> RealCallMedia(context, events) },
    /** Scales the machine's timers (tests run them in a fraction of the time). */
    timerScale: Double = 1.0,
    private val audio: CallAudioPort = RealCallAudio(context),
    private val useService: Boolean = true,
    /** Where the call ops go instead of the server (tests): peer, op, payload; true when sent. */
    private val opSender: ((String, String, JSONObject) -> Boolean)? = null,
    /** Low Data Mode (Settings → Calls): a smaller picture and a cap on what the camera sends. */
    private val lowData: () -> Boolean = { false },
    /** Whether the camera permission is granted (a video call without it receives video and sends none). */
    private val cameraAllowed: () -> Boolean = { true },
    /** lime is in front: the call screen is the ring; otherwise the incoming-call notification is. */
    private val foreground: () -> Boolean = { true },
) {
    /** The call screen is put away and the mini-bar shows instead (a voice call, or a video call that could not float). */
    var minimized by mutableStateOf(false); private set
    private var currentVideo = false
    var muted by mutableStateOf(false); private set
    /** Where the sound goes (the earpiece, the speaker, wired headphones or a Bluetooth headset). */
    var route by mutableStateOf(CallRouteKind.EARPIECE); private set
    val speaker: Boolean get() = route == CallRouteKind.SPEAKER
    /** "Audio now on Speaker" for two seconds after the route changes during a call. */
    var routeToast by mutableStateOf<String?>(null); private set
    /** The call is a video call (it may start as voice and turn to video). */
    var video by mutableStateOf(false); private set
    /** My camera is on (the person's choice; it may still be held by another app). */
    var cameraOn by mutableStateOf(true); private set
    var cameraHeld by mutableStateOf(false); private set
    var remoteMuted by mutableStateOf(false); private set
    var remoteCameraOn by mutableStateOf(true); private set
    private var remoteReceiving by mutableStateOf(false)
    /** The other person's picture is on the screen (their camera is on and their video is arriving), otherwise their avatar. */
    val remoteVideoShowing: Boolean get() = callRemoteVideoShowing(video, remoteCameraOn, remoteReceiving)
    val hasLocalVideo: Boolean get() = media?.hasLocalVideo == true
    private var renegotiating = false
    private var speakerWanted = false
    private var toastJob: Job? = null
    var emoji by mutableStateOf<List<CallEmoji>>(emptyList()); private set
    /** Something to tell the person after a call went wrong (shown by the app). */
    var notice by mutableStateOf<String?>(null)

    private var media: CallMedia? = null
    private var localFingerprint: String? = null
    private var remoteFingerprint: String? = null
    private val outbound = mutableListOf<RemoteCandidate>()
    private val pendingRemote = mutableListOf<RemoteCandidate>()
    private var batcher: Job? = null
    private var currentCall = ""
    private var currentName = ""

    private val events = object : CallMediaEvents {
        override fun onLocalCandidate(sdp: String, mid: String?, index: Int) {
            scope.launch {
                outbound += RemoteCandidate(sdp, mid, index)
                if (batcher == null) batcher = scope.launch {
                    delay(1_000)
                    val items = outbound.toList(); outbound.clear(); batcher = null
                    sendIce(items)
                }
            }
        }
        override fun onControlOpen() { scope.launch { sendState() } }
        override fun onControl(text: String) { scope.launch { handleControl(text) } }
        override fun onRemoteVideo(receiving: Boolean) { scope.launch { remoteReceiving = receiving } }
        override fun onCameraInterrupted(held: Boolean) {
            scope.launch {
                if (!inCall) return@launch
                cameraHeld = held
                media?.setVideo(sending()); sendState()
            }
        }
        override fun onConnection(up: Boolean) {
            scope.launch {
                if (up) { driver.dispatch(CallMachineEvent.MediaUp); return@launch }
                // The connection failing is often the other phone hanging up: look in the mailbox for its call.end before calling the call failed.
                val core = store(); val link = transport()
                if (core != null && link != null) {
                    withContext(Dispatchers.IO) { runCatching { core.sync(link, token()) } }
                    driver.handleArrivals()
                }
                if (inCall) driver.dispatch(CallMachineEvent.MediaFailed)
            }
        }
    }

    private val port = object : CallMediaPort {
        override fun startOutgoing(callId: String, video: Boolean) { currentCall = callId; place(callId, video) }
        override fun showIncoming(callId: String, name: String, video: Boolean) {
            currentCall = callId; currentName = name; currentVideo = video
            if (foreground()) audio.startRinging() else audio.postIncoming(callId, name, video)
        }
        override fun acceptIncoming(callId: String, offerSdp: String, video: Boolean) { audio.stopRinging(); audio.cancelIncoming(); answerCall(callId, offerSdp) }
        override fun applyAnswer(callId: String, answerSdp: String) {
            remoteFingerprint = callFingerprint(answerSdp)
            scope.launch {
                try { media?.apply(answerSdp) } catch (e: Exception) { driver.dispatch(CallMachineEvent.AnswerApplyFailed) }
            }
        }
        // Candidates that arrive while the call is still ringing (the media starts when it is answered) wait for the media.
        override fun remoteCandidates(callId: String, list: List<RemoteCandidate>) { val m = media; if (m != null) m.add(list) else pendingRemote += list }
        override fun startRingback() = audio.startRingback()
        override fun stopRingback() = audio.stopRingback()
        override fun stopRinging() { audio.stopRinging(); audio.cancelIncoming() }
        override fun tearDown(callId: String) { closeMedia() }
    }

    val driver: CallDriver = CallDriver(store, transport, token, myId, scope, nameOf, onLogged = onLogged, media = port, announce = announce, timerScale = timerScale, sender = opSender?.let { s -> { a -> s(a.peerId, a.op, JSONObject().put("call_id", a.callId).also { o -> a.reason?.let { r -> o.put("reason", r) } }) } })

    val phase: CallPhaseKind get() = driver.state.phase
    val inCall: Boolean get() = phase != CallPhaseKind.IDLE

    // ---- what the person does

    /** Calls someone by voice (the microphone permission has been asked for by now). */
    fun call(peerId: String, name: String, video: Boolean = false) {
        if (inCall) return
        currentName = name
        driver.dispatch(CallMachineEvent.TapCall(newCallId(), peerId, name, video))
    }

    /** lime came to the front or left it while a call is ringing: the call screen rings in front, the notification behind. */
    fun appForeground(front: Boolean) {
        if (phase != CallPhaseKind.INCOMING) return
        if (front) { audio.cancelIncoming(); audio.startRinging() } else { audio.stopRinging(); audio.postIncoming(driver.state.callId, driver.state.peerName.ifEmpty { currentName }, driver.state.video) }
    }

    fun minimize() { if (inCall && phase != CallPhaseKind.INCOMING) { minimized = true; announce("Call minimised") } }
    fun restore() { minimized = false }

    fun answer() = driver.dispatch(CallMachineEvent.TapAnswer)
    fun decline() = driver.dispatch(CallMachineEvent.TapDecline)
    fun hangUp() = driver.dispatch(CallMachineEvent.TapHangUp)

    fun toggleMute() { muted = !muted; media?.setMuted(muted); sendState() }
    fun toggleSpeaker() { speakerWanted = !speaker; audio.setSpeaker(speakerWanted); refreshRoute(announce = false) }

    /** The route picker: the sound goes to this route (the speaker is the person's choice; any other is "the best of the rest"). */
    fun chooseRoute(kind: CallRouteKind) {
        speakerWanted = kind == CallRouteKind.SPEAKER
        audio.choose(kind)
        refreshRoute(announce = false)
    }

    /** The phone's audio devices changed (a permission was granted): the route is chosen again from what is there. */
    fun audioRoutesChanged() { if (inCall) { if (!speakerWanted) audio.setSpeaker(false); refreshRoute(announce = true) } }

    /** lime went to the background (or came back): the camera is held, as another app's use of it is, and the other side is told. */
    fun setBackgrounded(away: Boolean) {
        if (!inCall || !hasLocalVideo) return
        cameraHeld = away
        media?.setVideo(sending())
        if (!away) media?.restartCamera()
        sendState()
    }

    /** The routes this phone has now (for the picker). */
    fun routes(): List<CallRouteKind> = audio.available()

    private fun refreshRoute(announce: Boolean) {
        val before = route
        route = audio.current()
        updateProximity()
        if (announce && route != before && inCall) {
            val words = callRouteToast(route)
            routeToast = words; announce(words)
            toastJob?.cancel(); toastJob = scope.launch { delay(2_000); routeToast = null }
        }
    }

    private fun updateProximity() { audio.setProximity(inCall && callProximityOn(video, route)) }

    /** Where my camera's picture goes (the small tile) and where the other person's goes; the call screen's views set and clear these. */
    fun attachLocal(sink: VideoSink?) { media?.attachLocal(sink); localSink = sink }
    fun attachRemote(sink: VideoSink?) { media?.attachRemote(sink); remoteSink = sink }
    private var localSink: VideoSink? = null
    private var remoteSink: VideoSink? = null

    fun toggleCamera() {
        val m = media ?: return
        if (!m.hasLocalVideo) { scope.launch { startVideo() }; return }
        cameraOn = !cameraOn
        m.setVideo(sending()); sendState()
    }
    fun flipCamera() { media?.flipCamera() }

    private fun sending() = callCameraSending(video, media?.hasLocalVideo == true, cameraOn, cameraHeld)

    // ---- the in-call control channel (iOS `lime-ctl`): my state, and the renegotiation that turns a voice call into video

    /** My microphone and camera state, sent once the channel opens and on every change. */
    fun sendState() { if (inCall) media?.sendControl(callControlState(muted, sending())) }

    private fun control(sdp: String, offer: Boolean): Boolean {
        val text = callControlDescription(offer, sdp) ?: return false
        return media?.sendControl(text) == true
    }

    /** Adds my camera and tells the other side. A voice call becomes a video call (the one call, recorded as video). */
    suspend fun startVideo() {
        val m = media ?: return
        if (phase != CallPhaseKind.ACTIVE || renegotiating) return
        val id = driver.state.callId
        try {
            m.addLocalVideo()
            renegotiating = true
            val sdp = m.renegotiationOffer()
            if (driver.state.callId != id) return
            if (!control(sdp, offer = true)) { renegotiating = false; return }
            cameraOn = true; makeVideo()
            sendState()
        } catch (e: Exception) { renegotiating = false }
    }

    /** The call is video now: the screen turns to video and the sound moves to the speaker (as iOS). */
    private fun makeVideo() {
        if (!video) { video = true; speakerWanted = callSpeakerByDefault(true); audio.setSpeaker(speakerWanted); refreshRoute(announce = false); driver.markVideo() }
    }

    suspend fun handleControl(text: String) {
        if (!inCall) return
        when (val message = parseCallControl(text)) {
            is CallControlMessage.State -> {
                message.muted?.let { remoteMuted = it }
                message.camera?.let { remoteCameraOn = it }
            }
            is CallControlMessage.Offer -> receivedOffer(message.sdp)
            is CallControlMessage.Answer -> receivedAnswer(message.sdp)
            CallControlMessage.Ignored -> {}
        }
    }

    private suspend fun receivedOffer(sdp: String) {
        val m = media ?: return
        when (callRenegotiationOffer(phase == CallPhaseKind.ACTIVE, sdp, remoteFingerprint, renegotiating, myId().orEmpty(), driver.state.peerId)) {
            RenegotiationVerdict.KEY_CHANGED -> { driver.dispatch(CallMachineEvent.MediaFailed); return }
            RenegotiationVerdict.GLARE, RenegotiationVerdict.IGNORE -> return
            RenegotiationVerdict.ACCEPT -> {}
        }
        val id = driver.state.callId
        try {
            val answer = m.accept(sdp)
            if (driver.state.callId != id) return
            renegotiating = false
            if (!control(answer, offer = false)) return
            if (!video) makeVideo()
            if (!m.hasLocalVideo) cameraOn = false
            sendState()
        } catch (e: Exception) {}
    }

    private suspend fun receivedAnswer(sdp: String) {
        val m = media ?: return
        when (callRenegotiationAnswer(phase == CallPhaseKind.ACTIVE, renegotiating, sdp, remoteFingerprint)) {
            RenegotiationVerdict.KEY_CHANGED -> { driver.dispatch(CallMachineEvent.MediaFailed); return }
            RenegotiationVerdict.GLARE, RenegotiationVerdict.IGNORE -> return
            RenegotiationVerdict.ACCEPT -> {}
        }
        try { m.apply(sdp) } catch (e: Exception) {}
        renegotiating = false
    }

    /** What arrived from the other phone since the last sync. */
    fun handleArrivals() = driver.handleArrivals()

    // ---- the media

    private fun newCallId(): String = java.util.UUID.randomUUID().toString().lowercase()

    private suspend fun iceServers(): List<CallIceServer> {
        val core = store() ?: return emptyList()
        val link = transport() ?: return emptyList()
        val servers = runCatching { withContext(Dispatchers.IO) { core.fetchTurnServers(link, token()) } }.getOrNull() ?: return emptyList()
        return listOf(CallIceServer(servers.urls, servers.username, servers.credential))
    }

    private fun begin(): CallMedia? {
        // "Always relay calls" is a Privacy setting iOS has; Android has not built it, so a call may go direct.
        if (!callRelayAllowed(false, true)) { notice = callRelayUnavailableWords(); return null }
        val carried = pendingRemote.toList()
        closeMedia()
        val m = mediaFactory(events)
        media = m
        if (carried.isNotEmpty()) m.add(carried)
        video = driver.state.video
        muted = false; emoji = emptyList(); localFingerprint = null; remoteFingerprint = null
        cameraOn = true; cameraHeld = false; remoteMuted = false; remoteCameraOn = true; remoteReceiving = false; renegotiating = false
        speakerWanted = callSpeakerByDefault(video)
        val camera = cameraAllowed()
        if (video && !camera) cameraOn = false
        m.configure(video, camera, lowData())
        audio.onRoutesChanged = { scope.launch { refreshRoute(announce = true) } }
        audio.start(speaker = speakerWanted)
        refreshRoute(announce = false)
        m.attachLocal(localSink); m.attachRemote(remoteSink)
        if (useService) CallService.start(context, currentName)
        return m
    }

    private fun place(callId: String, video: Boolean) {
        scope.launch {
            try {
                val m = begin() ?: run { driver.dispatch(CallMachineEvent.RelayUnavailable); return@launch }
                m.start(iceServers(), relayOnly = false)
                val sdp = m.makeOffer()
                val fingerprint = callFingerprint(sdp) ?: error("no fingerprint")
                localFingerprint = fingerprint
                val peer = driver.state.peerId
                val ok = send(peer, "call.offer", JSONObject().put("call_id", callId).put("video", video).put("sdp", sdp).put("fingerprint", fingerprint))
                if (ok) driver.dispatch(CallMachineEvent.OfferSent) else driver.dispatch(CallMachineEvent.OfferFailed)
            } catch (e: Exception) {
                driver.dispatch(CallMachineEvent.OfferFailed)
            }
        }
    }

    private fun answerCall(callId: String, offerSdp: String) {
        scope.launch {
            try {
                val m = begin() ?: run { driver.dispatch(CallMachineEvent.AnswerFailed); return@launch }
                remoteFingerprint = callFingerprint(offerSdp)
                m.start(iceServers(), relayOnly = false)
                val sdp = m.accept(offerSdp)
                val fingerprint = callFingerprint(sdp) ?: error("no fingerprint")
                localFingerprint = fingerprint
                val peer = driver.state.peerId
                val ok = send(peer, "call.answer", JSONObject().put("call_id", callId).put("sdp", sdp).put("fingerprint", fingerprint))
                if (ok) driver.dispatch(CallMachineEvent.AnswerSent) else driver.dispatch(CallMachineEvent.AnswerFailed)
            } catch (e: Exception) {
                driver.dispatch(CallMachineEvent.AnswerFailed)
            }
        }
    }

    private suspend fun send(peer: String, op: String, payload: JSONObject): Boolean {
        opSender?.let { return it(peer, op, payload) }
        val core = store() ?: return false
        val link = transport() ?: return false
        return withContext(Dispatchers.IO) { runCatching { core.sendCallSignal(link, token(), peer, op, payload.toString()) }.isSuccess }
    }

    private suspend fun sendIce(items: List<RemoteCandidate>) {
        if (items.isEmpty() || !inCall) return
        val list = org.json.JSONArray().also { a -> items.forEach { a.put(JSONObject().put("candidate", it.sdp).put("sdpMLineIndex", it.index).also { o -> if (it.mid != null) o.put("sdpMid", it.mid) }) } }
        send(driver.state.peerId, "call.ice", JSONObject().put("call_id", driver.state.callId).put("candidates", list))
    }

    /** The four emoji both people compare once the call is up: the caller's key is the one in the offer, the callee's the one in the answer. */
    fun updateEmoji() {
        val local = localFingerprint ?: return
        val remote = remoteFingerprint ?: return
        val outgoing = driver.state.outgoing
        emoji = callEmoji(driver.state.callId, if (outgoing) local else remote, if (outgoing) remote else local)
    }

    private fun closeMedia() {
        media?.close(); media = null
        renegotiating = false; remoteReceiving = false
        batcher?.cancel(); batcher = null; outbound.clear(); pendingRemote.clear()
        audio.stop()
        if (useService) CallService.stop(context)
    }

    /** A preview/test seam: shows these emoji (a real call computes them from the two fingerprints). */
    internal fun showEmojiForTest(list: List<CallEmoji>) { emoji = list }

    /** What the call received so far (a media proof and the diagnostics). */
    suspend fun inboundAudio(): InboundAudio? = media?.inboundAudio()
    suspend fun videoStats(): VideoStats? = media?.videoStats()

    init {
        driver.onPhase = { before, after ->
            if (after == CallPhaseKind.ACTIVE && before != CallPhaseKind.ACTIVE) updateEmoji()
            if (after == CallPhaseKind.IDLE) { minimized = false; emoji = emptyList(); muted = false; video = false; remoteMuted = false; routeToast = null; speakerWanted = false; route = CallRouteKind.EARPIECE; audio.onRoutesChanged = null; updateProximity() }
            if (before == CallPhaseKind.INCOMING && after != CallPhaseKind.INCOMING) { audio.stopRinging(); audio.cancelIncoming() }
        }
    }
}

/** The media of one call (the WebRTC peer connection; tests give a fake). */
interface CallMedia {
    fun start(servers: List<CallIceServer>, relayOnly: Boolean)
    suspend fun makeOffer(): String
    suspend fun accept(offer: String): String
    suspend fun apply(answer: String)
    fun add(candidates: List<RemoteCandidate>)
    fun setMuted(on: Boolean)
    suspend fun inboundAudio(): InboundAudio?
    fun close()
    /** Before `start`: whether this is a video call and Low Data Mode is on. */
    fun configure(video: Boolean, camera: Boolean, lowData: Boolean) {}
    val hasLocalVideo: Boolean get() = false
    fun sendControl(text: String): Boolean = false
    fun addLocalVideo() {}
    suspend fun renegotiationOffer(): String = ""
    fun setVideo(on: Boolean) {}
    fun flipCamera() {}
    fun restartCamera() {}
    fun attachLocal(sink: VideoSink?) {}
    fun attachRemote(sink: VideoSink?) {}
    suspend fun videoStats(): VideoStats? = null
}

private class RealCallMedia(context: Context, events: CallMediaEvents) : CallMedia {
    private val media = WebRtcCallMedia(context, events)
    private var video = false
    private var camera = false
    private var lowData = false
    override fun configure(video: Boolean, camera: Boolean, lowData: Boolean) { this.video = video; this.camera = camera; this.lowData = lowData }
    override fun start(servers: List<CallIceServer>, relayOnly: Boolean) = media.start(servers, relayOnly, video, camera, lowData)
    override val hasLocalVideo: Boolean get() = media.hasLocalVideo
    override fun sendControl(text: String) = media.sendControl(text)
    override fun addLocalVideo() = media.addLocalVideo()
    override suspend fun renegotiationOffer() = media.renegotiationOffer()
    override fun setVideo(on: Boolean) = media.setVideo(on)
    override fun flipCamera() = media.flipCamera()
    override fun restartCamera() = media.restartCamera()
    override fun attachLocal(sink: VideoSink?) = media.attachLocal(sink)
    override fun attachRemote(sink: VideoSink?) = media.attachRemote(sink)
    override suspend fun videoStats() = media.videoStats()
    override suspend fun makeOffer() = media.makeOffer()
    override suspend fun accept(offer: String) = media.accept(offer)
    override suspend fun apply(answer: String) = media.apply(answer)
    override fun add(candidates: List<RemoteCandidate>) = media.add(candidates)
    override fun setMuted(on: Boolean) = media.setMuted(on)
    override suspend fun inboundAudio() = media.inboundAudio()
    override fun close() = media.close()
}

/** The phone's audio for a call (tests give a silent one). */
interface CallAudioPort {
    fun start(speaker: Boolean)
    fun setSpeaker(on: Boolean)
    fun stop()
    fun startRingback()
    fun stopRingback()
    fun startRinging()
    fun stopRinging()
    fun available(): List<CallRouteKind> = listOf(CallRouteKind.EARPIECE, CallRouteKind.SPEAKER)
    fun current(): CallRouteKind = CallRouteKind.EARPIECE
    fun choose(kind: CallRouteKind) { setSpeaker(kind == CallRouteKind.SPEAKER) }
    fun setProximity(on: Boolean) {}
    /** The incoming call as a notification (lime is not in front), and taking it away. */
    fun postIncoming(callId: String, name: String, video: Boolean) {}
    fun cancelIncoming() {}
    var onRoutesChanged: (() -> Unit)?
        get() = null
        set(value) {}
}

private class RealCallAudio(context: Context) : CallAudioPort {
    private val audio = CallAudio(context)
    override fun start(speaker: Boolean) = audio.start(speaker)
    override fun setSpeaker(on: Boolean) = audio.setSpeaker(on)
    override fun stop() = audio.stop()
    override fun startRingback() = audio.startRingback()
    override fun stopRingback() = audio.stopRingback()
    override fun startRinging() = audio.startRinging()
    override fun stopRinging() = audio.stopRinging()
    override fun available() = audio.available()
    override fun current() = audio.current()
    override fun choose(kind: CallRouteKind) = audio.choose(kind)
    override fun setProximity(on: Boolean) = audio.setProximity(on)
    private val appContext = context.applicationContext
    override fun postIncoming(callId: String, name: String, video: Boolean) = IncomingCallNotifier.post(appContext, callId, name, video)
    override fun cancelIncoming() = IncomingCallNotifier.cancel(appContext)
    override var onRoutesChanged: (() -> Unit)?
        get() = audio.onRoutesChanged
        set(value) { audio.onRoutesChanged = value }
}
