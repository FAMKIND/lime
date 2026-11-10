package com.limemessenger.lime

import android.content.Context
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.AppearanceMode
import com.limemessenger.lime.chats.ThemePrefs
import com.limemessenger.lime.ui.settings.AppearanceScreen
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeTheme
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.ThemeBackground
import uniffi.lime_core.accentHex
import uniffi.lime_core.contrastNudge
import uniffi.lime_core.contrastRatio
import uniffi.lime_core.resolveTheme
import uniffi.lime_core.themeBackgrounds
import uniffi.lime_core.themePasses

/** LIME-307: the contrast guard, and a chosen accent and background applying across the app and persisting. */
@RunWith(AndroidJUnit4::class)
class AppearanceUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val app get() = context.applicationContext as LimeApp

    @Before fun setUp() { app.themePrefs.reset(); app.themePrefs.changeMode(AppearanceMode.Light) }
    @After fun tearDown() { app.themePrefs.reset(); app.themePrefs.changeMode(AppearanceMode.System) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun argb(hex: UInt) = Color(0xFF000000 or hex.toLong())

    @Test fun theGuardRejectsALowContrastPairAndEveryChoiceReadsAtAA() {
        // A pale grey on the canvas fails 4.5:1; the guard moves it until it passes and leaves good text alone.
        val canvas = 0xF9F8F4u
        assertTrue(contrastRatio(0xC9C5BCu, canvas) < 4.5)
        assertTrue(contrastRatio(contrastNudge(0xC9C5BCu, listOf(canvas), 4.5), canvas) >= 4.5)
        assertEquals(0x131B17u, contrastNudge(0x131B17u, listOf(canvas), 4.5))
        // Every accent on every background in light and dark (and with Increase Contrast) passes.
        for (accent in 0..7) for (background in themeBackgrounds()) for (dark in listOf(false, true)) for (increase in listOf(false, true)) {
            assertTrue("$accent $background dark=$dark increase=$increase", themePasses(resolveTheme(accent, background, dark, increase), increase))
        }
    }

    @Test fun aChosenAccentAndBackgroundApplyAcrossTheAppAndAreKept() {
        var canvas = Color.Unspecified; var accent = Color.Unspecified; var dark = false
        rule.setContent { LimeTheme { val c = Lime.colors; SideEffect { canvas = c.canvas; accent = c.accent; dark = c.dark }; AppearanceScreen(app.themePrefs, onBack = {}) } }
        rule.waitForIdle()
        // Lime's own look to begin with.
        assertEquals(argb(0xF9F8F4u), canvas); assertEquals(argb(0xA3E18Au), accent); assertFalse(dark)
        // Blue on Paper.
        rule.onNodeWithTag("accent-4").performScrollTo().performClick()
        rule.onNodeWithTag("background-paper").performScrollTo().performClick()
        rule.waitForIdle()
        val paper = resolveTheme(4, ThemeBackground.PAPER, false, false)
        assertEquals(argb(paper.canvas), canvas); assertEquals(argb(accentHex(4)), accent)
        assertNotEquals(argb(0xF9F8F4u), canvas)
        // Chalkboard is dark in light mode too.
        rule.onNodeWithTag("background-chalkboard").performScrollTo().performClick()
        rule.waitForIdle()
        assertEquals(argb(resolveTheme(4, ThemeBackground.CHALKBOARD, true, false).canvas), canvas); assertTrue(dark)
        // Kept on this phone: a fresh read of the preferences gives the choice back.
        val again = ThemePrefs(context.getSharedPreferences("lime.theme", Context.MODE_PRIVATE))
        assertEquals(4, again.accent); assertEquals(ThemeBackground.CHALKBOARD, again.background); assertFalse(again.isDefault)
        // Back to lime's own look.
        rule.onNodeWithTag("appearance-reset").performScrollTo().performClick()
        rule.waitForIdle()
        assertEquals(argb(0xF9F8F4u), canvas); assertEquals(argb(0xA3E18Au), accent); assertTrue(app.themePrefs.isDefault)
    }

    @Test fun darkAndLightFollowTheChoiceNotThePhone() {
        var dark = false
        rule.setContent { LimeTheme { val c = Lime.colors; SideEffect { dark = c.dark }; AppearanceScreen(app.themePrefs, onBack = {}) } }
        rule.waitForIdle(); assertFalse(dark)
        rule.onNodeWithTag("appearance-dark").performClick(); rule.waitForIdle(); assertTrue(dark)
        rule.onNodeWithTag("appearance-light").performClick(); rule.waitForIdle(); assertFalse(dark)
    }
}
