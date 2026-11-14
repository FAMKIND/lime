package com.limemessenger.lime.ui.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** The sizes of the circle button: iOS's 44 pt visible circle, inside a 48 dp touch target (Android's minimum). */
object LimeCircle {
    val visible: Dp = 44.dp
    val target: Dp = 48.dp
    /** The floating plus on the Messages list: iOS 64 pt. */
    val fab: Dp = 64.dp
}

/**
 * lime's circle icon button (iOS `limeCircleIcon`): a 44 dp circle in the surface colour with a hairline, an icon, a required content description,
 * a 48 dp touch target. Android has no Liquid Glass: the circle is solid, with a soft shadow only when [overContent]. Pressed uses `pressed`.
 */
@Composable
fun LimeCircleButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    overContent: Boolean = false,
    /** The pressed look without a press (the design gallery shows it). */
    showPressed: Boolean = false,
) {
    val colors = Lime.colors
    val source = remember { MutableInteractionSource() }
    val pressed = source.collectIsPressedAsState().value || showPressed
    Box(
        modifier.size(LimeCircle.target).semantics { role = Role.Button; this.contentDescription = contentDescription; if (!enabled) disabled() }
            .clickable(interactionSource = source, indication = null, enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(LimeCircle.visible).then(if (overContent) Modifier.shadow(6.dp, LimeShapes.circle, clip = false) else Modifier)
                .background(if (pressed) colors.pressed else colors.surface, LimeShapes.circle).border(BorderStroke(0.5.dp, colors.hairline), LimeShapes.circle)
                .alpha(if (enabled) 1f else 0.4f),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, null, tint = colors.text, modifier = Modifier.size(22.dp)) }
    }
}

/**
 * The soft veil behind a floating header (iOS `TopFade`): the canvas colour fading out, about the header's height plus 10 dp. No hit testing
 * (a Box with no pointer handling passes touches through) and hidden from TalkBack.
 */
@Composable
fun LimeTopFade(modifier: Modifier = Modifier, headerHeight: Dp = 56.dp) {
    val canvas = Lime.colors.canvas
    Box(
        modifier.fillMaxWidth().height(headerHeight + 10.dp)
            .background(Brush.verticalGradient(0f to canvas.copy(alpha = 0.96f), 0.55f to canvas.copy(alpha = 0.6f), 1f to Color.Transparent))
            .clearAndSetSemantics { },
    )
}

private enum class FloatingSlot { Header, Content, Fade }

/**
 * A header that floats over the content with the soft top fade (iOS: circle controls over the content): the content is composed knowing the header's height (its list starts
 * under it) and the fade is as tall as the header plus 10 dp. The header is measured first, in the same pass as the content, so no state is written after layout (a
 * `onSizeChanged` that set a padding made a lazy list lay out twice and, now and then, keep a stale layout: LIME-424).
 */
@Composable
fun FloatingHeaderLayout(modifier: Modifier = Modifier, header: @Composable () -> Unit, content: @Composable (headerHeight: Dp) -> Unit) {
    androidx.compose.ui.layout.SubcomposeLayout(modifier) { constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val headerPlaceables = subcompose(FloatingSlot.Header, header).map { it.measure(loose) }
        val headerHeight = headerPlaceables.maxOfOrNull { it.height } ?: 0
        val headerDp = headerHeight.toDp()
        val contentPlaceables = subcompose(FloatingSlot.Content) { content(headerDp) }.map { it.measure(constraints) }
        val fadePlaceables = subcompose(FloatingSlot.Fade) { LimeTopFade(headerHeight = (headerDp - 10.dp).coerceAtLeast(0.dp)) }.map { it.measure(loose) }
        layout(constraints.maxWidth, constraints.maxHeight) {
            contentPlaceables.forEach { it.place(0, 0) }
            fadePlaceables.forEach { it.place(0, 0) }
            headerPlaceables.forEach { it.place(0, 0) }
        }
    }
}
