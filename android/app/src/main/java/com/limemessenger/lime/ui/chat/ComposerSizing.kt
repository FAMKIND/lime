package com.limemessenger.lime.ui.chat

import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * How tall the composer's text field may be (iOS `ComposerSizing`, LIME-176), worked out from the window and the keyboard's real height, never fixed numbers. All in dp. A minimum never
 * beats the room really there (the 1e255 lesson): a short, landscape or split-screen window keeps the whole composer between the header and the keyboard, with one line at least.
 */
object ComposerSizing {
    /** Lines the field always has room for when the window allows it. */
    const val MINIMUM_LINES = 5f
    /** What the tool row, the paddings and the card around the field take. */
    const val CHROME = 54f
    /** The formatting strip under the row, while it shows. */
    const val STRIP_HEIGHT = 44f
    /** The header's height under the status bar, kept clear when the composer is expanded. */
    const val HEADER_HEIGHT = 56f
    /** The share of the window the composer and the keyboard may take together. */
    const val SHARE = 0.75f

    fun minimumHeight(line: Float): Float = line * MINIMUM_LINES + 16
    /** One line always shows (the field scrolls inside), whatever the window. */
    fun oneLineHeight(line: Float): Float = line + 16

    /** The room really there for the field: between the header and the keyboard (or the bottom), under the rest of the composer. */
    fun availableFieldHeight(window: Float, keyboard: Float, topInset: Float, bottomInset: Float, strip: Boolean): Float {
        val below = if (keyboard > 0) keyboard else bottomInset
        return window - topInset - HEADER_HEIGHT - below - CHROME - (if (strip) STRIP_HEIGHT else 0f)
    }

    /** The most the field grows to while writing: composer and keyboard about 75% of the window, never past the room really there, never under one line; five lines are kept when the room allows. */
    fun maxFieldHeight(window: Float, keyboard: Float, topInset: Float = 0f, bottomInset: Float, strip: Boolean, line: Float): Float {
        val below = if (keyboard > 0) keyboard else bottomInset
        val share = window * SHARE - below - CHROME - (if (strip) STRIP_HEIGHT else 0f)
        val available = availableFieldHeight(window, keyboard, topInset, bottomInset, strip)
        val floor = min(minimumHeight(line), available)
        return max(oneLineHeight(line), max(floor, min(floor(share), floor(available))))
    }

    /** The field's height when expanded: from just below the header to the keyboard (or the bottom). */
    fun expandedFieldHeight(window: Float, keyboard: Float, topInset: Float, bottomInset: Float, strip: Boolean, line: Float): Float =
        max(oneLineHeight(line), floor(availableFieldHeight(window, keyboard, topInset, bottomInset, strip)))
}
