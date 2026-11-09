package com.limemessenger.lime.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * lime's colour tokens (values from iOS's asset catalog: `Canvas`, `Surface`, `OwnBubble`, `Accent`, ...). Palette: ink #131b17,
 * lime #09a950 (the one primary/live action per screen), #a3e18a, #e4f9be, #f0eee6, #f9f8f4. The lime green is never used for text
 * on a light surface (it fails 4.5:1); text on lime is ink. Customization (themes, per-chat looks) comes later (DESIGN-28).
 */
data class LimeColors(
    val canvas: Color,
    val surface: Color,
    val bubbleOther: Color,
    val bubbleEdge: Color,
    /** My bubble. */
    val own: Color,
    val ownInk: Color,
    /** The accent: unread badges, the primary action. */
    val accent: Color,
    val accentInk: Color,
    val text: Color,
    val textSecondary: Color,
    val hairline: Color,
    val link: Color,
    val linkOwn: Color,
    val pressed: Color,
    val chip: Color,
    val danger: Color,
    val dark: Boolean,
) {
    companion object {
        val Light = LimeColors(
            canvas = Color(0xFFF9F8F4), surface = Color(0xFFF0EEE6), bubbleOther = Color(0xFFFFFEFE), bubbleEdge = Color(0xFFDDDDD9),
            own = Color(0xFFE4F9BE), ownInk = Color(0xFF131B17), accent = Color(0xFFA3E18A), accentInk = Color(0xFF131B17),
            text = Color(0xFF131B17), textSecondary = Color(0xFF504840), hairline = Color(0xFFDDDDD9), link = Color(0xFF1B7A3A),
            linkOwn = Color(0xFF1F6B2E), pressed = Color(0xFFE0DCD0), chip = Color(0xFFF1EFE8), danger = Color(0xFFB3261E), dark = false,
        )
        val Dark = LimeColors(
            canvas = Color(0xFF131B17), surface = Color(0xFF212925), bubbleOther = Color(0xFF3D4441), bubbleEdge = Color(0xFF3D4441),
            own = Color(0xFF8ECF73), ownInk = Color(0xFF131B17), accent = Color(0xFFA3E18A), accentInk = Color(0xFF131B17),
            text = Color(0xFFF5F3ED), textSecondary = Color(0xFFA09890), hairline = Color(0xFF3D4441), link = Color(0xFF8ECF73),
            linkOwn = Color(0xFF0A5524), pressed = Color(0xFF2E332D), chip = Color(0xFF1B241F), danger = Color(0xFFFF8A80), dark = true,
        )

        /** The web app's avatar pastels (`--lime-avatar-0…7`), light and dark; index 5 is lime green. */
        private val avatarLight = longArrayOf(0xFEB2BF, 0xFED2CA, 0xF3BF91, 0xEFDF91, 0x92D4FF, 0xC4EFA6, 0xD9BAFF, 0x99EEFF)
        private val avatarDark = longArrayOf(0xDF8193, 0xEF9B8D, 0xC59770, 0xC3B571, 0x51ABE2, 0x7FBF5F, 0xB091D6, 0x78C2D1)
    }

    fun avatar(tone: Int): Color {
        val i = ((tone % 8) + 8) % 8
        return Color(0xFF000000 or (if (dark) avatarDark else avatarLight)[i])
    }
}
