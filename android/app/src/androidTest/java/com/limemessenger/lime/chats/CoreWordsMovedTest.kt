package com.limemessenger.lime.chats

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.limemessenger.lime.chats.Samples.attachment
import com.limemessenger.lime.chats.Samples.conversation
import com.limemessenger.lime.chats.Samples.member
import com.limemessenger.lime.chats.Samples.message
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.ReactionActivity
import uniffi.lime_core.Reaction

/**
 * LIME-400: the Kotlin unit tests of rules that moved into LimeCore (chat words, delivery states and what TalkBack says for a message, the connection words),
 * run on a device because the rules are native now (a JVM test cannot load the library). The assertions are the ones the JVM tests had; the Rust tests in
 * `chat_words_rules.rs`, `message_speech_rules.rs` and `auth_rules.rs` carry the same cases. The one change: the symbol is the core's `AttachmentSymbol`.
 */
@RunWith(AndroidJUnit4::class)
class CoreWordsMovedTest {
    private val plain: (String) -> String = { it.replace("**", "") }
    private val clockOf = { _: Long -> "9:05 AM" }
    private fun found(self: Boolean = false) = uniffi.lime_core.FoundUser("u1", "Grace Ortiz", "grace.h", "Park School", null, null, self)

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
        assertEquals(uniffi.lime_core.AttachmentSymbol.CAMERA, AttachmentFormat.symbol(listOf(photo)))
        assertEquals(uniffi.lime_core.AttachmentSymbol.PAPERCLIP, AttachmentFormat.symbol(listOf(photo, attachment("video/mp4"))))
        assertEquals(uniffi.lime_core.AttachmentSymbol.MIC, AttachmentFormat.symbol(listOf(attachment("audio/mp4"))))
    }
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
        assertEquals("Photo · Look", p.text); assertEquals(uniffi.lime_core.AttachmentSymbol.CAMERA, p.symbol)
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
    @Test fun deliveryStatesMapFromTheCoresWords() {
        assertEquals(DeliveryState.Sending, DeliveryState.of("sending"))
        assertEquals(DeliveryState.Sent, DeliveryState.of("local"))   // the older local-only states count as sent
        assertTrue(DeliveryState.Offline.isInFlight); assertFalse(DeliveryState.Failed.isInFlight)
        assertEquals("Waiting for internet", DeliveryState.Offline.statusWords); assertNull(DeliveryState.Sent.statusWords)
    }
    @Test fun talkBackReadsOneStopPerMessage() {
        val clock = { _: Long -> "9:05 AM" }
        assertEquals("Ben Android, Hello there, 9:05 AM", MessageSpeech.label(message("1", "Hello there", "ben"), "Ben Android", plainText = plain, clock = clock))
        assertEquals("You, Hi, 9:05 AM, sending", MessageSpeech.label(message("2", "Hi", null, state = "sending"), null, plainText = plain, clock = clock))
        assertEquals("You, Hi, 9:05 AM, not sent, retry available", MessageSpeech.label(message("3", "Hi", null, state = "failed"), null, plainText = plain, clock = clock))
        assertEquals("Ben, This message was deleted", MessageSpeech.label(message("4", "x", "ben", deleted = true), "Ben", plainText = plain, clock = clock))
        assertEquals("Someone, Photo, 9:05 AM", MessageSpeech.label(message("5", "", "x", attachments = listOf(Samples.attachment("image/jpeg"))), null, plainText = plain, clock = clock))
        assertEquals("Ben, Hello, 9:05 AM, 2 replies, 1 unread", MessageSpeech.label(message("6", "Hello", "ben"), "Ben", replyCount = 2, unreplied = 1, plainText = plain, clock = clock))
        val reacted = message("7", "Hello", "ben").copy(reactions = listOf(Reaction("❤️", 2u, true, emptyList())))
        assertEquals("Ben, Hello, 9:05 AM, 2 reactions: ❤️ 2 (you)", MessageSpeech.label(reacted, "Ben", plainText = plain, clock = clock))
        assertEquals("Ben, Hello, 9:05 AM, edited", MessageSpeech.label(message("8", "Hello", "ben").copy(edited = true), "Ben", plainText = plain, clock = clock))
    }
    @Test fun aPhotoReadsWithItsDescription() {
        val withAlt = attachment("image/jpeg").copy(alt = "Students building a bridge")
        assertEquals("Photo: Students building a bridge", MessageSpeech.attachments(message("1", "", "ben", attachments = listOf(withAlt))))
        assertEquals("Photo", MessageSpeech.attachments(message("2", "", "ben", attachments = listOf(attachment("image/jpeg")))))
        assertEquals("2 photos", MessageSpeech.attachments(message("3", "", "ben", attachments = listOf(attachment("image/jpeg"), attachment("image/png")))))
    }
    @Test fun theLookupStatesAreSpokenAndTheLatestSearchWins() = runTest {
        val lookup = TeacherLookup()
        assertNull(lookup.state.spokenWords)
        lookup.run("grace.h") { found() }
        assertEquals("1 found", lookup.state.spokenWords)
        lookup.run("nobody_here") { null }
        assertEquals("No teacher found", lookup.state.spokenWords)
        lookup.run("grace.h") { throw uniffi.lime_core.StoreException.Network() }
        assertEquals("You're offline. Check your connection and try again.", lookup.state.spokenWords)
        lookup.run("@grace.h") { assertEquals("grace.h", it); null }
    }
}
