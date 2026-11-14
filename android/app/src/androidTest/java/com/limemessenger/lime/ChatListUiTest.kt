package com.limemessenger.lime

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.printToString
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.chats.ChatListScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore

/** The Messages list from a real core store: empty, with the core's sample chats, unread badges, filters, the largest font. */
@RunWith(AndroidJUnit4::class)
class ChatListUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var model: ChatsModel
    private val alias = "lime.test.list"
    private var opened: String? = null

    @Before fun setUp() {
        dir = File(context.cacheDir, "list-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("list-user")).store
        model = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
    }

    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun show(fontScale: Float = 1f) {
        rule.setContent {
            val d = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(d.density, fontScale)) {
                LimeTheme {
                    ChatListScreen(model, myName = "Ada Android", onOpen = { opened = it.id; runBlocking { model.markRead(it.id) } })
                }
            }
        }
        rule.runOnIdle { runBlocking { model.reload() } }
    }

    /** Rows are one merged TalkBack stop, so a row's parts are looked up in the unmerged tree. */
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun inner(tag: String) = rule.onNode(hasTestTag(tag), useUnmergedTree = true)

    @Test fun anEmptyStoreShowsTheGetStartedCards() {
        show()
        rule.waitUntil(5_000) { count("empty-title") > 0 }
        rule.onNodeWithTag("card-find").assertIsDisplayed()
        rule.onNodeWithTag("card-new-message").assertIsDisplayed()
        rule.onNodeWithTag("card-invite").performClick()
        rule.onNodeWithTag("coming-soon-note").assertIsDisplayed()
    }

    @Test fun theCoresSampleChatsAreListedPinnedFirstWithUnreadBadges() {
        store.seedSampleDataIfEmpty()
        show()
        rule.waitUntil(5_000) { count("messages-list") > 0 && model.chats.size >= 4 }
        val ids = model.chats.map { it.title }
        assertEquals("Journey Park", ids.first())          // pinned first, as the core orders it
        inner("row-title-${model.chats[0].id}").assertIsDisplayed()
        val autumn = model.chats.first { it.title == "Autumn Reyes" }
        inner("count-badge-${autumn.id}").assertIsDisplayed()
        inner("pinned-${model.chats[0].id}").assertIsDisplayed()
        assertEquals(2, model.unreadChatCount)
        // One TalkBack stop per row: the row's description carries name, state, preview, time and the unread count.
        val config = rule.onNodeWithTag("conversation-row-${autumn.id}").fetchSemanticsNode().config
        val description = config[androidx.compose.ui.semantics.SemanticsProperties.ContentDescription].joinToString()
        assertTrue(description, description.startsWith("Autumn Reyes") && description.contains("2 unread") && description.contains("exit tickets"))
    }

    @Test fun openingAChatClearsItsUnreadBadge() {
        store.seedSampleDataIfEmpty()
        show()
        rule.waitUntil(5_000) { model.chats.any { it.title == "Autumn Reyes" } }
        val autumn = model.chats.first { it.title == "Autumn Reyes" }
        rule.onNodeWithTag("conversation-row-${autumn.id}").performClick()
        rule.waitUntil(5_000) { count("count-badge-${autumn.id}") == 0 }
        assertEquals(autumn.id, opened)
        assertEquals(1, model.unreadChatCount)
    }

    @Test fun theUnreadFilterShowsOnlyUnreadAndSaysSoWhenNothingMatches() {
        store.seedSampleDataIfEmpty()
        show()
        rule.waitUntil(5_000) { model.chats.size >= 4 }
        rule.onNodeWithTag("chat-filter-unread").performClick()
        rule.waitForIdle()   // idle, not a clock: the filter is applied and drawn once the UI is idle
        assertEquals(2, model.shownChats.size)
        assertEquals(setOf("Journey Park", "Autumn Reyes"), model.shownChats.map { it.title }.toSet())
        runBlocking { model.chats.filter { it.unread > 0u }.forEach { model.markRead(it.id) } }
        rule.waitForIdle()
        // The marks-read reload lands on the model's own coroutine: wait for the state on screen, not for a clock (LIME-422: an order-dependent miss in one full pass).
        // If it ever fails, the report says what the model held and what was on screen (an intermittent miss seen in full passes since LIME-422).
        try { rule.waitUntil(5_000) { count("filtered-empty") > 0 } } catch (e: Throwable) {
            val info = com.limemessenger.lime.ui.chats.listStateProbe?.layoutInfo
            throw AssertionError("visible=${info?.visibleItemsInfo?.map { it.key to it.size }} total=${info?.totalItemsCount} viewport=${info?.viewportSize} shown=${model.shownChats.size} chats=${model.chats.size} unread=${model.chats.count { it.unread > 0u }} unreadOnly=${model.unreadOnly} loaded=${model.isLoaded} requests=${model.requests.size}\n" + rule.onRoot(useUnmergedTree = true).printToString(), e)
        }
        assertTrue("with nothing unread the filtered list says so", count("filtered-empty") > 0)
        rule.onNodeWithTag("filtered-empty").assertIsDisplayed()
        rule.onNodeWithTag("chat-filter-all").performClick()
        rule.waitForIdle()
        assertTrue(model.shownChats.size >= 4)
        assertFalse(model.unreadOnly)
    }

    @Test fun theLargestFontStillShowsTheRows() {
        store.seedSampleDataIfEmpty()
        show(fontScale = 2f)
        rule.waitUntil(5_000) { model.chats.size >= 4 }
        inner("row-title-${model.chats[0].id}").assertIsDisplayed()
        rule.onNodeWithTag("my-avatar").assertIsDisplayed()
    }
}
