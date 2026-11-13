package com.limemessenger.lime.debug

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/** Release builds have no design gallery: these twins of the debug source set do nothing. */
@Suppress("UNUSED_PARAMETER")
fun Modifier.designGalleryTrigger(onOpen: () -> Unit): Modifier = this

@Composable
@Suppress("UNUSED_PARAMETER")
fun DesignGallery(onBack: () -> Unit) {
}
