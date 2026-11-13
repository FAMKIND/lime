package com.limemessenger.lime

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.CallMachineAction
import uniffi.lime_core.CallMachineEvent
import uniffi.lime_core.CallPhaseKind
import uniffi.lime_core.CallResult
import uniffi.lime_core.callMachineNew
import uniffi.lime_core.callMachineStep
import uniffi.lime_core.callStatusText

/**
 * LIME-423: one 1:1 call run through the Kotlin binding gives the same phases, actions and words as the Rust test
 * (`an_outgoing_call_rings_then_connects_and_logs_its_duration` in `core/src/call_rules.rs`).
 */
@RunWith(AndroidJUnit4::class)
class CallRulesBindingTest {
    private val t0 = 1_800_000_000_000L

    @Test fun anOutgoingCallRingsThenConnectsAndLogsItsDuration() {
        var s = callMachineStep(callMachineNew(), CallMachineEvent.TapCall("c1", "ben", "Ben", false), t0)
        assertEquals(CallPhaseKind.OUTGOING, s.state.phase)
        assertTrue(s.actions.contains(CallMachineAction.StartOutgoing))
        assertEquals(listOf("Calling…"), s.actions.filterIsInstance<CallMachineAction.Announce>().map { it.words })
        s = callMachineStep(s.state, CallMachineEvent.OfferSent, t0 + 100)
        assertTrue(s.actions.contains(CallMachineAction.StartRingback))
        s = callMachineStep(s.state, CallMachineEvent.SignalRinging("c1", "ben"), t0 + 1_000)
        assertEquals("Ringing…", callStatusText(s.state, t0 + 1_000))
        s = callMachineStep(s.state, CallMachineEvent.SignalAnswer("c1", "ben"), t0 + 3_000)
        assertEquals(CallPhaseKind.CONNECTING, s.state.phase)
        assertTrue(s.actions.contains(CallMachineAction.ApplyAnswer))
        s = callMachineStep(s.state, CallMachineEvent.MediaUp, t0 + 4_000)
        assertEquals(CallPhaseKind.ACTIVE, s.state.phase)
        assertEquals("1:05", callStatusText(s.state, t0 + 4_000 + 65_000))
        s = callMachineStep(s.state, CallMachineEvent.TapHangUp, t0 + 4_000 + 65_000)
        assertEquals(CallPhaseKind.IDLE, s.state.phase)
        val log = s.actions.filterIsInstance<CallMachineAction.Log>().single().entry
        assertEquals(CallResult.COMPLETED, log.result)
        assertEquals(65_000L, log.durationMs)
        val sent = s.actions.filterIsInstance<CallMachineAction.Send>().single()
        assertEquals("call.end", sent.op)
        assertTrue(s.actions.contains(CallMachineAction.TearDown))
    }
}
