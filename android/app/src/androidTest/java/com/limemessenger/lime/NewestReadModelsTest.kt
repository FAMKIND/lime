package com.limemessenger.lime

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.GroupModel
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.chats.Samples
import com.limemessenger.lime.storage.StorageBootstrap
import java.io.File
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore

/**
 * LIME-417: for each model that reads asynchronously and sets state from it, the SAME story: a slow read starts, a fast newer read starts and finishes, then the slow one finishes: what is shown must be the
 * fast one's. Each test fails without the model's guard (checked once by removing the chat model's guard: see the record). Real local store and the core's sample data; the reads' speed is the test's (a hook).
 */
@RunWith(AndroidJUnit4::class)
class NewestReadModelsTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private val alias = "lime.test.newestread"

    @Before fun setUp() {
        dir = File(context.cacheDir, "newestread-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("newestread-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    @Test fun theChatListKeepsTheFastReadsNews() = runBlocking {
        val real = chats.conversations
        assertTrue(real.size >= 4)
        val gate = CompletableDeferred<Unit>()
        val calls = AtomicInteger(0)
        chats.listHook = { if (calls.incrementAndGet() == 1) { gate.await(); real } else real.take(1) }   // the first (slow) read still sees all the chats; the newer one sees one
        val slow = async { chats.reload() }
        while (calls.get() < 1) kotlinx.coroutines.delay(10)
        chats.reload()   // fast and newer
        assertEquals(1, chats.conversations.size)
        gate.complete(Unit); slow.await()
        assertEquals("the slow, older read did not put the old list back", 1, chats.conversations.size)
    }

    @Test fun anOpenChatKeepsTheFastReadsMessages() = runBlocking {
        val id = chats.chats.first { it.title == "Autumn Reyes" }.id
        val model = ChatModel(id, chats, accountSignedIn = false)
        model.reload()
        val real = model.messages
        assertTrue(real.size >= 2)
        val gate = CompletableDeferred<Unit>()
        val calls = AtomicInteger(0)
        model.readHook = { if (calls.incrementAndGet() == 1) { gate.await(); real.take(1) to emptyMap() } else real to emptyMap() }   // slow = older (one message), fast = newer (all)
        val slow = async { model.reload() }
        while (calls.get() < 1) kotlinx.coroutines.delay(10)
        model.reload()
        assertEquals(real.size, model.messages.size)
        gate.complete(Unit); slow.await()
        assertEquals("the older read did not put the shorter list back", real.size, model.messages.size)
    }

    @Test fun theJamFeedKeepsTheFastReadsPosts() = runBlocking {
        val calls = AtomicInteger(0)
        val gate = CompletableDeferred<Unit>()
        val jam = Samples.jam("j1", "Notes")
        val old = emptyList<uniffi.lime_core.JamPostInfo>()
        val fresh = listOf(Samples.jamPost("p1", "j1"))
        val model = JamModel({ store }, { "Ben" }, source = { if (calls.incrementAndGet() == 1) { gate.await(); listOf(jam) to old } else listOf(jam) to fresh })
        val slow = async { model.reload() }
        while (calls.get() < 1) kotlinx.coroutines.delay(10)
        model.reload()
        assertEquals(1, model.posts.size)
        gate.complete(Unit); slow.await()
        assertEquals("the older (empty) feed did not replace the newer one", 1, model.posts.size)
    }

    @Test fun aGroupsDetailsKeepTheFastReadsMembers() = runBlocking {
        val group = chats.conversations.first { it.isGroup }.id
        val model = GroupModel(chats, group)
        val fresh = uniffi.lime_core.GroupDetails(group, "Fresh name", null, false, "owner", emptyList(), true, true, 500u)
        val stale = fresh.copy(name = "Stale name")
        val gate = CompletableDeferred<Unit>()
        val calls = AtomicInteger(0)
        model.detailsHook = { if (calls.incrementAndGet() == 1) { gate.await(); stale } else fresh }   // the slow read began before a rename; the fast one after
        val slow = async { model.refresh() }
        while (calls.get() < 1) kotlinx.coroutines.delay(10)
        model.refresh()
        assertEquals("Fresh name", model.details!!.name)
        gate.complete(Unit); slow.await()
        assertEquals("the older details did not put the stale name back", "Fresh name", model.details!!.name)
    }
}
