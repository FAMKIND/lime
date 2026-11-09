package com.limemessenger.lime.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.chats.AvatarTone
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.profileOf
import com.limemessenger.lime.ui.common.Avatar
import com.limemessenger.lime.ui.common.initialsOf
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import uniffi.lime_core.PublicProfile

/** Someone else's profile, opened from a chat (iOS `ProfileView`, minimal): their name, username, school and About line, read only. */
@Composable
fun PersonProfileScreen(userId: String, fallbackName: String, chats: ChatsModel, onBack: () -> Unit, load: suspend (String) -> PublicProfile? = { chats.profileOf(it) }) {
    val colors = Lime.colors
    var profile by remember { mutableStateOf<PublicProfile?>(null) }
    var done by remember { mutableStateOf(false) }
    LaunchedEffect(userId) { profile = runCatching { load(userId) }.getOrNull(); done = true }
    val name = profile?.displayName?.ifEmpty { null } ?: fallbackName
    Column(Modifier.fillMaxSize().background(colors.canvas).systemBarsPadding().testTag("person-profile")) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack, Modifier.size(56.dp).testTag("profile-back")) { Icon(Icons.Back, stringResource(R.string.chat_back), tint = colors.text) }
            Text(stringResource(R.string.profile_title_other), color = colors.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
        }
        Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Avatar(initialsOf(name), AvatarTone.tone(userId), 96.dp)
            Text(name, color = colors.text, fontSize = 24.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.testTag("profile-name"))
            profile?.username?.let { Text("@$it", color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.testTag("profile-username")) }
            profile?.school?.let { Text(it, color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.testTag("profile-school")) }
            val about = listOfNotNull(profile?.aboutEmoji, profile?.aboutText).filter { it.isNotEmpty() }.joinToString(" ")
            if (about.isNotEmpty()) Text(about, color = colors.text, fontSize = 17.sp, textAlign = TextAlign.Center, modifier = Modifier.testTag("profile-about"))
            if (done && profile == null) Text(stringResource(R.string.profile_not_found), color = colors.textSecondary, fontSize = 16.sp, modifier = Modifier.testTag("profile-none"))
            if (!done) Text(stringResource(R.string.profile_loading), color = colors.textSecondary, fontSize = 15.sp)
        }
    }
}
