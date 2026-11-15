package com.limemessenger.lime.calls

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.limemessenger.lime.net.HttpTransport
import io.livekit.android.LiveKit
import io.livekit.android.RoomOptions
import io.livekit.android.events.RoomEvent
import io.livekit.android.events.collect
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.track.Track
import io.livekit.android.room.track.VideoTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.lime_core.CallEmoji
import uniffi.lime_core.GroupCallEvent
import uniffi.lime_core.GroupCallInfo
import uniffi.lime_core.LimeStore

/** One person's tile in a group call. */
data class GroupTile(
    val participant: String, val userId: String, val name: String, val isMe: Boolean,
    val keyReady: Boolean, val muted: Boolean = false, val speaking: Boolean = false, val hasPicture: Boolean = false,
)

/** The media of a group call (LiveKit; tests give a fake). Every key goes in as raw bytes; nothing is sent in the clear. */
interface GroupMedia {
    /** Connects to the room; the frame encryption is on from the first frame, with this phone's own key already installed. */
    suspend fun connect(url: String, token: String, identity: String, myKey: ByteArray, microphone: Boolean, camera: Boolean)
    fun setKey(key: ByteArray, participant: String)
    suspend fun setMicrophone(on: Boolean)
    suspend fun setCamera(on: Boolean)
    fun flipCamera() {}
    fun disconnect()
    /** The room's frame encryption is on (made when the room connects). */
    val encrypted: Boolean get() = true
    /** Draws a person's picture into this sink (null stops). */
    fun attach(participant: String, renderer: io.livekit.android.renderer.TextureViewRenderer?) {}
}

/** What the media tells the session. */
interface GroupMediaEvents {
    fun onParticipantConnected(participant: String)
    fun onParticipantDisconnected(participant: String)
    fun onPicture(participant: String, showing: Boolean)
    fun onMuted(participant: String, muted: Boolean)
    fun onSpeakers(participants: List<String>)
    fun onConnected()
    fun onDisconnected()
}

/**
 * One phone's group call (iOS `GroupCallManager`): a thin adapter between the core (who may join, the sender keys, the roster, the four emoji: `start_group_call`, `join_group_call`,
 * `take_group_call_events`, `deliver_group_call_ops`, `group_call_emoji_state`, `request_group_call_key`) and LiveKit (the media). The core decides; this asks and obeys. Every
 * participant's frame key arrives as raw bytes through the core's events and goes to the frame encryption at slot 0, so the LiveKit server forwards ciphertext only. All calls on the main thread.
 */
