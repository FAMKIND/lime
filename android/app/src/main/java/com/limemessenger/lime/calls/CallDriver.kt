package com.limemessenger.lime.calls

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
import uniffi.lime_core.CallMachineAction
import uniffi.lime_core.CallMachineEvent
import uniffi.lime_core.CallPhaseKind
import uniffi.lime_core.CallQuietKind
import uniffi.lime_core.CallTimerKind
import uniffi.lime_core.LimeStore
import uniffi.lime_core.callMachineNew
import uniffi.lime_core.callMachineStep
import uniffi.lime_core.callQuietParse

/** What a call needs from the media layer: each method does its part and then tells the driver how it went (`CallSession` implements it with WebRTC). */
interface CallMediaPort {
    /** Ice servers, media, offer, `call.offer` out; then `OfferSent` or `OfferFailed`. */
    fun startOutgoing(callId: String, video: Boolean) {}
    /** An incoming call is shown: ring. (The caller is told once the screen is up: `RingShown`.) */
    fun showIncoming(callId: String, name: String, video: Boolean) {}
    /** Ice servers, media, answer, `call.answer` out; then `AnswerSent` or `AnswerFailed`. */
    fun acceptIncoming(callId: String, offerSdp: String, video: Boolean) {}
    /** The other phone answered: apply its answer; `AnswerApplyFailed` if that fails. */
    fun applyAnswer(callId: String, answerSdp: String) {}
    /** Candidates from the other phone for the call that is going. */
    fun remoteCandidates(callId: String, list: List<RemoteCandidate>) {}
    fun startRingback() {}
    fun stopRingback() {}
    fun stopRinging() {}
    /** Close the media, the route and the foreground service. */
    fun tearDown(callId: String) {}
}

/** No media (LIME-424): signalling and history only. */
object NoMedia : CallMediaPort

/**
 * The thin driver of the core's 1:1 call machine (`call_rules.rs`, LIME-423): it feeds the machine what happens (taps, call ops from the other phone, media news,
 * timers) and carries out the actions it returns: send an op (`send_call_signal`), write the history (`call_history_add`), arm and cancel timers, and the media's
 * part through [CallMediaPort]. Everything that is a rule is the core's; this class only does what the machine asks. All calls come on the main thread.
 */
