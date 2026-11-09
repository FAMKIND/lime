package com.limemessenger.lime.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.ui.theme.Lime

/** The first letters of a name, as the core makes them for a member ("Ada Android" → "AA"). */
fun initialsOf(name: String): String {
    val words = name.trim().split(" ").filter { it.isNotEmpty() }
    return when {
        words.isEmpty() -> "?"
        words.size == 1 -> words[0].take(1).uppercase()
        else -> (words.first().take(1) + words.last().take(1)).uppercase()
    }
}

/**
 * The avatar: initials in a pastel from the tone (ink on pastel, readable in light and dark). A group shows its emoji. TalkBack skips it:
 * the row says the name.
 */
@Composable
fun Avatar(initials: String, tone: Int, size: Dp = 52.dp, emoji: String? = null, modifier: Modifier = Modifier) {
    val colors = Lime.colors
    Box(
        modifier.size(size).background(if (emoji != null) colors.surface else colors.avatar(tone), CircleShape).clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        // The glyphs are sized from the circle (dp converted to sp), not from the font setting, so they never spill out of it at the largest text size.
        val density = androidx.compose.ui.platform.LocalDensity.current
        val emojiSize = with(density) { (size * 0.5f).toSp() }
        val initialsSize = with(density) { (size * 0.38f).toSp() }
        if (emoji != null) Text(emoji, fontSize = emojiSize)
        else Text(initials, color = androidx.compose.ui.graphics.Color(0xFF131B17), fontSize = initialsSize, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}
