package com.limemessenger.lime.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

/**
 * lime's type, mapped from iOS (`Theme.swift`: `title` = body semibold, `body`, `secondary` = subheadline, `caption`, and the text styles
 * `Theme.font(.x, weight:)` used for headers). Sizes are iOS's default ("Large") Dynamic Type points as sp, so they follow the phone's font size
 * (Android has no lime-own text size or typeface setting yet: lime follows the system's font size, as Settings says). System font (Roboto), as iOS uses SF.
 */
object LimeType {
    /** One row of the iOS → Android table: the iOS style, its point size at the default step, its weight and the line height iOS sets for it. */
    data class Spec(val ios: String, val size: TextUnit, val weight: FontWeight, val line: TextUnit)

    val largeTitle = Spec("largeTitle", 34.sp, FontWeight.Normal, 41.sp)
    val titleBold = Spec("title bold", 28.sp, FontWeight.Bold, 34.sp)
    val screenTitle = Spec("title2 semibold", 22.sp, FontWeight.SemiBold, 28.sp)
    val sectionTitle = Spec("title3 semibold", 20.sp, FontWeight.SemiBold, 25.sp)
    /** lime's `title`: body, semibold: the name of a row, the title of an inline header. */
    val title = Spec("Theme.title (body semibold)", 17.sp, FontWeight.SemiBold, 22.sp)
    val body = Spec("Theme.body", 17.sp, FontWeight.Normal, 22.sp)
    /** `secondary`: subheadline. */
    val secondary = Spec("Theme.secondary (subheadline)", 15.sp, FontWeight.Normal, 20.sp)
    val secondaryStrong = Spec("subheadline semibold", 15.sp, FontWeight.SemiBold, 20.sp)
    val footnote = Spec("footnote", 13.sp, FontWeight.Normal, 18.sp)
    val caption = Spec("Theme.caption", 12.sp, FontWeight.Normal, 16.sp)
    val captionStrong = Spec("caption medium", 12.sp, FontWeight.Medium, 16.sp)
    val caption2 = Spec("caption2", 11.sp, FontWeight.Normal, 13.sp)

    /** Every style with its name, in the order the gallery shows them and the unit test checks them. */
    val all: List<Pair<String, Spec>> = listOf(
        "largeTitle" to largeTitle, "titleBold" to titleBold, "screenTitle" to screenTitle, "sectionTitle" to sectionTitle, "title" to title,
        "body" to body, "secondary" to secondary, "secondaryStrong" to secondaryStrong, "footnote" to footnote, "caption" to caption,
        "captionStrong" to captionStrong, "caption2" to caption2,
    )

    fun Spec.style() = TextStyle(fontSize = size, fontWeight = weight, lineHeight = line)

    /** Material's roles filled from lime's styles, so stock components (fields, buttons, bars) speak lime's type. */
    val typography = Typography(
        displayLarge = largeTitle.style(), displayMedium = titleBold.style(), displaySmall = screenTitle.style(),
        headlineLarge = titleBold.style(), headlineMedium = screenTitle.style(), headlineSmall = sectionTitle.style(),
        titleLarge = sectionTitle.style(), titleMedium = title.style(), titleSmall = secondaryStrong.style(),
        bodyLarge = body.style(), bodyMedium = secondary.style(), bodySmall = footnote.style(),
        labelLarge = secondaryStrong.style(), labelMedium = captionStrong.style(), labelSmall = caption2.style(),
    )
}