class CallDriver(
    private val store: () -> LimeStore?,
    private val transport: () -> HttpTransport?,
    private val token: suspend () -> String,
    private val myId: () -> String?,
    private val scope: CoroutineScope,
    private val nameOf: (String) -> String = { it },
    private val now: () -> Long = System::currentTimeMillis,
    /** Why this phone must not ring now (Do Not Disturb or outside work hours), or null. */
    private val quiet: () -> CallQuietKind? = { null },
    /** A call was written to the history (the chat shows it as a message, so the app reloads). */
    private val onLogged: () -> Unit = {},
    private val media: CallMediaPort = NoMedia,
    /** The words to say aloud (a TalkBack live region). */
    private val announce: (String) -> Unit = {},
    /** Scales the machine's timers (tests run them in a fraction of the time); 1.0 in the app. */
    private val timerScale: Double = 1.0,
    /** Where the machine's `Send` actions go (tests capture them); null sends through the core. */
    private val sender: ((CallMachineAction.Send) -> Unit)? = null,
) {
    var state by mutableStateOf(callMachineNew())
        private set
    /** Told when the phase changes (the session keeps the emoji and the audio in step). */
    var onPhase: ((CallPhaseKind, CallPhaseKind) -> Unit)? = null
    private val timers = mutableMapOf<CallTimerKind, Job>()
    private val offers = mutableMapOf<String, String>()
    private val answers = mutableMapOf<String, String>()
    /** Candidates that arrived before their offer (the mailbox does not keep the order), by call id. */
    private val early = mutableMapOf<String, MutableList<RemoteCandidate>>()

    fun dispatch(event: CallMachineEvent) {
        val before = state.phase
        val step = callMachineStep(state, event, now())
        state = step.state
        // The other phone is told before the media is torn down: closing the connection first makes it see a failure (and log "failed") a moment before the hang-up arrives.
        step.actions.sortedBy { if (it is CallMachineAction.TearDown) 1 else 0 }.forEach(::run)
        if (before == CallPhaseKind.INCOMING && state.phase != CallPhaseKind.INCOMING) media.stopRinging()
        if (before != state.phase) onPhase?.invoke(before, state.phase)
    }

    private fun run(action: CallMachineAction) {
        when (action) {
            is CallMachineAction.StartOutgoing -> media.startOutgoing(state.callId, state.video)
            is CallMachineAction.ShowIncoming -> { media.showIncoming(state.callId, state.peerName, state.video); dispatch(CallMachineEvent.RingShown) }
            is CallMachineAction.AcceptIncoming -> media.acceptIncoming(state.callId, offers[state.callId].orEmpty(), state.video)
            is CallMachineAction.ApplyAnswer -> media.applyAnswer(state.callId, answers[state.callId].orEmpty())
            is CallMachineAction.Send -> send(action)
            is CallMachineAction.StartRingback -> media.startRingback()
            is CallMachineAction.StopRingback -> media.stopRingback()
            is CallMachineAction.StartPolling, is CallMachineAction.StopPolling -> {}
            is CallMachineAction.ArmTimer -> {
                timers.remove(action.kind)?.cancel()
                timers[action.kind] = scope.launch { delay((action.seconds * 1000 * timerScale).toLong()); timers.remove(action.kind); dispatch(CallMachineEvent.Timer(action.kind)) }
            }
            is CallMachineAction.CancelTimer -> timers.remove(action.kind)?.cancel()
            is CallMachineAction.Announce -> announce(action.words)
            is CallMachineAction.Log -> scope.launch {
                val core = store() ?: return@launch
                withContext(Dispatchers.IO) { runCatching { core.callHistoryAdd(CallsModel.toRecord(action.entry)) } }
                onLogged()
            }
            is CallMachineAction.TearDown -> { val id = state.callId.ifEmpty { lastCallId }; media.tearDown(id); offers.remove(id); answers.remove(id) }
        }
    }

    private var lastCallId = ""

    private fun send(action: CallMachineAction.Send) {
        sender?.let { it(action); return }
        val core = store() ?: return
        val link = transport() ?: return
        val payload = JSONObject().put("call_id", action.callId).also { if (action.reason != null) it.put("reason", action.reason) }.toString()
        scope.launch {
            withContext(Dispatchers.IO) {
                runCatching { core.sendCallSignal(link, token(), action.peerId, action.op, payload) }
            }
        }
    }

    /** What arrived from the other phone since the last time: the call ops the core queued, handled one at a time and in order. */
    fun handleArrivals() {
        val core = store() ?: return
        val events = runCatching { core.takeCallEvents() }.getOrNull().orEmpty()
        for (event in events) handle(event.op, event.callId, event.peer, runCatching { JSONObject(event.payload) }.getOrNull() ?: JSONObject())
    }

    /** One incoming op (also the entry for tests that feed ops directly). */
    fun handle(op: String, callId: String, peer: String, payload: JSONObject) {
        lastCallId = if (callId.isNotEmpty()) callId else lastCallId
        when (op) {
            "call.offer" -> {
                payload.optString("sdp").takeIf { it.isNotEmpty() }?.let { offers[callId] = it }
                dispatch(CallMachineEvent.OfferReceived(callId, peer, nameOf(peer), payload.optBoolean("video", false), myId().orEmpty(), quiet()))
                // Candidates that came first belong to this call.
                if (state.callId == callId) early.remove(callId)?.let { media.remoteCandidates(callId, it) }
            }
            "call.ringing" -> dispatch(CallMachineEvent.SignalRinging(callId, peer))
            "call.answer" -> {
                payload.optString("sdp").takeIf { it.isNotEmpty() }?.let { answers[callId] = it }
                dispatch(CallMachineEvent.SignalAnswer(callId, peer))
            }
            "call.end" -> dispatch(CallMachineEvent.SignalEnd(callId, peer))
            "call.decline" -> dispatch(CallMachineEvent.SignalDecline(callId, peer))
            "call.busy" -> dispatch(CallMachineEvent.SignalBusy(callId, peer))
            "call.unavailable" -> callQuietParse(payload.optString("reason"))?.let { dispatch(CallMachineEvent.SignalUnavailable(callId, peer, it)) }
            "call.ice" -> {
                val list = candidatesIn(payload)
                if (list.isEmpty()) return
                if (state.callId == callId && state.peerId == peer && state.phase != CallPhaseKind.IDLE) media.remoteCandidates(callId, list)
                else {
                    // Before its offer has been handled (or while this phone is on another call) a candidate is kept, not dropped.
                    early.getOrPut(callId) { mutableListOf() } += list
                    if (early.size > 4) early.keys.firstOrNull { it != callId }?.let { early.remove(it) }
                }
            }
        }
    }

    private fun candidatesIn(payload: JSONObject): List<RemoteCandidate> {
        payload.optJSONArray("candidates")?.let { array ->
            return (0 until array.length()).mapNotNull { i -> array.optJSONObject(i)?.let { o -> o.optString("candidate").takeIf { it.isNotEmpty() }?.let { RemoteCandidate(it, o.optString("sdpMid").ifEmpty { null }, o.optInt("sdpMLineIndex", 0)) } } }
        }
        val single = payload.optString("candidate")
        return if (single.isEmpty()) emptyList() else listOf(RemoteCandidate(single, payload.optString("sdpMid").ifEmpty { null }, payload.optInt("sdpMLineIndex", 0)))
    }

    fun reset() { timers.values.forEach { it.cancel() }; timers.clear(); state = callMachineNew() }
}
