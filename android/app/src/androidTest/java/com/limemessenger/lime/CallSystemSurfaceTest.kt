package com.limemessenger.lime

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.calls.CallActionReceiver
import com.limemessenger.lime.calls.CallAudioPort
import com.limemessenger.lime.calls.CallIceServer
import com.limemessenger.lime.calls.CallMedia
import com.limemessenger.lime.calls.CallMediaEvents
import com.limemessenger.lime.calls.CallPrefs
import com.limemessenger.lime.calls.CallService
import com.limemessenger.lime.calls.CallSession
import com.limemessenger.lime.calls.IncomingCallNotifier
import com.limemessenger.lime.calls.InboundAudio
import com.limemessenger.lime.calls.RemoteCandidate
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.calls.CallMiniBar
import com.limemessenger.lime.ui.settings.CallSettingsScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.CallMachineEvent
import uniffi.lime_core.CallPhaseKind
import uniffi.lime_core.LimeStore

/**
 * LIME-427: lime's calls on the phone's own surfaces. The incoming-call notification (its words, its Answer and Decline, the full-screen intent, the channel's importance, sound and
 * vibration), the Decline button reaching the call, a ring that goes to the notification only when lime is not in front, the ongoing call's notification with Hang up, the mini-bar,
 * and Settings → Calls saying whether the ring can happen. The real session and the core's machine; a fake media and audio.
 */
@RunWith(AndroidJUnit4::class)
class CallSystemSurfaceTest {
    @get:Rule val rule = createComposeRule()
    private val context: Context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val manager get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var session: CallSession
    private val job = Job()
    private val alias = "lime.test.callsurface"
    private var front = true

    private class FakeMedia(events: CallMediaEvents) : CallMedia {
        override fun start(servers: List<CallIceServer>, relayOnly: Boolean) {}
        override suspend fun makeOffer() = "v=0\r\na=fingerprint:sha-256 11:22\r\n"
        override suspend fun accept(offer: String) = "v=0\r\na=fingerprint:sha-256 11:22\r\n"
        override suspend fun apply(answer: String) {}
        override fun add(candidates: List<RemoteCandidate>) {}
        override fun setMuted(on: Boolean) {}
        override suspend fun inboundAudio(): InboundAudio? = null
        override fun close() {}
    }
    private class Audio : CallAudioPort {
        val log = java.util.concurrent.CopyOnWriteArrayList<String>()
        override fun start(speaker: Boolean) {}
        override fun setSpeaker(on: Boolean) {}
        override fun stop() {}
        override fun startRingback() {}
        override fun stopRingback() {}
        override fun startRinging() { log += "ring" }
        override fun stopRinging() { log += "stopRing" }
        override fun postIncoming(callId: String, name: String, video: Boolean) { log += "post:$name:$video" }
        override fun cancelIncoming() { log += "cancel" }
    }
    private val audio = Audio()

    @Before fun setUp() {
        shell("pm grant ${context.packageName} android.permission.POST_NOTIFICATIONS")
        shell("pm grant ${context.packageName} android.permission.RECORD_AUDIO")
        dir = File(context.cacheDir, "callsurface-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("callsurface-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        session = CallSession(context, { store }, { null }, { "t" }, { "me" }, CoroutineScope(Dispatchers.Main + job), nameOf = { "Autumn Reyes" }, mediaFactory = { FakeMedia(it) }, audio = audio, useService = false, opSender = { _, _, _ -> true }, foreground = { front })
        (context.applicationContext as LimeApp).callSession = session
        IncomingCallNotifier.cancel(context)
    }

    @After fun tearDown() {
        (context.applicationContext as LimeApp).callSession = null
        IncomingCallNotifier.cancel(context); CallService.stop(context)
        job.cancel(); store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias)
    }

