package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.calls.CallPrefs
import com.limemessenger.lime.calls.CallsModel
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.calls.CallsScreen
import com.limemessenger.lime.ui.chat.ChatScreen
import com.limemessenger.lime.ui.settings.CallSettingsScreen
import com.limemessenger.lime.ui.shell.Shell
import com.limemessenger.lime.ui.shell.Tab
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.CallLogEntry
import uniffi.lime_core.CallResult
import uniffi.lime_core.LimeStore

/** NOT a test: the LIME-424 screenshots (the Calls tab, its details, the chat's call bubbles, Settings → Calls; light, dark, 200% font) into files/shots (`tools/shots-calls1.sh`). */
@Staging
@RunWith(AndroidJUnit4::class)
class CallsShotsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var calls: CallsModel
    private val alias = "lime.test.callsshots"
    private val minute = 60_000L

    @Before fun setUp() {
        dir = File(context.cacheDir, "callsshots-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("callsshots-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        calls = CallsModel { store }
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun entry(id: String, peer: String, name: String, ago: Long, result: CallResult, video: Boolean = false, outgoing: Boolean = false, seconds: Int = 0) =
        CallLogEntry(id, peer, name, video, outgoing, System.currentTimeMillis() - ago, seconds * 1000L, result)
    private fun shot(name: String) {
        rule.waitForIdle(); Thread.sleep(800)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(File(context.filesDir, "shots").also { it.mkdirs() }, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun seed() = runBlocking {
        val autumn = chats.conversations.first { it.title == "Autumn Reyes" }.members.first()
        val group = chats.conversations.first { it.isGroup }
        calls.add(entry("m1", autumn.id, "Autumn Reyes", 3 * minute, CallResult.MISSED))
        calls.add(entry("m2", autumn.id, "Autumn Reyes", 4 * minute, CallResult.MISSED))
        calls.add(entry("a1", autumn.id, "Autumn Reyes", 40 * minute, CallResult.COMPLETED, seconds = 252))
        calls.add(entry("v1", "sam", "Sam Park", 90 * minute, CallResult.COMPLETED, video = true, outgoing = true, seconds = 31))
        calls.add(entry("s1", "lee", "Lee Wong", 2 * minute, CallResult.MISSED_DND))
        calls.add(entry("u1", "jean", "Jean Chung", 26 * 60 * minute, CallResult.UNAVAILABLE, outgoing = true))
        calls.add(entry("g1", group.id, group.title, 50 * 60 * minute, CallResult.COMPLETED, video = true, seconds = 1200))
        calls.add(entry("o1", "rise", "Rise Chung", 5 * 24 * 60 * minute, CallResult.NO_ANSWER, outgoing = true))
    }
    private fun scr(name: String, dark: Boolean = false, font: Float = 1f, after: () -> Unit = {}, body: @Composable () -> Unit) {
        rule.setContent {
            val d = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(d.density, font)) { LimeTheme(dark = dark) { body() } }
        }
        after()
        shot(name + if (dark) "-dark" else "")
    }
    @Composable private fun TabContent() { Shell(link = {}, selected = Tab.Call, calls = { CallsScreen(calls, chats, "Ada Android", 5, {}, {}, { _, _, _ -> }) }) }

    @Test fun tab() { seed(); scr("1-calls-tab", after = { rule.waitUntil(5_000) { count("call-history-row") > 3 } }) { TabContent() } }
    @Test fun tabDark() { seed(); scr("1-calls-tab", dark = true, after = { rule.waitUntil(5_000) { count("call-history-row") > 3 } }) { TabContent() } }
    @Test fun tabLargest() { seed(); scr("2-calls-tab-font2", font = 2f, after = { rule.waitUntil(5_000) { count("call-history-row") > 3 } }) { TabContent() } }
    @Test fun missedFilter() { seed(); scr("3-calls-missed", after = { rule.waitUntil(5_000) { count("call-history-row") > 3 }; rule.onNodeWithTag("calls-filter-missed", useUnmergedTree = true).performClick(); rule.waitUntil(5_000) { count("call-history-row") == 2 } }) { TabContent() } }
    @Test fun empty() = scr("4-calls-empty", after = { rule.waitUntil(5_000) { count("calls-empty") > 0 } }) { TabContent() }
    @Test fun badge() { seed(); runBlocking { calls.reload() }; scr("5-calls-tab-badge", after = {}) { Shell(link = {}, selected = Tab.Link, linkUnread = 2, callsMissed = 3, calls = {}) } }
    @Test fun details() { seed(); scr("6-call-details", after = { rule.waitUntil(5_000) { count("call-row-avatar") > 0 }; rule.onAllNodes(hasTestTag("call-row-avatar"), useUnmergedTree = true)[2].performClick(); rule.waitUntil(5_000) { count("call-details") > 0 } }) { TabContent() } }
    @Test fun bubbles() {
        val dm = store.startDm("ben-test", "Ben Test"); runBlocking { chats.reload() }
        runBlocking {
            calls.add(entry("c1", "ben-test", "Ben Test", 50 * minute, CallResult.COMPLETED, seconds = 252))
            calls.add(entry("c2", "ben-test", "Ben Test", 40 * minute, CallResult.MISSED, video = true))
            calls.add(entry("c3", "ben-test", "Ben Test", 30 * minute, CallResult.DECLINED, outgoing = true))
            calls.add(entry("c4", "ben-test", "Ben Test", 20 * minute, CallResult.MISSED_DND))
            calls.add(entry("c5", "ben-test", "Ben Test", 10 * minute, CallResult.NO_ANSWER, outgoing = true))
            chats.reload()
        }
        val chat = ChatModel(dm, chats, accountSignedIn = false)
        scr("7-call-bubbles", after = { rule.waitUntil(5_000) { count("call-bubble-title") >= 5 } }) { ChatScreen(chat, chats, onBack = {}) }
    }
    @Test fun bubblesDark() {
        val dm = store.startDm("ben-test", "Ben Test"); runBlocking { chats.reload() }
        runBlocking { calls.add(entry("c1", "ben-test", "Ben Test", 50 * minute, CallResult.COMPLETED, seconds = 252)); calls.add(entry("c2", "ben-test", "Ben Test", 40 * minute, CallResult.MISSED, video = true)); chats.reload() }
        val chat = ChatModel(dm, chats, accountSignedIn = false)
        scr("7-call-bubbles", dark = true, after = { rule.waitUntil(5_000) { count("call-bubble-title") >= 2 } }) { ChatScreen(chat, chats, onBack = {}) }
    }
    @Test fun settings() = scr("8-call-settings") { CallSettingsScreen(CallPrefs(context.getSharedPreferences("lime.calls.shots", android.content.Context.MODE_PRIVATE)), onBack = {}) }
    @Test fun settingsDark() = scr("8-call-settings", dark = true) { CallSettingsScreen(CallPrefs(context.getSharedPreferences("lime.calls.shots", android.content.Context.MODE_PRIVATE)), onBack = {}) }
    @Test fun settingsLargest() = scr("9-call-settings-font2", font = 2f) { CallSettingsScreen(CallPrefs(context.getSharedPreferences("lime.calls.shots", android.content.Context.MODE_PRIVATE)), onBack = {}) }

    // ---- LIME-425: the call screen (fake media; the screen is dark in both themes, as iOS's)
    private class ShotMedia(private val events: com.limemessenger.lime.calls.CallMediaEvents) : com.limemessenger.lime.calls.CallMedia {
        private val sdp = "v=0\r\na=fingerprint:sha-256 11:22:33:44\r\n"
        override fun start(servers: List<com.limemessenger.lime.calls.CallIceServer>, relayOnly: Boolean) {}
        override suspend fun makeOffer() = sdp
        override suspend fun accept(offer: String) = sdp
        override suspend fun apply(answer: String) {}
        override fun add(candidates: List<com.limemessenger.lime.calls.RemoteCandidate>) {}
        override fun setMuted(on: Boolean) {}
        override suspend fun inboundAudio(): com.limemessenger.lime.calls.InboundAudio? = null
        override fun close() {}
    }
    private object ShotAudio : com.limemessenger.lime.calls.CallAudioPort {
        override fun start(speaker: Boolean) {}
        override fun setSpeaker(on: Boolean) {}
        override fun stop() {}
        override fun startRingback() {}
        override fun stopRingback() {}
        override fun startRinging() {}
        override fun stopRinging() {}
    }
    private val callJob = kotlinx.coroutines.Job()
    private fun session() = com.limemessenger.lime.calls.CallSession(
        context, { store }, { null }, { "t" }, { "me" }, kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.Main + callJob), nameOf = { "Autumn Reyes" },
        mediaFactory = { ShotMedia(it) }, audio = ShotAudio, useService = false, opSender = { _, _, _ -> true },
    )
    private fun main(block: () -> Unit) = runBlocking(kotlinx.coroutines.Dispatchers.Main) { block() }
    private fun emojiOf() = uniffi.lime_core.callEmoji("shots", "AB:CD", "01:23")

    @Test fun callIncoming() {
        val s = session(); main { s.driver.handle("call.offer", "in1", chats.conversations.first { it.title == "Autumn Reyes" }.members.first().id, org.json.JSONObject().put("sdp", "v=0\r\na=fingerprint:sha-256 AA:BB\r\n")) }
        scr("10-call-incoming", after = { rule.waitUntil(5_000) { count("call-accept") > 0 } }) { com.limemessenger.lime.ui.calls.CallScreen(s, chats) }
    }
    @Test fun callCalling() {
        val s = session(); main { s.call(chats.conversations.first { it.title == "Autumn Reyes" }.members.first().id, "Autumn Reyes") }
        scr("11-call-calling", after = { rule.waitUntil(5_000) { count("call-status") > 0 } }) { com.limemessenger.lime.ui.calls.CallScreen(s, chats) }
    }
    private fun active(): com.limemessenger.lime.calls.CallSession {
        val s = session(); val peer = chats.conversations.first { it.title == "Autumn Reyes" }.members.first().id
        main { s.call(peer, "Autumn Reyes") }
        rule.waitUntil(5_000) { s.driver.state.phase == uniffi.lime_core.CallPhaseKind.OUTGOING }
        main { s.driver.handle("call.answer", s.driver.state.callId, peer, org.json.JSONObject().put("sdp", "v=0\r\nanswer")); s.driver.dispatch(uniffi.lime_core.CallMachineEvent.MediaUp); s.showEmojiForTest(emojiOf()) }
        return s
    }
    @Test fun callActive() { val s = active(); scr("12-call-active", after = { rule.waitUntil(5_000) { count("call-emoji") > 0 } }) { com.limemessenger.lime.ui.calls.CallScreen(s, chats) } }
    @Test fun callActiveMuted() { val s = active(); main { s.toggleMute(); s.toggleSpeaker() }; scr("13-call-active-muted-speaker", after = { rule.waitUntil(5_000) { count("call-emoji") > 0 } }) { com.limemessenger.lime.ui.calls.CallScreen(s, chats) } }
    @Test fun callActiveLargest() { val s = active(); scr("14-call-active-font2", font = 2f, after = { rule.waitUntil(5_000) { count("call-emoji") > 0 } }) { com.limemessenger.lime.ui.calls.CallScreen(s, chats) } }
    @Test fun callIncomingLargest() {
        val s = session(); main { s.driver.handle("call.offer", "in2", chats.conversations.first { it.title == "Autumn Reyes" }.members.first().id, org.json.JSONObject().put("sdp", "v=0\r\na=fingerprint:sha-256 AA:BB\r\n")) }
        scr("15-call-incoming-font2", font = 2f, after = { rule.waitUntil(5_000) { count("call-accept") > 0 } }) { com.limemessenger.lime.ui.calls.CallScreen(s, chats) }
    }
}
