package com.limemessenger.lime.calls

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.CallHistoryRecord
import uniffi.lime_core.CallLogEntry
import uniffi.lime_core.CallResult
import uniffi.lime_core.LimeStore
import uniffi.lime_core.callResultParse
import uniffi.lime_core.callResultRaw
import uniffi.lime_core.callResultIsMissed

/** Which calls the Calls tab lists beyond All | Missed (iOS `CallFilter`): the kind and the direction. */
// ANDROID DEBT: iOS's `CallFilter` is Swift (`Model/`); the rule is three comparisons, so it is kept here until a brief moves it to the core.
data class CallFilter(val video: Boolean? = null, val incoming: Boolean? = null) {
    val activeCount: Int get() = listOfNotNull(video, incoming).size
    val isOn: Boolean get() = activeCount > 0

    fun apply(records: List<CallLogEntry>, missedOnly: Boolean): List<CallLogEntry> = records.filter { r ->
        (!missedOnly || (!r.outgoing && callResultIsMissed(r.result))) &&
            (video == null || r.video == video) &&
            (incoming == null || r.outgoing != incoming)
    }
}

/**
 * The calls on this phone (at most 500, newest first), kept in the encrypted core store (`call_history`): the Calls tab and the missed badge read them here.
 * Every rule (outcomes, words, grouping, what tapping does) is the core's `call_rules.rs`.
 */
class CallsModel(private val store: () -> LimeStore?) {
    var records by mutableStateOf<List<CallLogEntry>>(emptyList())
        private set
    /** Missed incoming calls not yet seen: the Call tab's badge. */
    var missedUnseen by mutableIntStateOf(0)
        private set
    var missedOnly by mutableStateOf(false)
    var filter by mutableStateOf(CallFilter())
    var isLoaded by mutableStateOf(false)
        private set

    val shown: List<CallLogEntry> get() = filter.apply(records, missedOnly)

    suspend fun reload() {
        val core = store() ?: return
        val (list, unseen) = withContext(Dispatchers.IO) {
            runCatching { core.callHistoryList().map(::toEntry) to core.callHistoryMissedUnseenCount().toInt() }.getOrNull()
        } ?: return
        records = list
        missedUnseen = unseen
        isLoaded = true
    }

    suspend fun add(entry: CallLogEntry) {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.callHistoryAdd(toRecord(entry)) } }
        reload()
    }

    suspend fun delete(ids: List<String>) {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.callHistoryDelete(ids) } }
        reload()
    }

    suspend fun clear() {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.callHistoryClear() } }
        reload()
    }

    /** The Call tab was opened. */
    suspend fun markMissedSeen() {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.callHistoryMarkMissedSeen() } }
        reload()
    }

    fun recordsWith(peerId: String): List<CallLogEntry> = records.filter { it.peerId == peerId }

    companion object {
        fun toEntry(r: CallHistoryRecord) = CallLogEntry(
            id = r.id, peerId = r.peer, peerName = r.peerName, video = r.video, outgoing = r.outgoing, atMs = r.atMs, durationMs = r.durationMs,
            result = callResultParse(r.outcome) ?: CallResult.FAILED,
        )

        fun toRecord(e: CallLogEntry) = CallHistoryRecord(
            id = e.id, peer = e.peerId, peerName = e.peerName, video = e.video, outgoing = e.outgoing, atMs = e.atMs, durationMs = e.durationMs, outcome = callResultRaw(e.result),
        )
    }
}
