package com.limemessenger.lime.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.statusBars
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
    // The call driver needs the chats (names) and the chats need to hand it the call ops that arrive: they meet here.
    val callHooks = remember(session) { CallHooks() }
    val chats = remember(session) {
        ChatsModel(
            store = { session.store }, transport = { session.transport }, token = { session.accessToken() },
            staleToken = { session.lastAccessToken() }, registrar = { session.registerDevice(); Unit }, isRegistered = { session.deviceRegistered },
            me = { session.profile?.displayName.orEmpty() to com.limemessenger.lime.chats.AvatarTone.tone(session.userId.orEmpty()) },
            mutes = com.limemessenger.lime.chats.MuteSettings(appContext.getSharedPreferences("lime.mutes", android.content.Context.MODE_PRIVATE)),
            afterSync = { callHooks.afterSync() },
        )
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(chats) { lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { chats.runWhileForeground() } }
    val callsModel = remember(session) { com.limemessenger.lime.calls.CallsModel { session.store } }
    val callScope = rememberCoroutineScope()
    var cameraDenied by remember { mutableStateOf(false) }
    val callView = androidx.compose.ui.platform.LocalView.current
    val callSession = remember(session) {
        com.limemessenger.lime.calls.CallSession(
            context = appContext, store = { session.store }, transport = { session.transport }, token = { session.accessToken() }, myId = { session.userId }, scope = callScope,
            // The chat may have arrived in this very sync (the list model has not read it yet): ask the core's list when the model does not know the person.
            nameOf = { id ->
                val dm = { c: uniffi.lime_core.ConversationSummary -> !c.isGroup && c.members.firstOrNull()?.id == id }
                chats.conversations.firstOrNull(dm)?.title ?: session.store?.let { core -> runCatching { core.listConversations() }.getOrNull()?.firstOrNull(dm)?.title } ?: id
            },
            onLogged = { callScope.launch { callsModel.reload(); chats.reload() } },
            announce = { words -> callView.announceForAccessibility(words) },
            lowData = { (appContext as? com.limemessenger.lime.LimeApp)?.callPrefs?.lowDataMode ?: false },
            foreground = { (appContext as? com.limemessenger.lime.LimeApp)?.inForeground ?: true },
            cameraAllowed = { androidx.core.content.ContextCompat.checkSelfPermission(appContext, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED },
        )
    }
    // The camera is held while lime is in the background (Android closes it for an app that is not in front) and comes back with it.
    androidx.compose.runtime.DisposableEffect(callSession, lifecycle) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) { (appContext as? com.limemessenger.lime.LimeApp)?.inForeground = false; callSession.setBackgrounded(true); callSession.appForeground(false) }
            else if (event == Lifecycle.Event.ON_START) { (appContext as? com.limemessenger.lime.LimeApp)?.inForeground = true; callSession.setBackgrounded(false); callSession.appForeground(true) }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    androidx.compose.runtime.DisposableEffect(callSession) {
        (appContext as? com.limemessenger.lime.LimeApp)?.callHangUp = { callSession.hangUp() }
        (appContext as? com.limemessenger.lime.LimeApp)?.callSession = callSession
        onDispose { (appContext as? com.limemessenger.lime.LimeApp)?.callHangUp = null; (appContext as? com.limemessenger.lime.LimeApp)?.callSession = null }
    }
    callHooks.afterSync = { callSession.handleArrivals(); callsModel.reload() }
    // The microphone is asked for when a call is placed or answered, never before (the same rule as a voice message).
    var afterMic by remember { mutableStateOf<(() -> Unit)?>(null) }
    var micDenied by remember { mutableStateOf(false) }
    val micLauncher = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { granted ->
        val next = afterMic; afterMic = null
        if (granted) next?.invoke() else { micDenied = true; callSession.decline() }
    }
    val withMic: (() -> Unit) -> Unit = { action ->
        if (androidx.core.content.ContextCompat.checkSelfPermission(appContext, android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED) action()
        else { afterMic = action; micLauncher.launch(android.Manifest.permission.RECORD_AUDIO) }
    }
    // The camera is asked for when a video call is placed or the camera is turned on mid-call, never before.
    var afterCamera by remember { mutableStateOf<((Boolean) -> Unit)?>(null) }
    val cameraLauncher = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { granted ->
        val next = afterCamera; afterCamera = null
        next?.invoke(granted)
    }
    val withCamera: ((Boolean) -> Unit) -> Unit = { action ->
        if (androidx.core.content.ContextCompat.checkSelfPermission(appContext, android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) action(true)
        else { afterCamera = action; cameraLauncher.launch(android.Manifest.permission.CAMERA) }
    }
    // Bluetooth headsets (Android 12+): the permission is asked for from the audio-output list, never before.
    val bluetoothLauncher = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { callSession.audioRoutesChanged() }
    val allowBluetooth: (() -> Unit)? = if (android.os.Build.VERSION.SDK_INT >= 31) ({ bluetoothLauncher.launch(android.Manifest.permission.BLUETOOTH_CONNECT) }) else null
    // A voice call starts now; a video call asks for the camera as well (without it the call is not placed: the person can still call by voice).
    val placeCall: (String, String, Boolean) -> Unit = { id, name, video ->
        if (video) withMic { withCamera { ok -> if (ok) callSession.call(id, name, video = true) else cameraDenied = true } } else withMic { callSession.call(id, name) }
    }
    // Answering a video call asks for the camera too; without it the call is answered with the camera off.
    val answerCall: () -> Unit = { withMic { if (callSession.video) withCamera { callSession.answer() } else callSession.answer() } }
    // "Video" in a voice call, or "Camera" when the camera is not on yet: asks, then adds the camera.
    val startVideo: () -> Unit = { withCamera { ok -> if (ok) callSession.toggleCamera() else cameraDenied = true } }
    var callSearchOpen by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(callsModel, chats.revision) { callsModel.reload() }
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
    var bandPage by remember { mutableStateOf<String?>(null) }
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
    BackHandler(enabled = bandPage != null && jamPost == null) { bandPage = null }
    BackHandler(enabled = yourJam && bandPage == null && compose == null && jamPost == null) { yourJam = false }
    BackHandler(enabled = personProfile != null) { personProfile = null }
    BackHandler(enabled = threadRoot != null) { threadRoot = null }
    BackHandler(enabled = openId == null && searchOpen) { searchOpen = false }
    BackHandler(enabled = openId == null && callSearchOpen) { callSearchOpen = false }
    BackHandler(enabled = groupInfoOpen) { groupInfoOpen = false }
    BackHandler(enabled = groupStep != null) { groupStep = null }
    BackHandler(enabled = groupStep == null && groupPicking) { groupPicking = false }
    BackHandler(enabled = threadRoot == null && !groupInfoOpen && openId != null) { openId = null; focusMessage = null }
    BackHandler(enabled = openId == null && requestsOpen) { requestsOpen = false }
    BackHandler(enabled = openId == null && newMessageOpen) { newMessageOpen = false }
    // Back from the call screen puts the call away (the mini-bar returns to it); a video call floats (Picture in Picture) when it can.
    val activity = remember(appContext) { generateSequence(callView.context) { (it as? android.content.ContextWrapper)?.baseContext }.filterIsInstance<com.limemessenger.lime.MainActivity>().firstOrNull() }
    val keyguard = appContext.getSystemService(android.content.Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
    val minimize: () -> Unit = {
        // Over the lock screen the call is the only thing that shows: it cannot be put away to the chats.
        if (!keyguard.isKeyguardLocked) { if (callSession.video && activity?.enterCallPip() == true) { callSession.minimize() } else callSession.minimize() }
    }
    BackHandler(enabled = callSession.inCall && !callSession.minimized) { minimize() }
    // The call shows over a locked phone only while it is going; an Answer tap on the notification answers it once the microphone is allowed.
    LaunchedEffect(callSession.inCall) { if (!callSession.inCall) { activity?.setShowWhenLocked(false); activity?.setTurnScreenOn(false) } }
    val appHandle = appContext as? com.limemessenger.lime.LimeApp
    LaunchedEffect(appHandle?.answerRequest, callSession.phase) {
        val wanted = appHandle?.answerRequest ?: return@LaunchedEffect
        if (callSession.phase == uniffi.lime_core.CallPhaseKind.INCOMING && callSession.driver.state.callId == wanted) { appHandle.answerRequest = null; answerCall() }
        else if (callSession.phase != uniffi.lime_core.CallPhaseKind.INCOMING) appHandle.answerRequest = null
    }
    val root = threadRoot
    val postOpen = jamPost
    val person = personProfile
    val writing = compose
    val miniBar = callSession.inCall && callSession.minimized
    Column(Modifier.fillMaxSize()) {
    if (miniBar) com.limemessenger.lime.ui.calls.CallMiniBar(callSession, chats)
    Box(Modifier.weight(1f).then(if (miniBar) Modifier.consumeWindowInsets(androidx.compose.foundation.layout.WindowInsets.Companion.statusBars) else Modifier)) {
    if (callSession.inCall && !callSession.minimized) {
        if (appHandle?.inPip == true && callSession.video) {
            val st = callSession.driver.state
            val mem = chats.conversations.firstOrNull { !it.isGroup && it.members.firstOrNull()?.id == st.peerId }?.members?.firstOrNull()
            val nm = st.peerName.ifEmpty { mem?.name.orEmpty() }
            com.limemessenger.lime.ui.calls.CallPipView(callSession, nm, mem?.initials?.ifEmpty { null } ?: nm.take(1), mem?.tone?.toInt() ?: com.limemessenger.lime.chats.AvatarTone.tone(st.peerId))
        } else com.limemessenger.lime.ui.calls.CallScreen(callSession, chats, onAnswer = answerCall, onStartVideo = startVideo, onAllowBluetooth = allowBluetooth, onMinimize = minimize)
    } else if (writing != null) {
        com.limemessenger.lime.ui.jam.JamComposeScreen(jam, jamDrafts, writing, onDone = { compose = null })
    } else if (profileOpen) {
        SettingsScreen(session, onClose = { profileOpen = false }, chats = chats)
    } else if (person != null) {
        PersonProfileScreen(person.first, person.second, chats, onBack = { personProfile = null }, jam = jam, onBlocked = { personProfile = null; openId = null })
    } else if (postOpen != null) {
        JamReaderScreen(postOpen, jam, myId = session.userId, chats = chats, onViewBand = { jamPost = null; bandPage = it }, onEdit = { compose = com.limemessenger.lime.ui.jam.ComposeRoute(if (it.kind == "article") "article" else "quick", editing = it); jamPost = null }, onBack = { jamPost = null })
    } else if (bandPage != null && jam.jams.any { it.jamId == bandPage }) {
        com.limemessenger.lime.ui.band.BandScreen(jam.jams.first { it.jamId == bandPage }, jam, onBack = { bandPage = null }, onOpenPost = { jamPost = it }, onOpenChat = { id -> bandPage = null; yourJam = false; openId = id })
    } else if (yourJam) {
        com.limemessenger.lime.ui.jam.YourJamScreen(jam, jamDrafts, onBack = { yourJam = false }, onCompose = { compose = it }, onOpenBand = { bandPage = it })
    } else if (chatModel != null && groupModel != null && groupInfoOpen) {
        GroupDetailsScreen(chats, groupModel, chats.myName, chats.myTone, onBack = { groupInfoOpen = false }, onLeft = { groupInfoOpen = false; openId = null })
    } else if (chatModel != null && root != null) {
        ThreadScreen(root, chatModel, onBack = { threadRoot = null })
    } else if (chatModel != null) {
        ChatScreen(chatModel, chats, onBack = { openId = null; focusMessage = null }, focusMessageId = focusMessage, onOpenThread = { threadRoot = it }, onOpenProfile = { id, name -> personProfile = id to name }, onOpenGroup = { groupInfoOpen = true }, onCallBack = placeCall)
    } else if (callSearchOpen) {
        com.limemessenger.lime.ui.calls.CallSearchScreen(callsModel, chats, onBack = { callSearchOpen = false }, onPlaceCall = placeCall)
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
        Shell(selected = shellTab, onSelect = { shellTab = it }, linkUnread = chats.unreadChatCount, callsMissed = if (shellTab == com.limemessenger.lime.ui.shell.Tab.Call) 0 else callsModel.missedUnseen,
            calls = {
                com.limemessenger.lime.ui.calls.CallsScreen(
                    callsModel, chats, myName = session.profile?.displayName.orEmpty(), myTone = com.limemessenger.lime.chats.AvatarTone.tone(session.userId.orEmpty()),
                    onProfile = { profileOpen = true }, onSearch = { callSearchOpen = true }, onPlaceCall = placeCall,
                )
            }, jam = { JamFeedScreen(jam, onYours = { yourJam = true }, onOpen = { jamPost = it }) }, link = {
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
    }
    }
    ArrivalBannerView(arrivals) { id -> openId = id; arrivals.dismiss() }
    if (micDenied) androidx.compose.material3.AlertDialog(
        onDismissRequest = { micDenied = false }, modifier = Modifier.testTag("call-mic-denied"),
        title = { Text(stringResource(R.string.calls_mic_title)) }, text = { Text(stringResource(R.string.calls_mic_body)) },
        confirmButton = { androidx.compose.material3.TextButton(onClick = { micDenied = false }, modifier = Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.calls_not_ready_ok)) } },
    )
    if (cameraDenied) androidx.compose.material3.AlertDialog(
        onDismissRequest = { cameraDenied = false }, modifier = Modifier.testTag("call-camera-denied"),
        title = { Text(stringResource(R.string.calls_camera_title)) }, text = { Text(stringResource(R.string.calls_camera_body)) },
        confirmButton = { androidx.compose.material3.TextButton(onClick = { cameraDenied = false }, modifier = Modifier.heightIn(min = 48.dp).testTag("call-camera-denied-ok")) { Text(stringResource(R.string.calls_not_ready_ok)) } },
    )
}

/** The place where the chats and the call driver are joined (each is built after the other needs it). */
private class CallHooks { var afterSync: suspend () -> Unit = {}; suspend fun afterSync() = afterSync.invoke() }

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
