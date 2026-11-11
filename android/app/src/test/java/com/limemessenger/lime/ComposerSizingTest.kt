package com.limemessenger.lime

import com.limemessenger.lime.ui.chat.ComposerSizing
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** LIME-406 C: the numbers of iOS's `ComposerSizingTests` (LIME-176), line = 20. */
class ComposerSizingTest {
    private val line = 20f
    private fun max(window: Float, keyboard: Float, top: Float = 0f, bottom: Float, strip: Boolean = false) = ComposerSizing.maxFieldHeight(window, keyboard, top, bottom, strip, line)
    private fun expanded(window: Float, keyboard: Float, top: Float, bottom: Float, strip: Boolean = false) = ComposerSizing.expandedFieldHeight(window, keyboard, top, bottom, strip, line)

    @Test fun withTheKeyboardUpTheComposerAndKeyboardTakeAboutThreeQuartersOfTheWindow() {
        assertEquals(844 * 0.75f, max(844f, 336f, bottom = 34f) + ComposerSizing.CHROME + 336, 1f)
    }

    @Test fun withTheKeyboardHiddenTheFieldIsTallerThanWithIt() {
        val up = max(844f, 336f, bottom = 34f)
        val down = max(844f, 0f, bottom = 34f)
        assertTrue(down > up)
        assertEquals(844 * 0.75f, down + ComposerSizing.CHROME + 34, 1f)
    }

    @Test fun theStripTakesItsHeightOutOfTheField() {
        assertEquals(ComposerSizing.STRIP_HEIGHT, max(844f, 336f, bottom = 34f) - max(844f, 336f, bottom = 34f, strip = true), 1f)
    }

    @Test fun neverUnderFiveLinesOnATallEnoughWindow() {
        assertEquals(116f, ComposerSizing.minimumHeight(line), 0f)
        assertTrue(max(812f, 500f, top = 47f, bottom = 34f) >= 116f)
    }

    @Test fun expandedGoesFromJustBelowTheHeaderToTheKeyboard() {
        val height = expanded(844f, 336f, 47f, 34f)
        assertEquals(844f, height + ComposerSizing.CHROME + 336 + 47 + ComposerSizing.HEADER_HEIGHT, 1f)
        assertTrue(height > max(844f, 336f, bottom = 34f))
    }

    @Test fun expandedWithTheKeyboardHiddenStopsAtTheNavigationBar() {
        assertEquals(844f, expanded(844f, 0f, 47f, 34f) + ComposerSizing.CHROME + 34 + 47 + ComposerSizing.HEADER_HEIGHT, 1f)
    }

    @Test fun aTabletWindowScalesWithItsHeight() {
        assertTrue(max(1194f, 0f, bottom = 20f) > max(600f, 0f, bottom = 20f))
    }

    private fun assertFits(window: Float, keyboard: Float, top: Float, bottom: Float, note: String) {
        for (strip in listOf(false, true)) {
            val below = if (keyboard > 0) keyboard else bottom
            val extra = ComposerSizing.CHROME + (if (strip) ComposerSizing.STRIP_HEIGHT else 0f)
            for ((what, height) in listOf("collapsed" to max(window, keyboard, top, bottom, strip), "expanded" to expanded(window, keyboard, top, bottom, strip))) {
                assertTrue("$note $what: one line always shows", height >= ComposerSizing.oneLineHeight(line))
                // Whenever one line fits at all, the composer stays between the header and the keyboard.
                if (window - top - ComposerSizing.HEADER_HEIGHT - below - extra >= ComposerSizing.oneLineHeight(line)) {
                    assertTrue("$note $what strip=$strip: fits under the header and above the keyboard", height + extra + below <= window - top - ComposerSizing.HEADER_HEIGHT + 1)
                }
            }
        }
    }

    @Test fun aLandscapePhoneWindowKeepsTheWholeComposerBetweenTheHeaderAndTheKeyboard() {
        assertFits(375f, 200f, 0f, 21f, "phone landscape, keyboard")
        assertFits(375f, 0f, 0f, 21f, "phone landscape, no keyboard")
    }

    @Test fun aTabletLandscapeAndASplitScreenWindowToo() {
        assertFits(834f, 420f, 24f, 20f, "tablet landscape, keyboard")
        assertFits(834f, 0f, 24f, 20f, "tablet landscape, no keyboard")
        assertFits(360f, 180f, 24f, 0f, "split screen, keyboard")
    }

    @Test fun portraitNumbersFrom176AreUnchanged() {
        assertEquals(218f, max(812f, 337f, top = 47f, bottom = 34f), 0f)
        assertEquals(521f, max(812f, 0f, top = 47f, bottom = 34f), 0f)
        assertEquals(318f, expanded(812f, 337f, 47f, 34f), 0f)
    }
}
