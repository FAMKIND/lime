package com.limemessenger.lime.ui.theme

import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/**
 * lime's shapes, from iOS: `Theme.bubbleRadius` 22; the most used card radii in the iOS views are 14 (54 uses), 16 (39), 12 (26), 20 (23) and 18 (17);
 * sheets use `presentationCornerRadius(28)`; the composer panel's top corners are 18; buttons and chips are capsules (181 `Capsule()` uses).
 */
object LimeShapes {
    val bubble = RoundedCornerShape(22.dp)
    /** The settings card, a profile card: iOS 20. */
    val card = RoundedCornerShape(20.dp)
    /** A row card, a link card, a toolbar group: iOS 14. */
    val cardSmall = RoundedCornerShape(14.dp)
    /** A text field, a report option: iOS 16. */
    val field = RoundedCornerShape(16.dp)
    /** A chip, a small tile: iOS 12. */
    val chip = RoundedCornerShape(12.dp)
    val pill = RoundedCornerShape(percent = 50)
    val circle = CircleShape
    /** A sheet's top corners: iOS 28. */
    val sheetTop = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    /** The composer panel's top corners: iOS 18. */
    val composerTop = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp)

    /** Material's five sizes from lime's: chip, row card, field, card, sheet. */
    val material = Shapes(
        extraSmall = RoundedCornerShape(12.dp), small = RoundedCornerShape(14.dp), medium = RoundedCornerShape(16.dp),
        large = RoundedCornerShape(20.dp), extraLarge = RoundedCornerShape(28.dp),
    )
}