class GroupCallSession(
    private val context: Context,
    private val store: () -> LimeStore?,
    private val transport: () -> HttpTransport?,
    private val token: suspend () -> String,
    private val scope: CoroutineScope,
    private val nameOfUser: (String) -> String = { it },
    private val myName: () -> String = { "" },
    private val announce: (String) -> Unit = {},
    private val mediaFactory: (GroupMediaEvents) -> GroupMedia = { events -> LiveKitGroupMedia(context, events) },
    private val audio: CallAudioPort = RealCallAudio(context),
    private val useService: Boolean = true,
    /** A group call has started that this phone may ring for (lime is open or in the background). */
    private val onRing: (GroupCallInfo, Boolean) -> Unit = { _, _ -> },
) {
    var call by mutableStateOf<GroupCallInfo?>(null); private set
    var connecting by mutableStateOf(false); private set
    var connected by mutableStateOf(false); private set
    val tiles = mutableStateListOf<GroupTile>()
    var emoji by mutableStateOf<List<CallEmoji>>(emptyList()); private set
    var emojiWaiting by mutableStateOf(0); private set
    var muted by mutableStateOf(false); private set
    var cameraOn by mutableStateOf(false); private set
    var minimized by mutableStateOf(false); private set
    var notice by mutableStateOf<String?>(null)
    val inCall: Boolean get() = call?.joined == true || connecting
    /** The media's frame encryption is on (a call is never shown as secure without it). */
    val encrypted: Boolean get() = media?.encrypted == true
    var myParticipant: String = ""; private set
    private var media: GroupMedia? = null
    private var ticker: Job? = null
    private var startedAt = 0L
    val startMillis: Long get() = startedAt
    private val keysSeen = mutableSetOf<String>()
    private val askedAt = mutableMapOf<String, Long>()

    private val events = object : GroupMediaEvents {
        override fun onParticipantConnected(participant: String) { scope.launch { refreshEmoji() } }
        override fun onParticipantDisconnected(participant: String) {
            scope.launch {
                val id = call?.callId ?: return@launch
                // LiveKit says they are gone: the core renews my key for everyone who stays (their sender key must not outlive them).
                withContext(Dispatchers.IO) { runCatching { store()?.groupCallParticipantGone(id, participant) } }
                deliver(); drainEvents()
            }
        }
        override fun onPicture(participant: String, showing: Boolean) { scope.launch { update(participant) { it.copy(hasPicture = showing) } } }
        override fun onMuted(participant: String, muted: Boolean) { scope.launch { update(participant) { it.copy(muted = muted) } } }
        override fun onSpeakers(participants: List<String>) { scope.launch { tiles.indices.forEach { i -> val t = tiles[i]; val s = t.participant in participants; if (t.speaking != s) tiles[i] = t.copy(speaking = s) } } }
        override fun onConnected() { scope.launch { connected = true; connecting = false; if (startedAt == 0L) startedAt = System.currentTimeMillis(); announce("Connected") } }
        override fun onDisconnected() { scope.launch { if (inCall) leave() } }
    }

    private fun update(participant: String, change: (GroupTile) -> GroupTile) {
        val i = tiles.indexOfFirst { it.participant == participant }
        if (i >= 0) tiles[i] = change(tiles[i])
    }

    // ---- what the person does

    /** Starts a call in a group (or joins the one already on) and joins it. The microphone (and for video the camera) permission has been asked for by now. */
    fun start(conversationId: String, video: Boolean) {
        if (inCall) return
        scope.launch {
            val core = store() ?: return@launch
            val info = runCatching { withContext(Dispatchers.IO) { core.startGroupCall(conversationId, video) } }.getOrElse { notice = "That call could not be started."; return@launch }
            join(info.callId, video || info.video)
        }
    }

    fun join(callId: String, video: Boolean) {
        if (inCall) return
        scope.launch {
            val core = store() ?: return@launch
            val link = transport() ?: return@launch
            connecting = true; connected = false; startedAt = 0L; muted = false; minimized = false; emoji = emptyList(); tiles.clear(); keysSeen.clear(); askedAt.clear()
            try {
                val join = withContext(Dispatchers.IO) { core.joinGroupCall(callId) }
                call = join.call; myParticipant = join.participant
                cameraOn = video
                tiles += GroupTile(join.participant, "", myName(), isMe = true, keyReady = true)
                join.participants.filter { it.participant != join.participant }.forEach { tiles += GroupTile(it.participant, it.userId, it.name, isMe = false, keyReady = false) }
                // The key side first: my own key is installed before a single frame goes out, the others' as their key events arrive.
                val m = mediaFactory(events); media = m
                audio.start(speaker = video)
                if (useService) CallService.start(context, join.call.conversationId.let { _ -> nameOfConversation(join.call) })
                val livekit = withContext(Dispatchers.IO) { runCatching { core.fetchLivekitToken(link, token(), join.call.room, join.participant) }.getOrNull() }
                if (livekit == null) { fail("Group calls are not set up on this server yet."); return@launch }
                // The core queued my join and my key for everyone (`deliver_group_call_ops`); send them, then take what came back.
                deliver(); drainEvents()
                m.connect(livekit.url, livekit.token, join.participant, join.key, microphone = true, camera = video)
                startTicker()
                refreshEmoji()
            } catch (e: Exception) {
                fail("The call could not connect.")
            }
        }
    }

    private fun nameOfConversation(info: GroupCallInfo): String = info.startedByName.ifEmpty { "Group call" }

    private suspend fun fail(words: String) {
        notice = words
        leave()
    }

    fun leave() {
        val info = call ?: return
        ticker?.cancel(); ticker = null
        media?.disconnect(); media = null
        audio.stop(); if (useService) CallService.stop(context)
        scope.launch {
            withContext(Dispatchers.IO) { runCatching { store()?.leaveGroupCall(info.callId) } }
            deliver()
        }
        call = null; connecting = false; connected = false; tiles.clear(); emoji = emptyList(); muted = false; cameraOn = false; minimized = false; startedAt = 0L
    }

    fun toggleMute() { muted = !muted; scope.launch { media?.setMicrophone(!muted) } }
    fun toggleCamera() { cameraOn = !cameraOn; scope.launch { media?.setCamera(cameraOn) } }
    fun flipCamera() { media?.flipCamera() }
    fun minimize() { if (inCall) { minimized = true; announce("Call minimised") } }
    fun restore() { minimized = false }
    fun attach(participant: String, renderer: io.livekit.android.renderer.TextureViewRenderer?) { media?.attach(participant, renderer) }

    // ---- the core's events (after every sync) and what this phone owes the others

    /** Called after each sync: the core's events (a call started, people joined and left, keys) and then the ops this phone owes. */
    suspend fun handleArrivals() {
        drainEvents()
        if (inCall) deliver()
    }

    private suspend fun deliver() {
        val core = store() ?: return; val link = transport() ?: return
        withContext(Dispatchers.IO) { runCatching { core.deliverGroupCallOps(link, token()) } }
    }

    private suspend fun drainEvents() {
        val core = store() ?: return
        val list = withContext(Dispatchers.IO) { runCatching { core.takeGroupCallEvents() }.getOrDefault(emptyList()) }
        var changed = false
        for (e in list) changed = apply(e) || changed
        if (changed) refreshEmoji()
    }

    private fun apply(e: GroupCallEvent): Boolean {
        val mine = call?.callId == e.callId
        when (e.kind) {
            "started" -> { if (!mine && e.ring) store()?.let { core -> runCatching { core.activeGroupCall(e.conversationId) }.getOrNull()?.let { onRing(it, e.video) } } }
            "joined" -> if (mine && tiles.none { it.participant == e.participant }) { tiles += GroupTile(e.participant, e.userId, e.name.ifEmpty { nameOfUser(e.userId) }, isMe = false, keyReady = false); return true }
            "left" -> if (mine) { tiles.removeAll { it.participant == e.participant }; keysSeen.remove(e.participant); return true }
            "key", "my_key" -> if (mine) {
                val key = e.key ?: return false
                // Every key is installed at slot 0, whatever index the core gave it (iOS does the same; see GroupCallKeys).
                media?.setKey(key, e.participant)
                keysSeen += e.participant
                update(e.participant) { it.copy(keyReady = true) }
                return true
            }
        }
        return false
    }

    private suspend fun refreshEmoji() {
        val core = store() ?: return; val id = call?.callId ?: return
        val state = withContext(Dispatchers.IO) { runCatching { core.groupCallEmojiState(id) }.getOrNull() } ?: return
        emoji = state.emoji; emojiWaiting = state.waiting.toInt()
    }

    /** A tile stuck without a key asks its owner to send it again (the core queues the request); checked every few seconds. */
    private fun startTicker() {
        ticker?.cancel()
        ticker = scope.launch {
            while (true) {
                delay(4_000)
                val id = call?.callId ?: break
                val core = store() ?: continue
                val now = System.currentTimeMillis()
                for (t in tiles.toList()) if (!t.isMe && !t.keyReady && now - (askedAt[t.participant] ?: 0L) > 8_000) {
                    askedAt[t.participant] = now
                    withContext(Dispatchers.IO) { runCatching { core.requestGroupCallKey(id, t.participant) } }
                    deliver()
                }
                drainEvents()
            }
        }
    }
}

