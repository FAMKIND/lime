package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.debug.DesignGallery
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** NOT a test: the LIME-420 gallery screenshots (light and dark halves; 100% and 200% font) into files/shots (`tools/shots-design.sh`). `@Staging` only so the plain pass skips it. */
@Staging
@RunWith(AndroidJUnit4::class)
class DesignGalleryShotsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val prefix get() = InstrumentationRegistry.getArguments().getString("prefix") ?: "x"

    private fun shot(name: String) {
        rule.waitForIdle(); Thread.sleep(600)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(File(context.filesDir, "shots").also { it.mkdirs() }, "$prefix-$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun at(tag: String) { rule.onNodeWithTag(tag, useUnmergedTree = true).performScrollTo(); shot(tag.removePrefix("gallery-")) }

    private fun run(font: Float, name: String) {
        rule.setContent {
            val d = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(d.density, font)) { LimeTheme(dark = false) { DesignGallery(onBack = {}) } }
        }
        rule.waitUntil(5_000) { rule.onAllNodes(hasTestTag("design-gallery")).fetchSemanticsNodes().isNotEmpty() }
        shot("$name-1-light-type")
        at("gallery-fade-list-light"); shot("$name-2-light-circles-fade")
        at("gallery-dark"); shot("$name-3-dark-type")
        at("gallery-fade-list-dark"); shot("$name-4-dark-circles-fade")
    }

    @Test fun font100() = run(1f, "font100")
    @Test fun font200() = run(2f, "font200")
}
