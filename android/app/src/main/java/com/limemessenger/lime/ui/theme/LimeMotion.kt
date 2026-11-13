package com.limemessenger.lime.ui.theme

import android.content.ContentResolver
import android.content.Context
import android.provider.Settings
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

/**
 * Motion that respects "Remove animations" (animator duration scale 0; iOS's Reduce Motion, `Motion.swift`). The setting is read when something
 * would animate, so a change takes effect at once.
 */
object LimeMotion {
    fun reduced(resolver: ContentResolver): Boolean = Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f

    fun <T> spec(resolver: ContentResolver, normal: AnimationSpec<T> = tween(250)): AnimationSpec<T> = if (reduced(resolver)) snap() else normal

    /** Inside a composable: the same, for the current context. */
    @Composable
    fun <T> spec(normal: AnimationSpec<T> = tween(250)): AnimationSpec<T> = spec(LocalContext.current.contentResolver, normal)

    fun reduced(context: Context) = reduced(context.contentResolver)
}
