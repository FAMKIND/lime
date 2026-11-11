package com.limemessenger.lime.chats

import com.limemessenger.lime.chats.Samples.message
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.lime_core.Reaction

class ChatRowsTest {
    private val zone = ZoneId.of("America/New_York")
    private fun ms(d: Int, h: Int, min: Int = 0) = ZonedDateTime.of(2026, 11, d, h, min, 0, 0, zone).toInstant().toEpochMilli()
    private val now = ms(9, 15)
    private fun rows(vararg m: uniffi.lime_core.MessageItem) = ChatRow.rows(m.toList(), now, zone, Locale.US)
    private val plain: (String) -> String = { it }

    @Test fun aNewDayStartsWithASeparator() {
        val r = rows(message("1", "a", "ben", ms(8, 10)), message("2", "b", "ben", ms(9, 9)))
        assertEquals(listOf("Yesterday", "Today"), r.filterIsInstance<ChatRow.Day>().map { it.text })
        assertEquals(4, r.size)
    }

    @Test fun theAvatarShowsOnTheFirstOfARunOfIncomingMessages() {
        val r = rows(message("1", "a", "ben", ms(9, 9)), message("2", "b", "ben", ms(9, 9, 1)), message("3", "c", null, ms(9, 9, 2)), message("4", "d", "ben", ms(9, 9, 3)))
        val m = r.filterIsInstance<ChatRow.Message>()
        assertEquals(listOf(true, false, false, true), m.map { it.showAvatar })   // mine never shows one
    }

    @Test fun onlyTheEndOfARunShowsItsTime() {
        val r = rows(message("1", "a", "ben", ms(9, 9, 0)), message("2", "b", "ben", ms(9, 9, 2)), message("3", "c", "ben", ms(9, 9, 20)), message("4", "d", null, ms(9, 9, 21)))
        assertEquals(listOf(false, true, true, true), r.filterIsInstance<ChatRow.Message>().map { it.endsRun })  // 2 min apart: same run; 18 min later: a new one
    }

    @Test fun systemLinesAreCentredAndBreakARun() {
        val r = rows(message("1", "a", "jean", ms(9, 9)), message("2", "Jean added Lee", state = "system", at = ms(9, 9, 1)), message("3", "b", "jean", ms(9, 9, 2)))
        assertTrue(r[2] is ChatRow.System)
        assertTrue((r[3] as ChatRow.Message).showAvatar)
    }

    @Test fun deletedMessagesCollapseWhenTwoOrMore() {
        val d = { id: String, t: Long -> message(id, "x", "ben", t, deleted = true) }
        val two = rows(message("0", "hi", "ben", ms(9, 8)), d("1", ms(9, 9)), d("2", ms(9, 9, 1)))
        assertEquals(3, two.size)
        assertEquals(2, (two.last() as ChatRow.DeletedRun).count)
        val one = rows(d("1", ms(9, 9)))
        assertTrue(one.last() is ChatRow.Message)
    }


}
