@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.FakeAuthService
import com.limemessenger.lime.auth.AuthTokens
import com.limemessenger.lime.auth.Profile
import com.limemessenger.lime.chats.ChatModel
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.isOwn
import com.limemessenger.lime.chats.FakeBand
import com.limemessenger.lime.chats.Samples
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.Root
import com.limemessenger.lime.ui.band.BandScreen
import com.limemessenger.lime.ui.chat.ChatScreen
import com.limemessenger.lime.ui.chats.ChatListScreen
import com.limemessenger.lime.ui.chats.NewMessageScreen
import com.limemessenger.lime.ui.jam.JamFeedScreen
import com.limemessenger.lime.ui.jam.JamReaderScreen
import com.limemessenger.lime.ui.profile.PersonProfileScreen
import com.limemessenger.lime.ui.settings.AboutScreen
import com.limemessenger.lime.ui.settings.AppearanceScreen
import com.limemessenger.lime.ui.settings.NotificationsScreen
import com.limemessenger.lime.ui.settings.PrivacyScreen
import com.limemessenger.lime.ui.settings.SettingsScreen
import com.limemessenger.lime.ui.settings.StorageScreen
import com.limemessenger.lime.ui.shell.Shell
import com.limemessenger.lime.ui.shell.Tab
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * NOT a test: the Android half of the LIME-421 audit (real screens, sample data) into files/shots, light and dark (`tools/shots-audit.sh`).
 * `@Staging` only so the plain pass skips it.
 */
