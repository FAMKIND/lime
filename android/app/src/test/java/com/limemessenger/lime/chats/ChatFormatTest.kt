package com.limemessenger.lime.chats

import com.limemessenger.lime.chats.Samples.attachment
import com.limemessenger.lime.chats.Samples.conversation
import com.limemessenger.lime.chats.Samples.member
import com.limemessenger.lime.chats.Samples.message
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.lime_core.ReactionActivity

class ChatFormatTest {
    private val zone = ZoneId.of("America/New_York")
    private val locale = Locale.US
    private fun ms(y: Int, m: Int, d: Int, h: Int = 12, min: Int = 0) = ZonedDateTime.of(y, m, d, h, min, 0, 0, zone).toInstant().toEpochMilli()
    private val now = ms(2026, 11, 9, 15, 30)
    private val plain: (String) -> String = { it.replace("**", "") }

    // MessageFormat (the cases of iOS's MessageFormat)

    @Test fun listTimeIsTheClockTodayYesterdayThenTheDate() {
        assertEquals("9:05 AM", MessageFormat.listTime(ms(2026, 11, 9, 9, 5), now, zone, locale).replace(" ", " "))
        assertEquals("Yesterday", MessageFormat.listTime(ms(2026, 11, 8, 23, 59), now, zone, locale))
        assertEquals("Nov 7", MessageFormat.listTime(ms(2026, 11, 7), now, zone, locale))
        assertEquals("Jan 2", MessageFormat.listTime(ms(2026, 1, 2), now, zone, locale))
        assertEquals("", MessageFormat.listTime(null, now, zone, locale))
        assertEquals("", MessageFormat.listTime(0L, now, zone, locale))
    }

    @Test fun daySeparators() {
        assertEquals("Today", MessageFormat.day(ms(2026, 11, 9, 1), now, zone, locale))
        assertEquals("Yesterday", MessageFormat.day(ms(2026, 11, 8, 1), now, zone, locale))
        assertEquals("Tuesday, Nov 3", MessageFormat.day(ms(2026, 11, 3), now, zone, locale))
    }

    // AttachmentFormat


    // ListPreview








    // Unread rules

    // The unread rules moved into the core (list_rules.rs, with the Swift cases as Rust tests); a JVM unit test cannot load the native library.

}
