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

    @Test fun attachmentSummaries() {
        val photo = attachment("image/jpeg")
        assertNull(AttachmentFormat.summary(emptyList()))
        assertEquals("Photo", AttachmentFormat.summary(listOf(photo)))
        assertEquals("3 Photos", AttachmentFormat.summary(listOf(photo, photo, photo)))
        assertEquals("Video", AttachmentFormat.summary(listOf(attachment("video/mp4"))))
        // ("Voice message (0:12)" uses the core's voice_clock now: a JVM test cannot load the native library; VoiceFilesUiTest checks it.)
        assertEquals("Voice message", AttachmentFormat.summary(listOf(attachment("audio/mp4"))))
        assertEquals("Plan.pdf", AttachmentFormat.summary(listOf(attachment("application/pdf", "Plan.pdf"))))
        assertEquals("File", AttachmentFormat.summary(listOf(attachment("application/pdf"))))
        assertEquals("2 attachments", AttachmentFormat.summary(listOf(photo, attachment("video/mp4"))))
        assertEquals(AttachmentFormat.Symbol.Camera, AttachmentFormat.symbol(listOf(photo)))
        assertEquals(AttachmentFormat.Symbol.Paperclip, AttachmentFormat.symbol(listOf(photo, attachment("video/mp4"))))
        assertEquals(AttachmentFormat.Symbol.Mic, AttachmentFormat.symbol(listOf(attachment("audio/mp4"))))
    }

    // ListPreview

    @Test fun aPlainMessageIsItsWords() {
        val c = conversation(last = message("1", "See you **Friday**", from = "ben"))
        assertEquals("See you Friday", ListPreview.make(c, plain).plain)
    }

    @Test fun aGroupMessageNamesTheSenderByFirstName() {
        val c = conversation(group = true, title = "Staff", members = listOf(member("jean", "Jean Park")), last = message("1", "Hello", from = "jean"))
        assertEquals("Jean: Hello", ListPreview.make(c, plain).body)
        val mine = conversation(group = true, members = listOf(member("jean", "Jean Park")), last = message("2", "Hi all"))
        assertEquals("Hi all", ListPreview.make(mine, plain).body)  // my own plain message in a group has no prefix
    }

    @Test fun deletedAndSystemMessages() {
        assertEquals("This message was deleted", ListPreview.make(conversation(last = message("1", "x", from = "ben", deleted = true)), plain).body)
        assertEquals("Jean added Lee", ListPreview.make(conversation(last = message("1", "Jean added Lee", state = "system")), plain).body)
    }

    @Test fun attachmentsShowTheirSummaryThenTheWords() {
        val c = conversation(last = message("1", "Look", from = "ben", attachments = listOf(attachment("image/jpeg"))))
        val p = ListPreview.make(c, plain)
        assertEquals("Photo · Look", p.text); assertEquals(AttachmentFormat.Symbol.Camera, p.symbol)
        val only = conversation(last = message("2", "", from = "ben", attachments = listOf(attachment("image/jpeg"), attachment("image/png"))))
        assertEquals("2 Photos", ListPreview.make(only, plain).text)
    }

    @Test fun aReplyReadsLikeAQuote() {
        val root = message("root", "Who can cover recess duty?", from = "ben")
        val reply = message("r1", "I can", from = null, threadRoot = "root")
        val c = conversation(last = reply, lastIsReply = true)
        val p = ListPreview.make(c, plain) { id -> if (id == "root") root else null }
        assertEquals("Reply to Ben · Who can cover recess duty?", p.quote); assertEquals("You: I can", p.body)
        assertEquals("Reply in a thread", ListPreview.make(c, plain).quote)
    }

    @Test fun aReactionNewerThanTheLastMessage() {
        val theirs = ReactionActivity("❤️", "ben", "Ben Android", "m1", "True that", 5L)
        assertEquals("Ben reacted ❤️ to “True that”", ListPreview.make(conversation(reaction = theirs, last = message("m1", "True that")), plain).text)
        val mine = ReactionActivity("👍", null, "Ada", "m1", "", 5L)
        assertEquals("You reacted 👍 to a message", ListPreview.make(conversation(reaction = mine), plain).text)
        assertTrue(ListPreview.make(conversation(reaction = mine), plain).isReaction)
    }

    @Test fun noMessagesIsAnEmptyPreview() = assertEquals("", ListPreview.make(conversation(), plain).plain)

    // Unread rules

    // The unread rules moved into the core (list_rules.rs, with the Swift cases as Rust tests); a JVM unit test cannot load the native library.

    @Test fun avatarToneIsTheSameOnEveryPhone() {
        // The rule: hash = hash*31 + byte over the id's UTF-8, as UInt32, mod 8 (iOS AvatarTone).
        assertEquals(0, AvatarTone.tone(""))
        assertEquals(97 % 8, AvatarTone.tone("a"))
        assertEquals((97 * 31 + 98) % 8, AvatarTone.tone("ab"))
        val long = "df2546ac-69d5-4074-8ff8-7c5125976a17"
        var h = 0L; for (b in long.toByteArray()) h = (h * 31 + b) and 0xFFFFFFFFL
        assertEquals((h % 8).toInt(), AvatarTone.tone(long))
        assertTrue(AvatarTone.tone(long) in 0..7)
    }
}
