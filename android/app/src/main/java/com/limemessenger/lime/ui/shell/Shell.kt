package com.limemessenger.lime.ui.shell

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.ui.theme.Lime

enum class Tab(val label: Int, val icon: ImageVector) {
    Link(R.string.tab_link, TabIcons.Link),
    Call(R.string.tab_call, TabIcons.Call),
    Jam(R.string.tab_jam, TabIcons.Jam),
}

/** The signed-in shell: link · call · jam as a bottom bar (as iOS). Call and jam say "Coming soon on Android" until built. */
@Composable
fun Shell(link: @Composable () -> Unit, modifier: Modifier = Modifier) {
    var tab by rememberSaveable { mutableStateOf(Tab.Link) }
    val colors = Lime.colors
    Scaffold(
        modifier = modifier,
        containerColor = colors.canvas,
        bottomBar = {
            NavigationBar(containerColor = colors.surface) {
                Tab.entries.forEach { entry ->
                    NavigationBarItem(
                        selected = tab == entry,
                        onClick = { tab = entry },
                        icon = { Icon(entry.icon, contentDescription = null) },
                        label = { Text(stringResource(entry.label), fontSize = 12.sp) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = colors.text, selectedTextColor = colors.text,
                            unselectedIconColor = colors.textSecondary, unselectedTextColor = colors.textSecondary,
                            indicatorColor = colors.pressed,
                        ),
                    )
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                Tab.Link -> link()
                Tab.Call, Tab.Jam -> ComingSoon()
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
