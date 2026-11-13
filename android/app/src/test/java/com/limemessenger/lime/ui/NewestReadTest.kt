package com.limemessenger.lime.ui

import com.limemessenger.lime.ui.common.NewestRead
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** LIME-417: the newest read wins: a slow read begun first and finished last never overwrites a faster, newer one. */
@OptIn(ExperimentalCoroutinesApi::class)
class NewestReadTest {
    @Test fun aSlowReadThatFinishesAfterAFastNewerOneIsDropped() = runTest {
        val reads = NewestRead()
        var shown = "nothing"
        val gate = CompletableDeferred<Unit>()
        val slow = launch { reads.read({ gate.await(); "old news" }) { shown = it } }   // starts first, waits
        advanceUntilIdle()
        assertTrue("the fast read is applied", reads.read({ "new news" }) { shown = it })
        assertEquals("new news", shown)
        gate.complete(Unit)
        slow.join()
        assertEquals("the slow, older read did not put old news back", "new news", shown)
    }

    @Test fun readsThatFinishInOrderAreAllApplied() = runTest {
        val reads = NewestRead()
        val seen = mutableListOf<Int>()
        for (i in 1..3) assertTrue(reads.read({ i }) { seen += it })
        assertEquals(listOf(1, 2, 3), seen)
    }

    @Test fun anOlderReadFinishingBeforeTheNewerOneIsStillApplied() = runTest {
        val reads = NewestRead()
        var shown = 0
        val gate = CompletableDeferred<Unit>()
        val newer = launch { reads.read({ gate.await(); 2 }) { shown = it } }   // (started later below, finishes last)
        // The first read takes its ticket before: start order decides, not arrival order.
        val first = reads.read({ 1 }) { shown = it }
        advanceUntilIdle()
        assertTrue(first); assertEquals(1, shown)
        gate.complete(Unit); newer.join()
        assertEquals("the later-started read is newer and wins when it arrives", 2, shown)
    }

    @Test fun aFailedReadDoesNotBlockTheNextOne() = runTest {
        val reads = NewestRead()
        var shown = "start"
        try { reads.read<String>({ error("storage unreadable") }) { shown = it } } catch (e: IllegalStateException) { }
        assertEquals("start", shown)
        assertFalse(shown == "never")
        assertTrue(reads.read({ "recovered" }) { shown = it })
        assertEquals("recovered", shown)
    }
}
