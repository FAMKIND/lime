package com.limemessenger.lime.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.ui.chats.ChatListScreen
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.AccountSession.Phase
import com.limemessenger.lime.auth.OnboardingModel
import com.limemessenger.lime.auth.TermsAcceptance
import com.limemessenger.lime.ui.onboarding.OnboardingFlow
import com.limemessenger.lime.ui.shell.Shell
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.launch

/** What is on screen follows the session's phase (iOS's `RootView`): a splash while launching, onboarding while signed out, the tabs once in. */
@Composable
fun Root(session: AccountSession) {
    val context = androidx.compose.ui.platform.LocalContext.current
    LaunchedEffect(session) { if (session.phase == Phase.Launching) session.resume() }
    when (session.phase) {
        Phase.Launching -> Splash()
        Phase.SignedOut -> SignedOut(session) { TermsAcceptance.record(context) }
        Phase.SignedIn -> SignedIn(session)
    }
}

@Composable
fun Splash() {
    Box(Modifier.fillMaxSize().background(Lime.colors.canvas), contentAlignment = Alignment.Center) {
        Text(stringResource(R.string.app_name), color = Lime.colors.text, fontSize = 56.sp, fontWeight = FontWeight.Bold, modifier = Modifier.testTag("splash"))
    }
}

/** The onboarding flow for a phone with no account on it yet. The model starts fresh each time the session signs out. */
@Composable
private fun SignedOut(session: AccountSession, onTermsAgreed: () -> Unit) {
    val auth = session.auth
    if (auth == null) {
        Box(Modifier.fillMaxSize().background(Lime.colors.canvas), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.no_backend), color = Lime.colors.textSecondary, fontSize = 16.sp, modifier = Modifier.testTag("no-backend"))
        }
        return
    }
    val model = remember(session.onboardingGeneration) {
        OnboardingModel(auth, onTermsAgreed = onTermsAgreed, onComplete = { tokens, profile, _ -> session.completeSignIn(tokens, profile) })
    }
    OnboardingFlow(model, onTestAccount = { tokens, profile -> session.completeSignIn(tokens, profile) })
}

/** Signed in: the tabs, with the Messages list on the link tab, kept fresh while the app is in front. A chat opens over the tabs (LIME-298 draws it). */
@Composable
private fun SignedIn(session: AccountSession) {
    val chats = remember(session) {
        ChatsModel(
            store = { session.store }, transport = { session.transport }, token = { session.accessToken() },
            staleToken = { session.lastAccessToken() }, registrar = { session.registerDevice(); Unit }, isRegistered = { session.deviceRegistered },
        )
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(chats) { lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { chats.runWhileForeground() } }
    var openId by rememberSaveable { mutableStateOf<String?>(null) }
    var profileOpen by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val opened = openId?.let { id -> chats.conversations.firstOrNull { it.id == id } }
    BackHandler(enabled = openId != null) { openId = null }
    if (opened != null) {
        ChatPlaceholder(opened.title)
    } else {
        Shell(link = {
            ChatListScreen(
                chats, myName = session.profile?.displayName.orEmpty(),
                onOpen = { openId = it.id; scope.launch { chats.markRead(it.id) } },
                onProfile = { profileOpen = true },
            )
        })
    }
    if (profileOpen) ProfileDialog(session, onDismiss = { profileOpen = false })
}

/** Stands in for the chat screen until LIME-298. */
@Composable
private fun ChatPlaceholder(title: String) {
    Box(Modifier.fillMaxSize().background(Lime.colors.canvas).systemBarsPadding(), contentAlignment = Alignment.Center) {
        Text(title, color = Lime.colors.text, fontSize = 24.sp, fontWeight = FontWeight.Bold, modifier = Modifier.testTag("chat-placeholder"))
    }
}

/** Who is signed in, and a plain sign out (Settings has it in LIME-300; until then it lives here). */
@Composable
private fun ProfileDialog(session: AccountSession, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    val colors = Lime.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.canvas,
        title = { Text(session.profile?.displayName.orEmpty(), color = colors.text, modifier = Modifier.testTag("signed-in-as")) },
        text = {
            if (!session.deviceRegistered) {
                Text(session.problem?.message ?: stringResource(R.string.registering_device), color = colors.textSecondary, modifier = Modifier.testTag("device-status"))
            }
        },
        confirmButton = {
            TextButton({ onDismiss(); scope.launch { session.signOut() } }, Modifier.heightIn(min = 48.dp).testTag("sign-out")) {
                Text(stringResource(R.string.sign_out), color = colors.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            }
        },
        dismissButton = {
            TextButton(onDismiss, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.action_back), color = colors.text, fontSize = 16.sp) }
        },
    )
}