/** LiveKit's Android SDK as the group call media engine, with the iOS key scheme (`GroupCallKeys`): per-participant keys, AES-GCM frame encryption, simulcast, adaptive streams. */
class LiveKitGroupMedia(private val context: Context, private val events: GroupMediaEvents) : GroupMedia {
    // WebRTC's native library is loaded before the first key provider is made (the staging proof found this: the key provider's native code was not there yet).
    private val loaded = WebRtcCallMedia.ensureLoaded(context)
    private val keys = GroupCallKeys()
    private var room: Room? = null
    private var watcher: Job? = null
    private val renderers = mutableMapOf<String, io.livekit.android.renderer.TextureViewRenderer>()

    override suspend fun connect(url: String, token: String, identity: String, myKey: ByteArray, microphone: Boolean, camera: Boolean) {
        // LiveKit's native code is loaded by the WebRTC factory; the key provider needs it.
        WebRtcCallMedia.ensureLoaded(context)
        keys.setKey(myKey, identity)
        val options = RoomOptions(adaptiveStream = true, dynacast = true, e2eeOptions = keys.options())
        val r = LiveKit.create(context.applicationContext, options)
        room = r
        watcher = CoroutineScope(Dispatchers.Main).launch {
            r.events.collect { event ->
                when (event) {
                    is RoomEvent.ParticipantConnected -> events.onParticipantConnected(event.participant.identity?.value.orEmpty())
                    is RoomEvent.ParticipantDisconnected -> events.onParticipantDisconnected(event.participant.identity?.value.orEmpty())
                    is RoomEvent.TrackSubscribed -> if (event.track is VideoTrack) { events.onPicture(event.participant.identity?.value.orEmpty(), true); bind(event.participant.identity?.value.orEmpty(), event.track as VideoTrack) }
                    is RoomEvent.TrackUnsubscribed -> if (event.track is VideoTrack) events.onPicture(event.participant.identity?.value.orEmpty(), false)
                    is RoomEvent.TrackMuted -> if (event.publication.source == Track.Source.MICROPHONE) events.onMuted(event.participant.identity?.value.orEmpty(), true)
                    is RoomEvent.TrackUnmuted -> if (event.publication.source == Track.Source.MICROPHONE) events.onMuted(event.participant.identity?.value.orEmpty(), false)
                    is RoomEvent.ActiveSpeakersChanged -> events.onSpeakers(event.speakers.map { (it as Participant).identity?.value.orEmpty() })
                    is RoomEvent.Disconnected -> events.onDisconnected()
                    else -> {}
                }
            }
        }
        r.connect(url, token)
        r.localParticipant.setMicrophoneEnabled(microphone)
        if (camera) r.localParticipant.setCameraEnabled(true)
        events.onConnected()
    }

