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
import com.limemessenger.lime.ui.chats.NewMessageScreen
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.ui.jam.JamFeedScreen
import com.limemessenger.lime.ui.jam.JamReaderScreen
import com.limemessenger.lime.ui.profile.PersonProfileScreen
import com.limemessenger.lime.ui.settings.SettingsScreen
import com.limemessenger.lime.ui.chats.RequestsScreen
import com.limemessenger.lime.ui.chat.ChatScreen
import com.limemessenger.lime.ui.chat.ThreadScreen
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.GroupModel
import com.limemessenger.lime.ui.chats.GroupDetailsScreen
import com.limemessenger.lime.ui.chats.GroupNameScreen
import com.limemessenger.lime.ui.chats.SearchScreen
import com.limemessenger.lime.ui.chats.GroupPickerScreen
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
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
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun SignedIn(session: AccountSession) {
    val appContext = androidx.compose.ui.platform.LocalContext.current.applicationContext
    val chats = remember(session) {
        ChatsModel(
            store = { session.store }, transport = { session.transport }, token = { session.accessToken() },
            staleToken = { session.lastAccessToken() }, registrar = { session.registerDevice(); Unit }, isRegistered = { session.deviceRegistered },
            me = { session.profile?.displayName.orEmpty() to com.limemessenger.lime.chats.AvatarTone.tone(session.userId.orEmpty()) },
            mutes = com.limemessenger.lime.chats.MuteSettings(appContext.getSharedPreferences("lime.mutes", android.content.Context.MODE_PRIVATE)),
        )
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(chats) { lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { chats.runWhileForeground() } }
    var openId by rememberSaveable { mutableStateOf<String?>(null) }
    var requestsOpen by rememberSaveable { mutableStateOf(false) }
    var newMessageOpen by rememberSaveable { mutableStateOf(false) }
    // New group: null, the picker ("pick"), or the name step with the people chosen. A group's details open over its chat.
    var searchOpen by rememberSaveable { mutableStateOf(false) }
    var focusMessage by remember { mutableStateOf<String?>(null) }
    var groupStep by remember { mutableStateOf<List<String>?>(null) }
    var groupPicking by rememberSaveable { mutableStateOf(false) }
    var groupInfoOpen by rememberSaveable { mutableStateOf(false) }
    var threadRoot by remember { mutableStateOf<uniffi.lime_core.MessageItem?>(null) }
    var profileOpen by rememberSaveable { mutableStateOf(false) }
    var personProfile by remember { mutableStateOf<Pair<String, String>?>(null) }
    var jamPost by remember { mutableStateOf<uniffi.lime_core.JamPostInfo?>(null) }
    var yourJam by remember { mutableStateOf(false) }
    var shellTab by rememberSaveable { mutableStateOf(com.limemessenger.lime.ui.shell.Tab.Link) }
    var compose by remember { mutableStateOf<com.limemessenger.lime.ui.jam.ComposeRoute?>(null) }
    // Unpublished posts stay on this phone, in this account's own folder.
    val jamDrafts = remember(session.userId) { com.limemessenger.lime.jam.JamDrafts(java.io.File(appContext.filesDir, "lime-jam-drafts/${session.userId.orEmpty().ifEmpty { "me" }}")) }
    val jam = remember(session) {
        JamModel(
            store = { session.store }, nameOf = { id -> if (id == session.userId) session.profile?.displayName else chats.conversations.firstNotNullOfOrNull { c -> c.members.firstOrNull { it.id == id }?.name } },
            env = com.limemessenger.lime.jam.JamEnv(transport = { session.transport }, token = { session.accessToken() }, deliver = { chats.deliverNow() }),
            savedStore = com.limemessenger.lime.jam.SavedPosts.Prefs(appContext.getSharedPreferences("lime.jam", android.content.Context.MODE_PRIVATE)),
        )
    }
    // A sync brought something: the jam posts and their counts are read again.
    LaunchedEffect(chats.revision) { jam.reload() }
    val app = appContext as? com.limemessenger.lime.LimeApp
    val mediaPolicy = remember(app) { app?.let { com.limemessenger.lime.chats.MediaPolicy(it, it.mediaPrefs) } }
    val chatModel = remember(openId) { openId?.let { ChatModel(it, chats, mayAutoDownload = { a -> mediaPolicy?.mayAutoDownload(a) ?: true }) } }
    // The banner for a new message in another chat while lime is open (no push service yet).
    val arrivals = remember(chats) {
        com.limemessenger.lime.chats.ArrivalBanner(
            enabled = { app?.notificationPrefs?.enabled ?: true }, preview = { app?.notificationPrefs?.preview ?: uniffi.lime_core.NotificationPreview.NAME_AND_MESSAGE },
            muted = { chats.isMuted(it) }, hideText = { app?.appLock?.hidesNotificationText() ?: false },
        )
    }
    LaunchedEffect(chats.revision) { arrivals.check(chats.conversations, openId) }
    val groupModel = remember(openId) { openId?.let { GroupModel(chats, it) } }
    BackHandler(enabled = jamPost != null && compose == null) { jamPost = null }
    BackHandler(enabled = yourJam && compose == null && jamPost == null) { yourJam = false }
    BackHandler(enabled = personProfile != null) { personProfile = null }
    BackHandler(enabled = threadRoot != null) { threadRoot = null }
    BackHandler(enabled = openId == null && searchOpen) { searchOpen = false }
    BackHandler(enabled = groupInfoOpen) { groupInfoOpen = false }
    BackHandler(enabled = groupStep != null) { groupStep = null }
    BackHandler(enabled = groupStep == null && groupPicking) { groupPicking = false }
    BackHandler(enabled = threadRoot == null && !groupInfoOpen && openId != null) { openId = null; focusMessage = null }
    BackHandler(enabled = openId == null && requestsOpen) { requestsOpen = false }
    BackHandler(enabled = openId == null && newMessageOpen) { newMessageOpen = false }
    val root = threadRoot
    val postOpen = jamPost
    val person = personProfile
    val writing = compose
    if (writing != null) {
        com.limemessenger.lime.ui.jam.JamComposeScreen(jam, jamDrafts, writing, onDone = { compose = null })
    } else if (profileOpen) {
        SettingsScreen(session, onClose = { profileOpen = false }, chats = chats)
    } else if (person != null) {
        PersonProfileScreen(person.first, person.second, chats, onBack = { personProfile = null }, jam = jam, onBlocked = { personProfile = null; openId = null })
    } else if (postOpen != null) {
        JamReaderScreen(postOpen, jam, myId = session.userId, onEdit = { compose = com.limemessenger.lime.ui.jam.ComposeRoute(if (it.kind == "article") "article" else "quick", editing = it); jamPost = null }, onBack = { jamPost = null })
    } else if (yourJam) {
        com.limemessenger.lime.ui.jam.YourJamScreen(jam, jamDrafts, onBack = { yourJam = false }, onCompose = { compose = it })
    } else if (chatModel != null && groupModel != null && groupInfoOpen) {
        GroupDetailsScreen(chats, groupModel, chats.myName, chats.myTone, onBack = { groupInfoOpen = false }, onLeft = { groupInfoOpen = false; openId = null })
    } else if (chatModel != null && root != null) {
        ThreadScreen(root, chatModel, onBack = { threadRoot = null })
    } else if (chatModel != null) {
        ChatScreen(chatModel, chats, onBack = { openId = null; focusMessage = null }, focusMessageId = focusMessage, onOpenThread = { threadRoot = it }, onOpenProfile = { id, name -> personProfile = id to name }, onOpenGroup = { groupInfoOpen = true })
    } else if (searchOpen) {
        SearchScreen(chats, onBack = { searchOpen = false }, onOpenChat = { searchOpen = false; openId = it }, onOpenMessage = { chat, message -> searchOpen = false; focusMessage = message; openId = chat })
    } else if (groupStep != null) {
        GroupNameScreen(chats, groupStep!!, onBack = { groupStep = null }, onCreated = { groupStep = null; groupPicking = false; newMessageOpen = false; openId = it })
    } else if (groupPicking) {
        GroupPickerScreen(chats, existing = emptyList(), adding = false, onBack = { groupPicking = false }, onNext = { groupStep = it })
    } else if (newMessageOpen) {
        NewMessageScreen(chats, onClose = { newMessageOpen = false }, onOpenChat = { newMessageOpen = false; openId = it }, onNewGroup = { groupPicking = true })
    } else if (requestsOpen) {
        RequestsScreen(chats, onOpen = { openId = it.id }, onBack = { requestsOpen = false })
    } else {
        Shell(selected = shellTab, onSelect = { shellTab = it }, jam = { JamFeedScreen(jam, onYours = { yourJam = true }, onOpen = { jamPost = it }) }, link = {
            ChatListScreen(
                chats, myName = session.profile?.displayName.orEmpty(), myTone = com.limemessenger.lime.chats.AvatarTone.tone(session.userId.orEmpty()),
                onOpen = { openId = it.id },
                onProfile = { profileOpen = true },
                onRequests = { requestsOpen = true },
                onNewMessage = { newMessageOpen = true },
                onSearch = { searchOpen = true },
            )
        })
    }
    ArrivalBannerView(arrivals) { id -> openId = id; arrivals.dismiss() }
}

/** The banner for a new message: the title and body from the core's words, shown for a few seconds; tapping it opens the chat. TalkBack reads it when it appears. */
@Composable
private fun ArrivalBannerView(arrivals: com.limemessenger.lime.chats.ArrivalBanner, onOpen: (String) -> Unit) {
    val banner = arrivals.banner ?: return
    LaunchedEffect(banner) { kotlinx.coroutines.delay(4_000); arrivals.dismiss() }
    val colors = Lime.colors
    Box(Modifier.fillMaxSize().systemBarsPadding().padding(12.dp), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.fillMaxWidth().background(colors.surface, androidx.compose.foundation.shape.RoundedCornerShape(18.dp)).heightIn(min = 56.dp)
                .semantics(mergeDescendants = true) { liveRegion = androidx.compose.ui.semantics.LiveRegionMode.Polite; role = androidx.compose.ui.semantics.Role.Button }
                .clickable { onOpen(banner.conversationId) }.padding(horizontal = 16.dp, vertical = 10.dp).testTag("arrival-banner"),
        ) {
            Text(banner.title, color = colors.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Text(banner.body, color = colors.textSecondary, fontSize = 15.sp, maxLines = 2, modifier = Modifier.testTag("arrival-banner-body"))
        }
    }
}
