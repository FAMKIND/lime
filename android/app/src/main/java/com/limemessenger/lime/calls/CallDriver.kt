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
import uniffi.lime_core.CallMachineState
import uniffi.lime_core.CallQuietKind
import uniffi.lime_core.CallTimerKind
import uniffi.lime_core.LimeStore
import uniffi.lime_core.callMachineNew
import uniffi.lime_core.callMachineStep
import uniffi.lime_core.callQuietParse

/** What a call needs from the media layer (LIME-425 fills it with WebRTC): each method does its part and then tells the driver how it went. */
interface CallMediaPort {
    /** Ice servers, media, offer, `call.offer` out; then `OfferSent` or `OfferFailed`. */
    fun startOutgoing(video: Boolean) {}
    /** Ice servers, media, answer, `call.answer` out; then `AnswerSent` or `AnswerFailed`. */
    fun acceptIncoming() {}
    fun applyAnswer() {}
    fun startRingback() {}
    fun stopRingback() {}
    /** Close the media, the route and the foreground service. */
    fun tearDown() {}
}

/** No media (LIME-424): signalling and history only. */
object NoMedia : CallMediaPort

/**
 * The thin driver of the core's 1:1 call machine (`call_rules.rs`, LIME-423): it feeds the machine what happens (taps, call ops from the other phone, media news,
 * timers) and carries out the actions it returns: send an op (`send_call_signal`), write the history (`call_history_add`), arm and cancel timers. Everything that
 * is a rule is the core's; this class only does what the machine asks. All calls come on the main thread.
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
) {
    var state by mutableStateOf(callMachineNew())
        private set
    private val timers = mutableMapOf<CallTimerKind, Job>()

    fun dispatch(event: CallMachineEvent) {
        val step = callMachineStep(state, event, now())
        state = step.state
        step.actions.forEach(::run)
    }

    private fun run(action: CallMachineAction) {
        when (action) {
            is CallMachineAction.StartOutgoing -> media.startOutgoing(state.video)
            is CallMachineAction.ShowIncoming -> {}
            is CallMachineAction.AcceptIncoming -> media.acceptIncoming()
            is CallMachineAction.ApplyAnswer -> media.applyAnswer()
            is CallMachineAction.Send -> send(action)
            is CallMachineAction.StartRingback -> media.startRingback()
            is CallMachineAction.StopRingback -> media.stopRingback()
            is CallMachineAction.StartPolling, is CallMachineAction.StopPolling -> {}
            is CallMachineAction.ArmTimer -> {
                timers.remove(action.kind)?.cancel()
                timers[action.kind] = scope.launch { delay((action.seconds * 1000).toLong()); timers.remove(action.kind); dispatch(CallMachineEvent.Timer(action.kind)) }
            }
            is CallMachineAction.CancelTimer -> timers.remove(action.kind)?.cancel()
            is CallMachineAction.Announce -> announce(action.words)
            is CallMachineAction.Log -> scope.launch {
                val core = store() ?: return@launch
                withContext(Dispatchers.IO) { runCatching { core.callHistoryAdd(CallsModel.toRecord(action.entry)) } }
                onLogged()
            }
            is CallMachineAction.TearDown -> media.tearDown()
        }
    }

    private fun send(action: CallMachineAction.Send) {
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

    private fun handle(op: String, callId: String, peer: String, payload: JSONObject) {
        when (op) {
            "call.offer" -> dispatch(CallMachineEvent.OfferReceived(callId, peer, nameOf(peer), payload.optBoolean("video", false), myId().orEmpty(), quiet()))
            "call.ringing" -> dispatch(CallMachineEvent.SignalRinging(callId, peer))
            "call.answer" -> dispatch(CallMachineEvent.SignalAnswer(callId, peer))
            "call.end" -> dispatch(CallMachineEvent.SignalEnd(callId, peer))
            "call.decline" -> dispatch(CallMachineEvent.SignalDecline(callId, peer))
            "call.busy" -> dispatch(CallMachineEvent.SignalBusy(callId, peer))
            "call.unavailable" -> callQuietParse(payload.optString("reason"))?.let { dispatch(CallMachineEvent.SignalUnavailable(callId, peer, it)) }
            // call.ice goes to the media (LIME-425).
        }
    }

    fun reset() { timers.values.forEach { it.cancel() }; timers.clear(); state = callMachineNew() }

}