    private fun shell(command: String) { InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).close() }
    private fun main(block: () -> Unit) = runBlocking(Dispatchers.Main) { block() }
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun desc(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
    private fun ring(id: String = "in1") { main { session.driver.handle("call.offer", id, "ben", JSONObject().put("sdp", "v=0\r\na=fingerprint:sha-256 AA:BB\r\n")) } }
    private fun active() {
        main { session.call("ben", "Autumn Reyes") }
        rule.waitUntil(5_000) { session.driver.state.phase == CallPhaseKind.OUTGOING }
        main { session.driver.handle("call.answer", session.driver.state.callId, "ben", JSONObject().put("sdp", "v=0\r\na=fingerprint:sha-256 CC:DD\r\n")); session.driver.dispatch(CallMachineEvent.MediaUp) }
        rule.waitUntil(5_000) { session.phase == CallPhaseKind.ACTIVE }
    }

    // ---- the notification

    @Test fun theIncomingCallNotificationHasTheNameTheWordsAnAnswerAndADeclineAndTakesTheScreenWhenLocked() {
        val n = IncomingCallNotifier.build(context, "c1", "Ben Test", video = false)
        assertEquals("Ben Test", n.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertEquals("lime voice call", n.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals(Notification.CATEGORY_CALL, n.category)
        assertNotNull("the full-screen intent", n.fullScreenIntent)
        assertEquals(listOf("Decline", "Answer"), n.actions.map { it.title.toString() }.let { titles -> titles.sortedBy { it != "Decline" } })
        assertTrue("ongoing until answered or declined", n.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertTrue("the ring repeats", n.flags and Notification.FLAG_INSISTENT != 0)
        assertEquals("a lock screen shows no private text", Notification.VISIBILITY_PRIVATE, n.visibility)
        assertEquals("lime video call", IncomingCallNotifier.build(context, "c1", "Ben Test", video = true).extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertNotNull("the caller's picture", n.getLargeIcon())
    }

    @Test fun theChannelIsHighImportanceWithTheRingtoneAndVibrationTheUserCanChangeInTheirSettings() {
        IncomingCallNotifier.createChannel(context)
        val channel = manager.getNotificationChannel(IncomingCallNotifier.CHANNEL)
        assertNotNull(channel)
        assertEquals(NotificationManager.IMPORTANCE_HIGH, channel.importance)
        assertNotNull("rings", channel.sound); assertTrue("vibrates", channel.shouldVibrate())
        assertEquals(android.media.AudioAttributes.USAGE_NOTIFICATION_RINGTONE, channel.audioAttributes.usage)
        assertFalse("it does not bypass Do Not Disturb", channel.canBypassDnd())
    }

    @Test fun postingAndCancellingTheNotification() {
        IncomingCallNotifier.post(context, "c1", "Ben Test", false)
        rule.waitUntil(5_000) { manager.activeNotifications.any { it.id == IncomingCallNotifier.NOTIFICATION_ID } }
        IncomingCallNotifier.cancel(context)
        rule.waitUntil(5_000) { manager.activeNotifications.none { it.id == IncomingCallNotifier.NOTIFICATION_ID } }
    }

    @Test fun theDeclineButtonDeclinesThatCallAndAStaleOneDoesNothing() {
        front = false
        ring("in7"); rule.waitUntil(5_000) { session.phase == CallPhaseKind.INCOMING }
        context.sendBroadcast(Intent(context, CallActionReceiver::class.java).setAction(IncomingCallNotifier.ACTION_DECLINE).putExtra(IncomingCallNotifier.EXTRA_CALL, "some-other-call"))
        Thread.sleep(1_000)
        assertEquals("a stale button does nothing", CallPhaseKind.INCOMING, session.phase)
        context.sendBroadcast(Intent(context, CallActionReceiver::class.java).setAction(IncomingCallNotifier.ACTION_DECLINE).putExtra(IncomingCallNotifier.EXTRA_CALL, "in7"))
        rule.waitUntil(10_000) { session.phase == CallPhaseKind.IDLE }
    }

    // ---- who rings: the call screen in front, the notification behind

    @Test fun inFrontTheCallScreenRingsAndNoNotificationIsPosted() {
        front = true; ring()
        rule.waitUntil(5_000) { audio.log.contains("ring") }
        assertTrue(audio.log.none { it.startsWith("post") })
    }

    @Test fun behindTheNotificationRingsAndComingToTheFrontSwapsThem() {
        front = false; ring()
        rule.waitUntil(5_000) { audio.log.any { it == "post:Autumn Reyes:false" || it.startsWith("post:") } }
        assertFalse(audio.log.contains("ring"))
        audio.log.clear()
        main { session.appForeground(true) }
        assertEquals(listOf("cancel", "ring"), audio.log.toList())
        audio.log.clear()
        main { session.appForeground(false) }
        assertEquals("stopRing", audio.log.first()); assertTrue(audio.log.last().startsWith("post:"))
    }

    @Test fun answeringOrDecliningTakesTheNotificationAway() {
        front = false; ring(); rule.waitUntil(5_000) { session.phase == CallPhaseKind.INCOMING }
        audio.log.clear()
        main { session.decline() }
        rule.waitUntil(5_000) { session.phase == CallPhaseKind.IDLE }
        assertTrue("cancelled: ${audio.log}", audio.log.contains("cancel"))
    }

    // ---- the call that is going

    @Test fun theOngoingCallNotificationNamesThePersonAndHasHangUp() {
        CallService.start(context, "Ben Test")
        rule.waitUntil(10_000) { manager.activeNotifications.any { it.id == CallService.NOTIFICATION_ID } }
        val n = manager.activeNotifications.first { it.id == CallService.NOTIFICATION_ID }.notification
        assertTrue(n.extras.getCharSequence(Notification.EXTRA_TITLE).toString().contains("Ben Test"))
        assertTrue("ongoing", n.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals(listOf("Hang up"), n.actions.map { it.title.toString() })
        CallService.stop(context)
        rule.waitUntil(10_000) { manager.activeNotifications.none { it.id == CallService.NOTIFICATION_ID } }
    }

    // ---- the mini-bar

    @Test fun theMiniBarNamesThePersonAndHasMuteEndAndAWayBackWithLargeTargets() {
        active()
        main { session.minimize() }
        assertTrue(session.minimized)
        rule.setContent { LimeTheme { CallMiniBar(session, chats) } }
        rule.waitUntil(5_000) { count("call-mini-bar") > 0 }
        assertTrue(desc("call-mini-open").startsWith("Call with Autumn Reyes"))
        assertEquals("Mute", desc("call-mini-mute")); assertEquals("End call", desc("call-mini-end"))
        for (tag in listOf("call-mini-open", "call-mini-mute", "call-mini-end")) rule.onNodeWithTag(tag, useUnmergedTree = true).assertHeightIsAtLeast(48.dp)
        rule.onNodeWithTag("call-mini-mute", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { session.muted }
        rule.onNodeWithTag("call-mini-open", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { !session.minimized }
        main { session.minimize() }
        rule.onNodeWithTag("call-mini-end", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { session.phase == CallPhaseKind.IDLE }
        assertFalse("the call's end brings the call screen state back to rest", session.minimized)
    }

    @Test fun aRingingCallCannotBeMinimised() {
        ring(); rule.waitUntil(5_000) { session.phase == CallPhaseKind.INCOMING }
        main { session.minimize() }
        assertFalse(session.minimized)
    }

    // ---- Settings → Calls

    @Test fun settingsSaysWhetherTheRingCanHappenAndHasAButtonToThePhonesSettings() {
        rule.setContent { LimeTheme { CallSettingsScreen(CallPrefs(context.getSharedPreferences("lime.calls.surface", Context.MODE_PRIVATE)), onBack = {}) } }
        rule.waitUntil(5_000) { count("calls-ring-state") > 0 }
        val state = rule.onNodeWithTag("calls-ring-state", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString("")
        assertEquals("Ring while lime is in the background: on", state)
        assertEquals(1, count("calls-ring-settings"))
        assertEquals(0, count("calls-ring-allow"))
        assertTrue(IncomingCallNotifier.surface(context).ringsInBackground)
        val intent = IncomingCallNotifier.settingsIntent(context)
        assertEquals(android.provider.Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS, intent.action)
        assertEquals(IncomingCallNotifier.CHANNEL, intent.getStringExtra(android.provider.Settings.EXTRA_CHANNEL_ID))
    }

    @Test fun withNotificationsDeniedSettingsSaysSoAndOffersToAllowThem() {
        // (Revoking the permission kills the app's own process, so the denied state is handed to the screen.)
        val denied = IncomingCallNotifier.Surface(notificationsAllowed = false, channelAllowed = true, fullScreenAllowed = true)
        rule.setContent { LimeTheme { CallSettingsScreen(CallPrefs(context.getSharedPreferences("lime.calls.surface", Context.MODE_PRIVATE)), onBack = {}, surfaceOf = { denied }) } }
        rule.waitUntil(5_000) { count("calls-ring-state") > 0 }
        val state = rule.onNodeWithTag("calls-ring-state", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString("")
        assertEquals("Ring while lime is in the background: off. Notifications are off for lime.", state)
        if (Build.VERSION.SDK_INT >= 33) assertEquals(1, count("calls-ring-allow"))
        assertEquals("the phone's own page opens at the app's notification settings", android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS.let { it }, android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        assertFalse(denied.ringsInBackground)
    }

    @Test fun withTheChannelOrFullScreenOffSettingsSaysWhichAndLinksToIt() {
        val channelOff = IncomingCallNotifier.Surface(notificationsAllowed = true, channelAllowed = false, fullScreenAllowed = false)
        rule.setContent { LimeTheme { CallSettingsScreen(CallPrefs(context.getSharedPreferences("lime.calls.surface", Context.MODE_PRIVATE)), onBack = {}, surfaceOf = { channelOff }) } }
        rule.waitUntil(5_000) { count("calls-ring-state") > 0 }
        assertEquals("Ring while lime is in the background: off. Incoming call notifications are turned off.", rule.onNodeWithTag("calls-ring-state", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString(""))
        if (Build.VERSION.SDK_INT >= 34) {
            assertEquals(1, count("calls-ring-fullscreen")); assertEquals(1, count("calls-ring-fullscreen-settings"))
            assertNotNull(IncomingCallNotifier.fullScreenSettingsIntent(context))
        } else assertNull(IncomingCallNotifier.fullScreenSettingsIntent(context))
    }
}
