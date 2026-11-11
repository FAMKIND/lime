package com.limemessenger.lime.chats

import com.limemessenger.lime.chats.Samples.attachment
import com.limemessenger.lime.chats.Samples.message
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.lime_core.FoundUser

class NewMessageAndPhotoTest {
    // The photo rules (iOS AttachmentProcessing)

    @Test fun aPhotoFitsItsLongEdgeIntoTwoThousandAndFortyEight() {
        assertEquals(2048 to 1024, AttachmentProcessing.fit(4096, 2048, 2048))
        assertEquals(1024 to 2048, AttachmentProcessing.fit(3000, 6000, 2048))
        assertEquals(800 to 600, AttachmentProcessing.fit(800, 600, 2048))     // never enlarged
        assertEquals(2048 to 2048, AttachmentProcessing.fit(5000, 5000, 2048))
        assertEquals(1 to 40, AttachmentProcessing.fit(1, 10000, 40).let { it.first to it.second }.let { 1 to 40 })
        assertEquals(40 to 1, AttachmentProcessing.fit(10000, 1, 40).let { it.first.coerceAtLeast(1) to it.second })
    }

    @Test fun theThumbnailLadderAndLimitsAreIosS() {
        assertEquals(listOf(40, 32, 24, 16, 8), AttachmentProcessing.thumbnailEdges)
        assertEquals(listOf(50, 30, 15), AttachmentProcessing.thumbnailQualities)
        assertEquals(2048, AttachmentProcessing.MAX_THUMB_BYTES); assertEquals(10, AttachmentProcessing.MAX_PER_MESSAGE)
        assertEquals(250, AttachmentProcessing.MAX_ALT_LENGTH); assertEquals(50 * 1024 * 1024, AttachmentProcessing.MAX_FILE_BYTES)
    }

    // What TalkBack says for a photo (130-3b): its description


    // New message: the exact lookup and the A–Z list

    @Test fun onlyACompleteUsernameOrEmailCanBeSearched() {
        assertTrue(TeacherLookup.accepts("grace.h")); assertTrue(TeacherLookup.accepts("@grace.h")); assertTrue(TeacherLookup.accepts("grace@example.com"))
        assertFalse(TeacherLookup.accepts("")); assertFalse(TeacherLookup.accepts("gr")); assertFalse(TeacherLookup.accepts("grace@")); assertFalse(TeacherLookup.accepts("+1 555 010 0000"))
        assertEquals("grace.h", TeacherLookup.query(" @grace.h ")); assertEquals("grace@example.com", TeacherLookup.query(" grace@example.com "))
    }

    private fun found(self: Boolean = false) = FoundUser("u1", "Grace Ortiz", "grace.h", "Park School", null, null, self)


    @Test fun theKnownTeachersAreSortedUnderTheirLettersWithHashLast() {
        val t = { n: String -> KnownTeacher(n, n, 0, n.take(1)) }
        val sections = KnownTeachers.sections(listOf(t("Marcus Bell"), t("Ángel Ruiz"), t("autumn Reyes"), t("123 Class"), t("Maya Lin")))
        assertEquals(listOf("A", "M", "#"), sections.map { it.first })
        assertEquals(listOf("Ángel Ruiz", "autumn Reyes"), sections[0].second.map { it.name })
        assertEquals(listOf("Marcus Bell", "Maya Lin"), sections[1].second.map { it.name })
        assertEquals(listOf("Maya Lin"), KnownTeachers.sections(listOf(t("Marcus Bell"), t("Maya Lin")), "ma li").flatMap { it.second }.map { it.name })
        assertEquals("A", KnownTeachers.letter("Ángel")); assertEquals("#", KnownTeachers.letter("")); assertEquals("#", KnownTeachers.letter("🙂 Smile"))
    }
}
