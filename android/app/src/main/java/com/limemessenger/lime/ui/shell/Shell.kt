package com.limemessenger.lime.ui.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeType
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription

enum class Tab(val label: Int, val icon: ImageVector) {
    Link(R.string.tab_link, TabIcons.Link),
    Call(R.string.tab_call, TabIcons.Call),
    Jam(R.string.tab_jam, TabIcons.Jam),
}

/** The signed-in shell: link · call · jam as a bottom bar (as iOS). Call and jam say "Coming soon on Android" until built. */
@Composable
fun Shell(link: @Composable () -> Unit, modifier: Modifier = Modifier, jam: (@Composable () -> Unit)? = null, selected: Tab? = null, onSelect: ((Tab) -> Unit)? = null, linkUnread: Int = 0) {
    // The caller can keep the tab (Root does: a post, a chat or a profile replaces the whole shell, and coming back must land on the same tab).
    var own by rememberSaveable { mutableStateOf(Tab.Link) }
    val tab = selected ?: own
    val choose: (Tab) -> Unit = { own = it; onSelect?.invoke(it) }
    val colors = Lime.colors
    Scaffold(
        modifier = modifier,
        containerColor = colors.canvas,
        bottomBar = {
            Column {
                // lime's bar: the canvas colour with a hairline on top (the accent is only for the unread badge, the one live thing here); still a real NavigationBar for TalkBack.
                Box(Modifier.fillMaxWidth().height(0.5.dp).background(colors.hairline))
                NavigationBar(containerColor = colors.canvas) {
                    Tab.entries.forEach { entry ->
                        val unreadWords = if (entry == Tab.Link && linkUnread > 0) androidx.compose.ui.res.pluralStringResource(R.plurals.chat_back_unread, linkUnread, linkUnread) else null
                        NavigationBarItem(
                            modifier = Modifier.testTag("tab-${entry.name.lowercase()}").then(if (unreadWords != null) Modifier.semantics { stateDescription = unreadWords } else Modifier),
                            selected = tab == entry,
                            onClick = { choose(entry) },
                            icon = {
                                if (entry == Tab.Link && linkUnread > 0) BadgedBox(badge = {
                                    Badge(containerColor = colors.accent, contentColor = colors.accentInk, modifier = Modifier.testTag("tab-link-badge")) { Text(com.limemessenger.lime.chats.badgeText(linkUnread)) }
                                }) { Icon(entry.icon, contentDescription = null) }
                                else Icon(entry.icon, contentDescription = null)
                            },
                            label = { Text(stringResource(entry.label), fontSize = LimeType.caption.size) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = colors.text, selectedTextColor = colors.text,
                                unselectedIconColor = colors.textSecondary, unselectedTextColor = colors.textSecondary,
                                indicatorColor = colors.pressed,
                            ),
                        )
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                Tab.Link -> link()
                Tab.Jam -> if (jam != null) jam() else ComingSoon()
                Tab.Call -> ComingSoon()
            }
        }
    }
}

@Composable
fun ComingSoon() {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(stringResource(R.string.coming_soon_android), color = Lime.colors.textSecondary, fontSize = 16.sp)
    }
}
