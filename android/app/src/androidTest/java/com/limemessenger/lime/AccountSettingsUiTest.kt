package com.limemessenger.lime

import android.content.Context
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.auth.AccountSession
import com.limemessenger.lime.auth.AuthTokens
import com.limemessenger.lime.auth.FakeAuthService
import com.limemessenger.lime.auth.Profile
import com.limemessenger.lime.chats.ArrivalBanner
import com.limemessenger.lime.chats.ChatsModel
import com.limemessenger.lime.chats.MediaPrefs
import com.limemessenger.lime.chats.NotificationPrefs
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.security.AppLock
import com.limemessenger.lime.security.LockAuthenticator
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.settings.ChangePasswordScreen
import com.limemessenger.lime.ui.settings.NotificationsScreen
import com.limemessenger.lime.ui.settings.PrivacyScreen
import com.limemessenger.lime.ui.settings.SettingsScreen
import com.limemessenger.lime.ui.settings.StorageScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.AutoDownload
import uniffi.lime_core.KeepMedia
import uniffi.lime_core.LimeStore
import uniffi.lime_core.LockDelay
import uniffi.lime_core.NotificationPreview

/** LIME-306: change password, notifications, storage and Lock lime, against fakes (a fake auth, a fake lock authenticator, a fake clock). */
@RunWith(AndroidJUnit4::class)
class AccountSettingsUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val auth = FakeAuthService()
    private lateinit var dir: File
    private lateinit var session: AccountSession
    private lateinit var store: LimeStore
    private lateinit var chats: ChatsModel
    private val alias = "lime.test.account.settings"

    @Before fun setUp() {
        dir = File(context.cacheDir, "account-settings-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        session = AccountSession(auth, backend = null, storage = storage, secrets = secrets)
        runBlocking { session.completeSignIn(AuthTokens("a", "r", System.currentTimeMillis() + 3_600_000, "ada-id"), Profile("Ada Android", "ada_android", null, null, null, maskedEmail = "a•••@example.invalid")) }
        store = session.store!!
        store.seedSampleDataIfEmpty()
        chats = ChatsModel(store = { store }, transport = { null }, token = { "t" }, staleToken = { "t" })
        runBlocking { chats.reload() }
    }

    @After fun tearDown() { dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun prefs(name: String) = context.getSharedPreferences(name, Context.MODE_PRIVATE).also { it.edit().clear().commit() }

    // ---- change password

    @Test fun changePasswordGoesThroughTheCodeAndAWrongCurrentPasswordSaysSo() {
        var back = false
        rule.setContent { LimeTheme { ChangePasswordScreen(session, onBack = { back = true }) } }
        rule.onNodeWithTag("pw-send").assertIsNotEnabled()
        rule.onNodeWithTag("pw-current").performTextInput("wrong password")
        rule.onNodeWithTag("pw-new").performTextInput("a brand new password")
        rule.onNodeWithTag("pw-confirm").performTextInput("a brand new password")
        rule.onNodeWithTag("pw-send").assertIsEnabled().performClick()
        rule.waitUntil(5_000) { count("pw-error") > 0 }
        rule.onNodeWithTag("pw-error", useUnmergedTree = true).assertTextEquals("That isn't your current password.")
        // The right one: the code step, a wrong code, the right code, done.
        auth.correctPassword = "wrong password"
        rule.onNodeWithTag("pw-send").performClick()
        rule.waitUntil(5_000) { count("pw-code") > 0 }
        rule.onNodeWithTag("pw-code").performTextInput("000000")
        rule.onNodeWithTag("pw-verify").performClick()
        rule.waitUntil(5_000) { count("pw-error") > 0 }
        rule.onNodeWithTag("pw-error", useUnmergedTree = true).assertTextEquals("That code isn't right.")
        rule.onNodeWithTag("pw-back").performClick()
        rule.waitUntil(5_000) { count("pw-send") > 0 }
        rule.onNodeWithTag("pw-send").performClick()
        rule.waitUntil(5_000) { count("pw-code") > 0 }
        rule.onNodeWithTag("pw-code").performTextInput("123456")
        rule.onNodeWithTag("pw-verify").performClick()
        rule.waitUntil(5_000) { count("pw-done") > 0 }
        rule.onNodeWithTag("pw-done", useUnmergedTree = true).assertTextEquals("Your password was changed.")
        assertTrue(auth.calls.contains("finishPasswordChange:123456"))
        rule.onNodeWithTag("pw-finish").performClick()
        assertTrue(back)
    }

    // ---- notifications

    @Test fun notificationPreferencesAreKeptAndSayThereIsNoPushYet() {
        val p = NotificationPrefs(prefs("test.notify"))
        rule.setContent { LimeTheme { NotificationsScreen(chats, p, onBack = {}) } }
        rule.onNodeWithTag("notif-no-push", useUnmergedTree = true).assertTextEquals("lime has no push service on Android yet, so alerts show only while lime is open.")
        rule.onNodeWithTag("preview-name_only").performScrollTo().performClick()
        assertEquals(NotificationPreview.NAME_ONLY, p.preview)
        assertEquals(NotificationPreview.NAME_ONLY, NotificationPrefs(context.getSharedPreferences("test.notify", Context.MODE_PRIVATE)).preview)
        rule.onNodeWithTag("notif-toggle").performClick()
        assertFalse(p.enabled)
        rule.waitUntil(5_000) { count("preview-name_only") == 0 }
        rule.onNodeWithTag("notif-toggle").performClick()
        assertTrue(p.enabled)
    }

    private fun summary(id: String, title: String, request: Boolean = false, group: Boolean = false, last: uniffi.lime_core.MessageItem?) = uniffi.lime_core.ConversationSummary(
        activityAt = 0, lastReaction = null, id = id, title = title, isGroup = group, isPinned = false, unread = 0u, requestState = if (request) "pending" else "accepted",
        keyChangePending = false, lastMessage = last, members = listOf(uniffi.lime_core.MemberInfo("lee", "Lee Wong", "LW", 0u, null, null)), groupEmoji = null, verified = false,
        verifiedAt = null, groupEnded = null, myRole = null, markedUnread = false, lastIsReply = false,
    )

    private fun message(id: String, text: String, from: String? = "lee", at: Long = 1_000) = uniffi.lime_core.MessageItem(
        id = id, conversationId = "dm:lee", senderId = from, text = text, sentAt = at, localState = "received", attachments = emptyList(), edited = false, deleted = false,
        reactions = emptyList(), forwarded = false, linkPreview = null, threadRoot = null, emergency = null,
    )

    @Test fun theBannerSaysWhatThePreviewAllowsAndNeverForARequestOrAMutedChatOrTheChatOnScreen() {
        var preview = NotificationPreview.NAME_AND_MESSAGE
        var hide = false
        var muted = false
        val banner = ArrivalBanner(enabled = { true }, preview = { preview }, muted = { muted }, hideText = { hide })
        val old = summary("dm:lee", "Lee Wong", last = message("m1", "old"))
        banner.check(listOf(old), viewing = null)
        assertNull("opening the app announces no history", banner.banner)
        // A new message arrives in a chat that is not on screen: title and words.
        banner.check(listOf(summary("dm:lee", "Lee Wong", last = message("m2", "Can we plan the lesson?", at = 2_000))), viewing = "dm:sam")
        assertEquals("Lee Wong", banner.banner?.title); assertEquals("Can we plan the lesson?", banner.banner?.body)
        banner.dismiss()
        // The lock hides the words; "Name only" says only that there is a message.
        hide = true
        banner.check(listOf(summary("dm:lee", "Lee Wong", last = message("m3", "secret", at = 3_000))), viewing = null)
        assertEquals("New message", banner.banner?.body); assertEquals("lime", banner.banner?.title)
        banner.dismiss(); hide = false; preview = NotificationPreview.NAME_ONLY
        banner.check(listOf(summary("dm:lee", "Lee Wong", last = message("m4", "secret", at = 4_000))), viewing = null)
        assertEquals("New message", banner.banner?.body); assertEquals("Lee Wong", banner.banner?.title)
        banner.dismiss(); preview = NotificationPreview.NAME_AND_MESSAGE
        // The chat on screen only ticks; a muted chat is silent; a request never shows its words.
        banner.check(listOf(summary("dm:lee", "Lee Wong", last = message("m5", "x", at = 5_000))), viewing = "dm:lee")
        assertNull(banner.banner)
        muted = true
        banner.check(listOf(summary("dm:lee", "Lee Wong", last = message("m6", "x", at = 6_000))), viewing = null)
        assertNull(banner.banner)
        muted = false
        banner.check(listOf(summary("dm:new", "Someone", request = true, last = message("m7", "secret words", from = "lee", at = 7_000))), viewing = null)
        assertEquals("Wants to message you", banner.banner?.body)
        // My own messages never announce.
        banner.dismiss()
        banner.check(listOf(summary("dm:lee", "Lee Wong", last = message("m8", "mine", from = null, at = 8_000))), viewing = null)
        assertNull(banner.banner)
    }

    // ---- storage

    @Test fun storageShowsWhatLimeUsesAndKeepsTheChoices() {
        val p = MediaPrefs(prefs("test.media"))
        rule.setContent { LimeTheme { StorageScreen(chats, p, onBack = {}) } }
        rule.waitUntil(10_000) { count("storage-total") > 0 }
        rule.onNodeWithTag("keep-month").performScrollTo().performClick()
        assertEquals(KeepMedia.MONTH, p.keep)
        rule.onNodeWithTag("auto-photos-never").performScrollTo().performClick()
        assertEquals(AutoDownload.NEVER, p.photos)
        rule.onNodeWithTag("auto-videofiles-wifi_and_mobile").performScrollTo().performClick()
        assertEquals(AutoDownload.WIFI_AND_MOBILE, p.videoAndFiles)
        assertEquals(AutoDownload.NEVER, MediaPrefs(context.getSharedPreferences("test.media", Context.MODE_PRIVATE)).photos)
    }

    // ---- Lock lime

    private class Answer(var ok: Boolean) : LockAuthenticator { override suspend fun authenticate(reason: String) = ok }

    @Test fun lockLimeNeedsTheSystemToAgreeAndKeepsItsDelay() {
        val answer = Answer(false)
        val lock = AppLock(prefs("test.lock"), answer)
        rule.setContent { LimeTheme { PrivacyScreen(lock, onBack = {}) } }
        rule.onNodeWithTag("privacy-lock").performClick()
        rule.waitUntil(5_000) { count("privacy-lock-unavailable") > 0 }
        assertFalse(lock.isEnabled)
        answer.ok = true
        rule.onNodeWithTag("privacy-lock").performClick()
        rule.waitUntil(5_000) { lock.isEnabled }
        rule.waitUntil(5_000) { count("lock-delay-one_hour") > 0 }
        rule.onNodeWithTag("lock-delay-one_hour").performScrollTo().performClick()
        assertEquals(LockDelay.ONE_HOUR, lock.delay)
        assertEquals(LockDelay.ONE_HOUR, AppLock(context.getSharedPreferences("test.lock", Context.MODE_PRIVATE)).delay)
        rule.onNodeWithTag("privacy-lock").performClick()
        assertFalse(lock.isEnabled)
    }

    @Test fun theLockEngagesAfterTheDelayAndNotBefore() = runBlocking {
        var now = 1_000_000L
        val answer = Answer(true)
        val sp = prefs("test.lock2")
        val lock = AppLock(sp, answer, clock = { now })
        assertTrue(lock.turnOn())
        lock.changeDelay(LockDelay.ONE_MINUTE)
        // Not locked while in front; a cold start (a new AppLock on the same choices) is locked.
        assertFalse(lock.isLocked)
        assertTrue(AppLock(sp, answer, clock = { now }).isLocked)
        // Away for 59 s: not locked; away for 60 s: locked.
        lock.sceneBecameInactive(); assertTrue(lock.isCovered)
        lock.sceneEnteredBackground(); assertFalse("the delay has not passed", lock.isLocked)
        now += 59_000; lock.sceneBecameActive(); assertFalse(lock.isLocked); assertFalse("the cover goes", lock.isCovered)
        lock.sceneEnteredBackground(); now += 60_000
        assertTrue("the words are hidden once it would be locked", lock.hidesNotificationText())
        lock.sceneBecameActive(); assertTrue(lock.isLocked)
        // A refused system check leaves it locked; an accepted one opens it.
        answer.ok = false; lock.unlock(); assertTrue(lock.isLocked)
        answer.ok = true; lock.unlock(); assertFalse(lock.isLocked)
        // Immediately: locked as soon as it leaves.
        lock.changeDelay(LockDelay.IMMEDIATELY); lock.sceneEnteredBackground(); assertTrue(lock.isLocked)
        Unit
    }

    @Test fun settingsListsTheAccountRows() {
        rule.setContent { LimeTheme { SettingsScreen(session, onClose = {}, chats = chats) } }
        for (tag in listOf("settings-row-password", "settings-row-notifications", "settings-row-storage", "settings-row-privacy")) assertEquals(tag, 1, count(tag))
        // Delete account is not here (a critical design: the user reviews it first).
        assertEquals(0, count("settings-row-delete-account"))
        rule.onNodeWithTag("settings-row-privacy").performClick()
        rule.waitUntil(5_000) { count("privacy-screen") > 0 }
    }
}
