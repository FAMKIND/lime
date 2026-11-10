package com.limemessenger.lime.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.security.AppLock
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.launch

/**
 * Above everything: a plain cover while lime is not in front, the lock screen while it is locked (iOS `LockCoverView` / `LockScreen`). Nothing of the chats
 * shows through. Nobody signed in: there is nothing to cover.
 */
@Composable
fun LockOverlay(lock: AppLock, signedIn: Boolean) {
    LaunchedEffect(signedIn) { if (!signedIn) lock.turnOffForSignedOut() }
    if (!signedIn || !(lock.isCovered || lock.isLocked)) return
    val colors = Lime.colors
    val scope = rememberCoroutineScope()
    // Coming back locked asks by itself; "Unlock" asks again.
    LaunchedEffect(lock.isLocked) { if (lock.isLocked) lock.unlock() }
    Box(Modifier.fillMaxSize().background(colors.canvas).clickable(enabled = false) {}, contentAlignment = Alignment.Center) {
        if (lock.isLocked) {
            Column(Modifier.padding(24.dp).testTag("lock-screen"), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Text(stringResource(R.string.lock_title), color = colors.text, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                val unlock = stringResource(R.string.lock_unlock_description)
                Box(
                    Modifier.heightIn(min = 52.dp).background(colors.accent, RoundedCornerShape(26.dp)).semantics { contentDescription = unlock; role = Role.Button }
                        .clickable { scope.launch { lock.unlock() } }.padding(horizontal = 32.dp).testTag("lock-unlock"),
                    contentAlignment = Alignment.Center,
                ) { Text(stringResource(R.string.lock_unlock), color = colors.accentInk, fontSize = 17.sp, fontWeight = FontWeight.SemiBold) }
            }
        }
    }
}
