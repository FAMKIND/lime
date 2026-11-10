package com.limemessenger.lime.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf

val LocalLimeColors = staticCompositionLocalOf { LimeColors.Light }

object Lime {
    val colors: LimeColors @Composable @ReadOnlyComposable get() = LocalLimeColors.current
}

/** Material 3 mapped onto lime's tokens, so stock components (bars, fields, buttons) already look like lime. System font (Roboto), as iOS uses SF. */
@Composable
fun LimeTheme(dark: Boolean? = null, content: @Composable () -> Unit) {
    // The person's choice (Appearance): light, dark or the phone's; an accent; a background. Lime's own look when nothing was chosen.
    val prefs = (androidx.compose.ui.platform.LocalContext.current.applicationContext as? com.limemessenger.lime.LimeApp)?.themePrefs
    val system = isSystemInDarkTheme()
    val wantsDark = dark ?: when (prefs?.mode) {
        com.limemessenger.lime.chats.AppearanceMode.Light -> false
        com.limemessenger.lime.chats.AppearanceMode.Dark -> true
        else -> system
    }
    val background = prefs?.background ?: uniffi.lime_core.ThemeBackground.PLAIN
    // Chalkboard is dark in both modes: the whole app is drawn dark on it.
    val isDark = wantsDark || uniffi.lime_core.themeBackgroundForcesDark(background)
    val c = if (prefs == null || prefs.isDefault) (if (isDark) LimeColors.Dark else LimeColors.Light)
    else LimeColors.from(uniffi.lime_core.resolveTheme(prefs.accent, background, isDark, false), isDark)
    val dark = isDark
    val scheme = if (dark) {
        darkColorScheme(
            primary = c.accent, onPrimary = c.accentInk, background = c.canvas, onBackground = c.text, surface = c.canvas, onSurface = c.text,
            surfaceVariant = c.surface, onSurfaceVariant = c.textSecondary, outline = c.hairline, outlineVariant = c.hairline,
            error = c.danger, secondaryContainer = c.pressed, onSecondaryContainer = c.text, surfaceContainer = c.surface,
        )
    } else {
        lightColorScheme(
            primary = c.accent, onPrimary = c.accentInk, background = c.canvas, onBackground = c.text, surface = c.canvas, onSurface = c.text,
            surfaceVariant = c.surface, onSurfaceVariant = c.textSecondary, outline = c.hairline, outlineVariant = c.hairline,
            error = c.danger, secondaryContainer = c.pressed, onSecondaryContainer = c.text, surfaceContainer = c.surface,
        )
    }
    CompositionLocalProvider(LocalLimeColors provides c) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