    private fun bind(participant: String, track: VideoTrack) {
        renderers[participant]?.let { track.addRenderer(it) }
    }

    override val encrypted: Boolean get() = room?.e2eeManager != null
    override fun setKey(key: ByteArray, participant: String) { keys.setKey(key, participant) }
    override suspend fun setMicrophone(on: Boolean) { room?.localParticipant?.setMicrophoneEnabled(on) }
    override suspend fun setCamera(on: Boolean) { room?.localParticipant?.setCameraEnabled(on) }

    override fun attach(participant: String, renderer: io.livekit.android.renderer.TextureViewRenderer?) {
        val r = room ?: return
        val old = renderers.remove(participant)
        val p = if (participant == r.localParticipant.identity?.value) r.localParticipant else r.remoteParticipants.entries.firstOrNull { it.key.value == participant }?.value
        val track = p?.getTrackPublication(Track.Source.CAMERA)?.track as? VideoTrack
        if (old != null) track?.removeRenderer(old)
        if (renderer != null) { r.initVideoRenderer(renderer); renderers[participant] = renderer; track?.addRenderer(renderer) }
    }

    override fun disconnect() {
        watcher?.cancel(); watcher = null
        runCatching { room?.disconnect() }; runCatching { room?.release() }
        room = null; renderers.clear()
    }
}
