package com.limemessenger.lime.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.AvatarTone
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import uniffi.lime_core.MentionSuggestion

/**
 * The list that floats above the composer while "@" is typed (iOS `MentionSuggestions`, LIME-181c): its own panel over the messages, not part of the card, which keeps its height, and a
 * separate window that does not take focus, so tapping a row never puts the keyboard away. About five rows then it scrolls; fewer when the room above the card is short (landscape),
 * so it never goes under the header. Announced to TalkBack as "Suggestions, 3 people".
 */
@Composable
fun MentionPanel(suggestions: List<MentionSuggestion>, room: androidx.compose.ui.unit.Dp, onPick: (MentionSuggestion) -> Unit) {
    if (suggestions.isEmpty()) return
    val colors = Lime.colors
    val density = LocalDensity.current
    val row = 52.dp
    val height = maxOf(row, minOf(row * 5, room, row * suggestions.size))
    val gap = 8.dp
    val label = if (suggestions.size == 1) stringResource(R.string.mention_suggestions_one) else stringResource(R.string.mention_suggestions, suggestions.size)
    Popup(alignment = Alignment.TopStart, offset = IntOffset(0, -with(density) { (height + gap).roundToPx() }), properties = PopupProperties(focusable = false, clippingEnabled = false)) {
        Column(
            Modifier.width(with(density) { androidx.compose.ui.platform.LocalWindowInfo.current.containerSize.width.toDp() } - 24.dp).padding(horizontal = 0.dp).heightIn(max = height)
                .shadow(8.dp, RoundedCornerShape(20.dp), clip = false).clip(RoundedCornerShape(20.dp)).background(colors.surface)
                .verticalScroll(rememberScrollState()).semantics { contentDescription = label; liveRegion = LiveRegionMode.Polite }.testTag("mention-suggestions"),
        ) {
            suggestions.forEach { s ->
                val spoken = if (s.isEveryone) stringResource(R.string.mention_everyone_spoken) else s.username?.let { "${s.name}, @$it" } ?: s.name
                Row(
                    Modifier.fillMaxWidth().heightIn(min = row).semantics(mergeDescendants = true) { contentDescription = spoken; role = Role.Button }.clickable { onPick(s) }
                        .padding(horizontal = 16.dp, vertical = 6.dp).testTag("mention-suggestion-${s.id}"),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    if (s.isEveryone) Box(Modifier.size(32.dp).background(colors.pressed, CircleShape), contentAlignment = Alignment.Center) { Icon(Icons.People, null, tint = colors.text, modifier = Modifier.size(18.dp)) }
                    else Avatar(initialsOf(s.name), AvatarTone.tone(s.id), 32.dp)
                    Column(Modifier.weight(1f)) {
                        Text(if (s.isEveryone) "@everyone" else s.name, color = colors.text, fontSize = 17.sp, maxLines = 1)
                        val second = if (s.isEveryone) s.detail else s.username?.let { "@$it" }
                        if (second != null) Text(second, color = colors.textSecondary, fontSize = 14.sp, maxLines = 1)
                    }
                }
            }
        }
    }
}

@Composable
private fun Icon(icon: androidx.compose.ui.graphics.vector.ImageVector, description: String?, tint: Color, modifier: Modifier = Modifier) =
    androidx.compose.material3.Icon(icon, description, modifier = modifier, tint = tint)