@Staging
@RunWith(AndroidJUnit4::class)
class AuditShotsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val auth = FakeAuthService()
    private lateinit var dir: File
    private lateinit var session: AccountSession
    private lateinit var chats: ChatsModel
    private lateinit var store: uniffi.lime_core.LimeStore
    private val alias = "lime.test.audit"
    private val app get() = context.applicationContext as LimeApp

    @Before fun setUp() {
        dir = File(context.cacheDir, "audit-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        session = AccountSession(auth, backend = null, storage = storage, secrets = secrets)
        runBlocking { session.completeSignIn(AuthTokens("a", "r", System.currentTimeMillis() + 3_600_000, "ada-id"), Profile("Ada Android", "ada_android", "Park School", "👋", "Happy to help", maskedEmail = "a•••@example.invalid")) }
        store = storage.open(storage.space("audit-user")).store
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun shot(name: String) {
        rule.waitForIdle(); Thread.sleep(700)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(File(context.filesDir, "shots").also { it.mkdirs() }, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun scr(name: String, dark: Boolean = false, font: Float = 1f, wait: String? = null, after: () -> Unit = {}, body: @Composable () -> Unit) {
        rule.setContent {
            val d = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(d.density, font)) { LimeTheme(dark = dark) { body() } }
        }
        if (wait != null) rule.waitUntil(8_000) { count(wait) > 0 }
        after()
        shot(name + if (dark) "-dark" else "")
    }

    // ---- Messages
    @Test fun messages() = scr("messages", wait = "messages-list") { Shell(link = { ChatListScreen(chats, "Ada Android", onOpen = {}) }) }
    @Test fun messagesDark() = scr("messages", dark = true, wait = "messages-list") { Shell(link = { ChatListScreen(chats, "Ada Android", onOpen = {}) }) }
    @Test fun messagesLargest() = scr("messages-font2", font = 2f, wait = "messages-list") { Shell(link = { ChatListScreen(chats, "Ada Android", onOpen = {}) }) }
    @Test fun messagesEmpty() {
        val empty = ChatsModel(store = { null }, transport = { null }, token = { "t" }, staleToken = { "t" })
        scr("messages-empty", wait = "messages-list") { Shell(link = { ChatListScreen(empty, "Ada Android", onOpen = {}) }) }
    }
    @Test fun newMessage() = scr("new-message") { NewMessageScreen(chats, onClose = {}, onOpenChat = {}, find = { null }, startChat = { id, _ -> "dm:$id" }) }
    @Test fun search() = scr("search", wait = "search-field") { com.limemessenger.lime.ui.chats.SearchScreen(chats, onBack = {}, onOpenChat = {}, onOpenMessage = { _, _ -> }) }

    // ---- Chats
    private fun chatNamed(title: String) = ChatModel(chats.chats.first { it.title == title }.id, chats)
    private fun firstGroup() = chats.chats.firstOrNull { it.isGroup }
    @Test fun chat() { val m = chatNamed("Autumn Reyes"); scr("chat", wait = "chat-messages") { ChatScreen(m, chats, onBack = {}) } }
    @Test fun chatDark() { val m = chatNamed("Autumn Reyes"); scr("chat", dark = true, wait = "chat-messages") { ChatScreen(m, chats, onBack = {}) } }
    @Test fun chatLargest() { val m = chatNamed("Autumn Reyes"); scr("chat-font2", font = 2f, wait = "chat-messages") { ChatScreen(m, chats, onBack = {}) } }
    @Test fun group() { val g = firstGroup()!!; val m = ChatModel(g.id, chats); scr("group", wait = "chat-messages") { ChatScreen(m, chats, onBack = {}) } }
    @Test fun composerOpen() {
        val m = chatNamed("Autumn Reyes")
        scr("chat-composer-open", wait = "composer-field", after = { rule.onNodeWithTag("composer-field").performTextInput("Planning the **trip**"); }) { ChatScreen(m, chats, onBack = {}) }
    }
    @Test fun messageActions() {
        val m = chatNamed("Autumn Reyes")
        scr("message-actions", wait = "chat-messages", after = {
            val theirs = m.messages.first { !it.isOwn }
            rule.onNodeWithTag("message-${theirs.id}").performTouchInput { longClick() }
            rule.waitUntil(5_000) { count("message-actions") > 0 }
        }) { ChatScreen(m, chats, onBack = {}) }
    }
    @Test fun groupInfo() {
        val g = firstGroup()!!
        val model = com.limemessenger.lime.chats.GroupModel(chats, g.id)
        scr("group-info") { com.limemessenger.lime.ui.chats.GroupDetailsScreen(chats, model, "Ada Android", 5, onBack = {}, onLeft = {}) }
    }
    @Test fun groupPicker() = scr("group-picker") { com.limemessenger.lime.ui.chats.GroupPickerScreen(chats, emptyList(), false, onBack = {}, onNext = {}) }
    @Test fun profileOther() {
        val ben = uniffi.lime_core.PublicProfile("ben-id", "Ben Android", "ben_android", "North High", "🎒", "Teaching maths and coaching chess", 1_700_000_000L, true)
        runCatching { scr("profile-other", wait = "profile-username") { PersonProfileScreen("ben-id", "Ben", chats = chats, onBack = {}, load = { ben }) } }
    }

    // ---- Settings
    @Test fun settings() = scr("settings", wait = "settings-name") { SettingsScreen(session, onClose = {}, chats = chats) }
    @Test fun settingsDark() = scr("settings", dark = true, wait = "settings-name") { SettingsScreen(session, onClose = {}, chats = chats) }
    @Test fun settingsLargest() = scr("settings-font2", font = 2f, wait = "settings-name") { SettingsScreen(session, onClose = {}, chats = chats) }
    @Test fun about() = scr("about") { AboutScreen(onBack = {}) }
    @Test fun notifications() = scr("settings-notifications", wait = "notifications-screen") { NotificationsScreen(chats, app.notificationPrefs, onBack = {}) }
    @Test fun storage() = scr("settings-storage") { StorageScreen(chats, app.mediaPrefs, onBack = {}) }
    @Test fun privacy() = scr("settings-privacy") { PrivacyScreen(app.appLock, onBack = {}, linkPreviews = app.linkPreviewPrefs) }
    @Test fun appearance() = scr("settings-appearance") { AppearanceScreen(app.themePrefs, onBack = {}) }
    @Test fun blocked() = scr("settings-blocked") { com.limemessenger.lime.ui.moderation.BlockedScreen(chats, onBack = {}) }

    // ---- Onboarding
    @Test fun welcome() { val s = signedOutSession(); scr("onboarding-welcome", wait = "welcome-continue") { Root(s) } }
    @Test fun welcomeDark() { val s = signedOutSession(); scr("onboarding-welcome", dark = true, wait = "welcome-continue") { Root(s) } }
    @Test fun identifier() { val s = signedOutSession(); scr("onboarding-identifier", wait = "welcome-continue", after = { rule.onNodeWithTag("welcome-continue").performClick(); rule.waitUntil(5_000) { count("identifier-field") > 0 } }) { Root(s) } }
    @Test fun password() {
        val s = signedOutSession()
        scr("onboarding-password", wait = "welcome-continue", after = {
            rule.onNodeWithTag("welcome-continue").performClick(); rule.waitUntil(5_000) { count("identifier-field") > 0 }
            rule.onNodeWithTag("identifier-field").performTextInput("ada@example.com"); rule.onNodeWithTag("onboarding-next").performClick()
            rule.waitUntil(5_000) { count("confirm-yes") > 0 }; rule.onNodeWithTag("confirm-yes").performClick()
            rule.waitUntil(5_000) { count("password-field") > 0 }
        }) { Root(s) }
    }
    private fun signedOutSession(): AccountSession {
        val secrets = SecureBlobStore(File(dir, "secrets2"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        return AccountSession(auth, backend = null, storage = StorageBootstrap(File(dir, "data2"), secrets), secrets = secrets)
    }

    // ---- Jam and bands
    private val posts = listOf(
        Samples.jamPost("p1", "j1", at = 3_000, plain = "Our class garden is blooming: sharing the plan we used for the seed swap.", author = "ben"),
        Samples.jamPost("p2", "j1", at = 2_000, kind = "article", title = "Planning a unit backwards", subtitle = "Start from the end", plain = "How I plan: first the finish line, then the steps.", author = "ben"),
    )
    private fun jamModel(): JamModel = JamModel({ store }, { "Ada" }, source = { listOf(Samples.jam("j1", "Ben's jam", mine = false)) to posts }).also { runBlocking { it.reload() } }
    @Test fun jamFeed() { val m = jamModel(); scr("jam-feed", wait = "jam-feed") { Shell(link = {}, jam = { JamFeedScreen(m, onYours = {}) {} }, selected = Tab.Jam) } }
    @Test fun jamFeedDark() { val m = jamModel(); scr("jam-feed", dark = true, wait = "jam-feed") { Shell(link = {}, jam = { JamFeedScreen(m, onYours = {}) {} }, selected = Tab.Jam) } }
    @Test fun jamReader() { val m = jamModel(); scr("jam-reader", wait = "jam-reader") { JamReaderScreen(posts[1], m) {} } }
    @Test fun band() {
        val fake = FakeBand { store.parseOrgInvite(it) }; fake.myRole = "owner"
        val jam = Samples.jam("band", "The Staff Room", mine = true).copy(about = "A school team: maths and planning together", topics = listOf("Maths", "Grade 4"), postCount = 2u)
        val m = JamModel({ store }, { "Ada" }, source = { listOf(jam) to posts.map { it.copy(jamId = "band") } }, bandsBackend = fake).also { runBlocking { it.reload() } }
        scr("band-page", wait = "band-page") { BandScreen(jam, m, onBack = {}, onOpenPost = {}) }
    }

    // ---- More screens
    @Test fun report() {
        val target = uniffi.lime_core.reportTargetMessage("m1", "dm:ben", "ben", "Ben", "Hello there", 1_000, 0u)
        scr("report", wait = "report-sheet") { com.limemessenger.lime.ui.moderation.ReportDialog(target, chats, onDismiss = {}) }
    }
    @Test fun requests() = scr("requests") { com.limemessenger.lime.ui.chats.RequestsScreen(chats, onOpen = {}, onBack = {}) }
    @Test fun formatting() {
        val m = chatNamed("Autumn Reyes")
        scr("chat-format-strip", wait = "composer-field", after = { rule.onNodeWithTag("composer-field").performTextInput("Planning the trip"); rule.onNodeWithTag("composer-aa", useUnmergedTree = true).performClick() }) { ChatScreen(m, chats, onBack = {}) }
    }
    private fun bandModel(role: String?, mine: Boolean): Pair<uniffi.lime_core.JamInfo, JamModel> {
        val fake = FakeBand { store.parseOrgInvite(it) }; fake.myRole = role
        fake.groupList = mutableListOf(uniffi.lime_core.OrgGroupInfo("grp:open", "Everyone", true, false, false), uniffi.lime_core.OrgGroupInfo("grp:mine", "Planning", false, true, true))
        val jam = Samples.jam("band", "The Staff Room", mine = mine).copy(about = "A school team: maths and planning together", topics = listOf("Maths", "Grade 4"), postCount = 2u)
        return jam to JamModel({ store }, { "Ada" }, source = { listOf(jam) to posts.map { it.copy(jamId = "band") } }, bandsBackend = fake).also { runBlocking { it.reload() } }
    }
    @Test fun bandMembers() { val (jam, m) = bandModel("owner", true); scr("band-members", wait = "band-page", after = { rule.onNodeWithTag("band-tab-members", useUnmergedTree = true).performClick() }) { BandScreen(jam, m, onBack = {}, onOpenPost = {}) } }
    @Test fun bandGroups() { val (jam, m) = bandModel("owner", true); scr("band-groups", wait = "band-page", after = { rule.onNodeWithTag("band-tab-groups", useUnmergedTree = true).performClick() }) { BandScreen(jam, m, onBack = {}, onOpenPost = {}) } }
    @Test fun yourJam() {
        val m = jamModel()
        scr("jam-yours", wait = "jam-yours") { com.limemessenger.lime.ui.jam.YourJamScreen(m, com.limemessenger.lime.jam.JamDrafts(File(dir, "drafts")), onBack = {}, onCompose = {}) }
    }
}
