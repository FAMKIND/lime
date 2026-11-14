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
import uniffi.lime_core.CallEmoji
import uniffi.lime_core.CallMachineEvent
import uniffi.lime_core.CallPhaseKind
import uniffi.lime_core.LimeStore
import uniffi.lime_core.callEmoji
import uniffi.lime_core.callFingerprint
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
    myId: () -> String?,
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
) {
    var muted by mutableStateOf(false); private set
    var speaker by mutableStateOf(false); private set
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
        override fun showIncoming(callId: String, name: String, video: Boolean) { currentCall = callId; currentName = name; audio.startRinging() }
        override fun acceptIncoming(callId: String, offerSdp: String, video: Boolean) { audio.stopRinging(); answerCall(callId, offerSdp) }
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
        override fun stopRinging() = audio.stopRinging()
        override fun tearDown(callId: String) { closeMedia() }
    }

    val driver: CallDriver = CallDriver(store, transport, token, myId, scope, nameOf, onLogged = onLogged, media = port, announce = announce, timerScale = timerScale, sender = opSender?.let { s -> { a -> s(a.peerId, a.op, JSONObject().put("call_id", a.callId).also { o -> a.reason?.let { r -> o.put("reason", r) } }) } })

    val phase: CallPhaseKind get() = driver.state.phase
    val inCall: Boolean get() = phase != CallPhaseKind.IDLE

    // ---- what the person does

    /** Calls someone by voice (the microphone permission has been asked for by now). */
    fun call(peerId: String, name: String) {
        if (inCall) return
        currentName = name
        driver.dispatch(CallMachineEvent.TapCall(newCallId(), peerId, name, false))
    }

    fun answer() = driver.dispatch(CallMachineEvent.TapAnswer)
    fun decline() = driver.dispatch(CallMachineEvent.TapDecline)
    fun hangUp() = driver.dispatch(CallMachineEvent.TapHangUp)

    fun toggleMute() { muted = !muted; media?.setMuted(muted) }
    fun toggleSpeaker() { speaker = !speaker; audio.setSpeaker(speaker) }

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
        muted = false; speaker = false; emoji = emptyList(); localFingerprint = null; remoteFingerprint = null
        audio.start(speaker = false)
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
        batcher?.cancel(); batcher = null; outbound.clear(); pendingRemote.clear()
        audio.stop()
        if (useService) CallService.stop(context)
    }

    /** A preview/test seam: shows these emoji (a real call computes them from the two fingerprints). */
    internal fun showEmojiForTest(list: List<CallEmoji>) { emoji = list }

    /** What the call received so far (a media proof and the diagnostics). */
    suspend fun inboundAudio(): InboundAudio? = media?.inboundAudio()

    init {
        driver.onPhase = { before, after ->
            if (after == CallPhaseKind.ACTIVE && before != CallPhaseKind.ACTIVE) updateEmoji()
            if (after == CallPhaseKind.IDLE) { emoji = emptyList(); muted = false; speaker = false }
            if (before == CallPhaseKind.INCOMING && after != CallPhaseKind.INCOMING) audio.stopRinging()
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
}

private class RealCallMedia(context: Context, events: CallMediaEvents) : CallMedia {
    private val media = WebRtcCallMedia(context, events)
    override fun start(servers: List<CallIceServer>, relayOnly: Boolean) = media.start(servers, relayOnly)
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
}
