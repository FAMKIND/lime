package com.limemessenger.lime.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.GroupAvatarKind
import uniffi.lime_core.groupAvatarPlan
import uniffi.lime_core.groupAvatarRingWidth
import uniffi.lime_core.groupAvatarSpots
import com.limemessenger.lime.ui.theme.Lime

private const val ME = "me"

/**
 * A group's picture: its emoji if it has one, else the other members and me as overlapping circles with a thin ring (the core's `group_avatar_plan` and
 * `group_avatar_spots`, the same numbers iOS draws). TalkBack skips it: the row says the name.
 */
@Composable
fun GroupAvatar(group: ConversationSummary, myName: String, myTone: Int, size: Dp = 52.dp) {
    val emoji = group.groupEmoji
    if (!emoji.isNullOrEmpty()) { Avatar(initialsOf(group.title), 0, size, emoji = emoji); return }
    val colors = Lime.colors
    val plan = groupAvatarPlan(group.members.map { it.id }, ME)
    val circles = plan.shown.size + (if (plan.extra > 0u) 1 else 0)
    val spots = groupAvatarSpots(circles.toUInt())
    val diameter = size * spots.diameter.toFloat()
    val ring = groupAvatarRingWidth(size.value.toDouble()).toFloat().dp
    Box(Modifier.size(size).background(colors.surface, CircleShape), contentAlignment = Alignment.Center) {
        // A single circle is just the person's avatar, filling it.
        fun person(id: String): Triple<String, Int, String> =
            if (id == ME) Triple(initialsOf(myName), myTone, myName) else group.members.first { it.id == id }.let { Triple(it.initials.ifEmpty { initialsOf(it.name) }, it.tone.toInt(), it.name) }
        // Pair: the plan lists [front, back] but the spots are in drawing order (the back one first): reverse it.
        val ordered = if (plan.kind == GroupAvatarKind.PAIR) plan.shown.reversed() else plan.shown
        ordered.forEachIndexed { index, id ->
            val spot = spots.centres[index]
            val (initials, tone) = person(id).let { it.first to it.second }
            Avatar(initials, tone, diameter, modifier = Modifier.offset(size * spot.x.toFloat(), size * spot.y.toFloat()).border(ring, colors.surface, CircleShape))
        }
        if (plan.extra > 0u) {
            val spot = spots.centres[3]
            Box(
                Modifier.size(diameter).offset(size * spot.x.toFloat(), size * spot.y.toFloat()).background(colors.hairline, CircleShape).border(ring, colors.surface, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                val density = androidx.compose.ui.platform.LocalDensity.current
                androidx.compose.material3.Text("+${plan.extra}", color = colors.text, style = glyphStyle(with(density) { (diameter * 0.38f).toSp() }), maxLines = 1)
            }
        }
    }
}
