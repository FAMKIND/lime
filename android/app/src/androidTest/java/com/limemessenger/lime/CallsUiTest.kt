package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.calls.CallFilter
import com.limemessenger.lime.calls.CallPrefs
import com.limemessenger.lime.calls.CallsModel
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.ListPreview
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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.CallLogEntry
import uniffi.lime_core.CallResult
import uniffi.lime_core.LimeStore

/** LIME-424: the Calls tab from a real core store and a seeded log: grouped rows, the missed badge, call back, filters, the empty states, the chat's call bubble and the settings. */
@RunWith(AndroidJUnit4::class)
class CallsUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private lateinit var calls: CallsModel
    private val alias = "lime.test.calls"
    private val placed = mutableListOf<Triple<String, String, Boolean>>()

    @Before fun setUp() {
        dir = File(context.cacheDir, "calls-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("calls-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
        calls = CallsModel { store }
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun entry(id: String, peer: String, name: String, ago: Long, result: CallResult, video: Boolean = false, outgoing: Boolean = false, seconds: Int = 0) =
        CallLogEntry(id, peer, name, video, outgoing, System.currentTimeMillis() - ago, seconds * 1000L, result)
    private val minute = 60_000L
    private fun seed() = runBlocking {
        // three missed calls from Ben a few minutes ago (one row, "(3)"), an answered one earlier the same day, a video call out to Sam, a silenced one from Lee
        calls.add(entry("m1", "ben", "Ben Test", 3 * minute, CallResult.MISSED))
        calls.add(entry("m2", "ben", "Ben Test", 4 * minute, CallResult.MISSED))
        calls.add(entry("m3", "ben", "Ben Test", 5 * minute, CallResult.MISSED))
        calls.add(entry("a1", "ben", "Ben Test", 6 * minute, CallResult.COMPLETED, seconds = 252))
        calls.add(entry("v1", "sam", "Sam Park", 2 * minute, CallResult.COMPLETED, video = true, outgoing = true, seconds = 31))
        calls.add(entry("s1", "lee", "Lee Wong", minute, CallResult.MISSED_DND))
    }
    private fun show() = rule.setContent { LimeTheme { CallsScreen(calls, chats, "Ada Android", 5, onProfile = {}, onSearch = {}, onPlaceCall = { id, name, video -> placed += Triple(id, name, video) }) } }
    private fun label(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
    private fun rows() = rule.onAllNodes(hasTestTag("call-history-row"), useUnmergedTree = true).fetchSemanticsNodes().map { it.config[SemanticsProperties.ContentDescription].joinToString() }

    @Test fun neighbouringCallsOfOnePersonFormOneRowWithACountAndMissedIsSaidInWords() {
        seed(); show()
        rule.waitUntil(5_000) { count("call-history-row") >= 4 }
        val all = rows()
        // newest first: Lee (silenced, minute ago), Sam, Ben x3 missed, Ben answered
        assertEquals(all.toString(), 4, all.size)
        assertTrue(all[0], all[0].startsWith("Lee Wong, voice call") && all[0].endsWith("Silenced · Do Not Disturb") && all[0].contains(", missed"))
        assertTrue(all[1], all[1].startsWith("Sam Park, video call") && !all[1].contains("missed"))
        assertTrue(all[2], all[2].startsWith("Ben Test (3), voice call") && all[2].contains(", missed"))
        assertTrue(all[3], all[3].startsWith("Ben Test, voice call") && !all[3].contains("missed"))
        // the word is on screen too, not only the colour (WCAG 1.4.1), and the note under the name
        assertEquals(2, count("call-row-missed"))
        rule.onNodeWithTag("call-row-note", useUnmergedTree = true).assertTextEquals("Silenced · Do Not Disturb")
    }

    @Test fun tappingARowOrItsButtonCallsBackTheSameWayTheCallWasMade() {
        seed(); show()
        rule.waitUntil(5_000) { count("call-history-row") >= 4 }
        rule.onAllNodes(hasTestTag("call-history-row"), useUnmergedTree = true)[1].performClick()   // Sam: a video call
        assertEquals(Triple("sam", "Sam Park", true), placed.last())
        rule.onAllNodes(hasTestTag("call-row-callback"), useUnmergedTree = true)[0].performClick()   // Lee: a voice call
        assertEquals(Triple("lee", "Lee Wong", false), placed.last())
    }

    @Test fun theMissedFilterAndTheKindFilterNarrowTheListAndEmptyStatesSayWhy() {
        seed(); show()
        rule.waitUntil(5_000) { count("call-history-row") >= 4 }
        rule.onNodeWithTag("calls-filter-missed", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("call-history-row") == 2 }
        assertTrue(rows().all { it.contains(", missed") })
        rule.onNodeWithTag("calls-filter-all", useUnmergedTree = true).performClick()
        runBlocking { calls.delete(listOf("m1", "m2", "m3", "s1")) }
        rule.onNodeWithTag("calls-filter-missed", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("calls-empty-missed") > 0 }
        rule.onNodeWithTag("calls-empty-missed", useUnmergedTree = true).assertTextEquals("No missed calls")
        rule.onNodeWithTag("calls-filter-all", useUnmergedTree = true).performClick()
        calls.filter = CallFilter(video = true)
        rule.waitUntil(5_000) { count("call-history-row") == 1 }
        calls.filter = CallFilter(video = false, incoming = false)
        rule.waitUntil(5_000) { count("calls-no-match") > 0 }
    }

    @Test fun anEmptyHistorySaysSoAndOffersANewCall() {
        show()
        rule.waitUntil(5_000) { count("calls-empty") > 0 }
        rule.onNodeWithTag("calls-empty", useUnmergedTree = true).assertTextEquals("No calls yet")
        rule.onNodeWithTag("calls-empty-new-call", useUnmergedTree = true).assertIsDisplayed()
        rule.onNodeWithTag("new-call-button", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("new-call-sheet") > 0 }
        // The people I message are listed with a voice and a video button each; the sample data has several.
        assertTrue(count("new-call-empty") == 0)
    }

    @Test fun theMissedBadgeCountsUnseenMissedCallsAndOpeningTheTabClearsIt() {
        seed()
        runBlocking { calls.reload() }
        assertEquals("three missed from Ben and one silenced from Lee", 4, calls.missedUnseen)
        rule.setContent {
            LimeTheme {
                Shell(link = {}, selected = Tab.Link, callsMissed = calls.missedUnseen, calls = { CallsScreen(calls, chats, "Ada", 5, {}, {}, { _, _, _ -> }) })
            }
        }
        rule.waitUntil(5_000) { count("tab-call-badge") > 0 }
        runBlocking { calls.markMissedSeen() }
        rule.waitUntil(5_000) { count("tab-call-badge") == 0 }
        assertEquals(0, calls.missedUnseen)
    }

    @Test fun aCallIsABubbleInItsChatAndAPreviewInTheList() {
        val dm = store.startDm("ben-test", "Ben Test")
        runBlocking { chats.reload() }
        runBlocking { calls.add(entry("c1", "ben-test", "Ben Test", minute, CallResult.MISSED)) }
        runBlocking { calls.add(entry("c2", "ben-test", "Ben Test", 30_000, CallResult.COMPLETED, outgoing = true, seconds = 252)) }
        runBlocking { chats.reload() }
        val chat = ChatModel(dm, chats, accountSignedIn = false)
        rule.setContent { LimeTheme { ChatScreen(chat, chats, onBack = {}, onCallBack = { id, name, video -> placed += Triple(id, name, video) }) } }
        rule.waitUntil(5_000) { count("call-bubble-title") >= 2 }
        val titles = rule.onAllNodes(hasTestTag("call-bubble-title"), useUnmergedTree = true).fetchSemanticsNodes().map { it.config[SemanticsProperties.Text].joinToString() }
        assertEquals(listOf("Missed voice call", "Voice call"), titles)
        val details = rule.onAllNodes(hasTestTag("call-bubble-detail"), useUnmergedTree = true).fetchSemanticsNodes().map { it.config[SemanticsProperties.Text].joinToString() }
        assertEquals(listOf("Missed", "4:12"), details)
        // The list says the same in one line, not the body's JSON.
        val summary = chats.conversations.first { it.id == dm }
        assertEquals("Voice call · 4:12", ListPreview.make(summary).body)
        // A tap asks before it calls back.
        rule.onAllNodes(hasTestTag("call-bubble-c1"), useUnmergedTree = true)[0].performClick()
        rule.waitUntil(5_000) { count("call-bubble-ask") > 0 }
        rule.onNodeWithTag("call-bubble-ask-call", useUnmergedTree = true).performClick()
        assertEquals(Triple("ben-test", "Ben Test", false), placed.last())
    }

    @Test fun theCallSettingsAreKeptAndTheVolumeStaysInRange() {
        val prefs = CallPrefs(context.getSharedPreferences("lime.calls.test", android.content.Context.MODE_PRIVATE).also { it.edit().clear().commit() })
        rule.setContent { LimeTheme { CallSettingsScreen(prefs, onBack = {}) } }
        rule.waitUntil(5_000) { count("calls-low-data") > 0 }
        rule.onNodeWithTag("calls-low-data", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { prefs.lowDataMode }
        assertEquals("100%", CallPrefs.percent(prefs.volume))
        prefs.changeVolume(9.0)
        assertEquals(2.0, prefs.volume, 0.0)
        prefs.changeVolume(0.0)
        assertEquals(0.5, prefs.volume, 0.0)
        rule.onNodeWithTag("calls-volume-value", useUnmergedTree = true).assertTextEquals("50%")
        rule.onNodeWithTag("calls-ring-note", useUnmergedTree = true).assertIsDisplayed()
    }
}
