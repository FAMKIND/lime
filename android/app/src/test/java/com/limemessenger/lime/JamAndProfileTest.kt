package com.limemessenger.lime

import com.limemessenger.lime.auth.FieldEditorModel
import com.limemessenger.lime.auth.Profile
import com.limemessenger.lime.auth.ProfileField
import com.limemessenger.lime.chats.Samples.jam
import com.limemessenger.lime.chats.Samples.jamPost
import com.limemessenger.lime.jam.JamDates
import com.limemessenger.lime.jam.JamModel
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class JamAndProfileTest {
    private val zone = ZoneId.of("America/New_York")
    private fun ms(y: Int, m: Int, d: Int) = ZonedDateTime.of(y, m, d, 12, 0, 0, 0, zone).toInstant().toEpochMilli()
    private val now = ms(2026, 11, 9)

    // Jam dates (iOS JamDates)

    @Test fun datesShowTheYearOnlyWhenItIsNotThisYear() {
        assertEquals("Oct 22", JamDates.short(ms(2026, 10, 22), now, zone, Locale.US))
        assertEquals("Oct 22, 2025", JamDates.short(ms(2025, 10, 22), now, zone, Locale.US))
        assertEquals("October 22", JamDates.spoken(ms(2026, 10, 22), now, zone, Locale.US))
        assertEquals("October 22, 2025", JamDates.spoken(ms(2025, 10, 22), now, zone, Locale.US))
    }

    // The feed (iOS jamFeed)

    @Test fun theFeedHoldsTheReadyPostsOfActiveAndOwnJamsNewestFirst() {
        val jams = listOf(jam("a"), jam("b", status = "requested"), jam("c", mine = true, status = "active"), jam("d", status = "removed"))
        val posts = listOf(
            jamPost("p1", "a", at = 100), jamPost("p2", "b", at = 900), jamPost("p3", "c", at = 300), jamPost("p4", "d", at = 400),
            jamPost("p5", "a", at = 200, state = "pending"), jamPost("p1", "a", at = 100),
        )
        assertEquals(listOf("p3", "p1"), JamModel.feed(posts, jams).map { it.postId })   // requested/removed jams, a post still arriving, and a repeat are out
    }

    @Test fun bylineNamesTheCoauthors() {
        assertNull(JamModel.byline(emptyList()))
        assertEquals("with Jean Chung", JamModel.byline(listOf("Jean Chung")))
        assertEquals("with Jean Chung and Lee Wong", JamModel.byline(listOf("Jean Chung", "Lee Wong")))
        assertEquals("with A, B and C", JamModel.byline(listOf("A", "B", "C")))
    }

    @Test fun anExcerptIsCutAtAWord() {
        val long = jamPost("p", plain = "word ".repeat(100))
        val cut = JamModel.excerpt(long, 50)
        assertTrue(cut.endsWith("…") && cut.length <= 51 && !cut.dropLast(1).endsWith(" "))
        assertEquals("A short post", JamModel.excerpt(jamPost("q")))
        assertEquals("The subtitle", JamModel.excerpt(jamPost("r", kind = "article", subtitle = "The subtitle", plain = "Body text here")))
    }

    // Editing my profile (iOS FieldEditorModel)

    private val me = Profile("Ada Android", "ada_android", "Park School", "👋", "Happy to help")

    @Test fun nameRules() {
        val m = FieldEditorModel(ProfileField.Name, me)
        assertFalse(m.hasChange); assertFalse(m.canSave); assertEquals("Edit Name", m.title)
        m.text = "  "; assertEquals("Your name can't be empty.", m.validationMessage); assertFalse(m.canSave)
        m.text = "x".repeat(41); assertEquals("Use at most 40 characters.", m.validationMessage)
        m.text = "Ada K"; assertTrue(m.canSave); assertEquals("Ada K", m.draft().displayName)
        assertEquals("Your name is visible to teachers you message.", m.footer)
    }

    @Test fun aboutCountsItsEmojiAsOneAndKeepsTheOtherFields() {
        val m = FieldEditorModel(ProfileField.About, me)
        assertEquals("About (${140 - 14})", m.title)         // 13 letters + the emoji
        m.applyPreset(com.limemessenger.lime.auth.AboutPreset.all[1])
        assertEquals("📚", m.emoji); assertEquals("Planning lessons", m.text); assertTrue(m.canSave)
        val draft = m.draft()
        assertEquals("📚", draft.aboutEmoji); assertEquals("Planning lessons", draft.aboutText)
        assertEquals("Ada Android", draft.displayName); assertEquals("ada_android", draft.username); assertEquals("Park School", draft.school)
        m.text = "x".repeat(141); assertEquals("About is at most 140 characters.", m.validationMessage)
        m.text = "ok"; m.emoji = "👋📚"; assertEquals("Use a single emoji.", m.validationMessage)
        m.pickEmoji("🍎📝"); assertEquals("📝", m.emoji); assertNull(m.validationMessage)
    }

    @Test fun usernameAndSchoolRules() {
        val u = FieldEditorModel(ProfileField.Username, me)
        u.text = "@ab"; assertEquals("Use 3 to 20 characters.", u.validationMessage)
        u.text = "@ada.k"; assertNull(u.validationMessage); assertEquals("ada.k", u.draft().username)
        u.text = ""; assertEquals("", u.draft().username)             // clearing it sends an empty one
        val s = FieldEditorModel(ProfileField.School, me)
        s.text = "x".repeat(121); assertEquals("Use at most 120 characters.", s.validationMessage)
        s.text = "North High"; assertEquals("North High", s.draft().school); assertEquals("Ada Android", s.draft().displayName)
    }
}
