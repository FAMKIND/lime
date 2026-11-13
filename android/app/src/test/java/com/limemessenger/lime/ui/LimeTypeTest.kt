package com.limemessenger.lime.ui

import com.limemessenger.lime.ui.theme.LimeCircle
import com.limemessenger.lime.ui.theme.LimeType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** LIME-420: the Typography matches the recorded iOS → sp table (iOS's default Dynamic Type points), and the circle button's target is 48 dp. */
class LimeTypeTest {
    @Test
    fun theStylesMatchTheRecordedIosTable() {
        val table = mapOf(
            "largeTitle" to 34f, "titleBold" to 28f, "screenTitle" to 22f, "sectionTitle" to 20f, "title" to 17f, "body" to 17f, "secondary" to 15f,
            "secondaryStrong" to 15f, "footnote" to 13f, "caption" to 12f, "captionStrong" to 12f, "caption2" to 11f,
        )
        assertEquals(table.keys, LimeType.all.map { it.first }.toSet())
        for ((name, spec) in LimeType.all) assertEquals(name, table.getValue(name), spec.size.value, 0f)
        // lime's own words: title is body semibold, secondary is the subheadline, caption the caption.
        assertEquals(LimeType.body.size, LimeType.title.size)
        assertEquals(androidx.compose.ui.text.font.FontWeight.SemiBold, LimeType.title.weight)
        // Material's roles are filled from them.
        val t = LimeType.typography
        assertEquals(17f, t.bodyLarge.fontSize.value, 0f)
        assertEquals(15f, t.bodyMedium.fontSize.value, 0f)
        assertEquals(12f, t.labelMedium.fontSize.value, 0f)
    }

    @Test
    fun theCircleButtonTargetIsAtLeast48dpAndTheCircleIs44() {
        assertTrue(LimeCircle.target.value >= 48f)
        assertEquals(44f, LimeCircle.visible.value, 0f)
    }
}
