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
fun LimeTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val c = if (dark) LimeColors.Dark else LimeColors.Light
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
