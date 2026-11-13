package com.limemessenger.lime

import android.graphics.Bitmap
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.FakeBand
import com.limemessenger.lime.chats.Samples
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.band.BandJoinDialog
import com.limemessenger.lime.ui.band.BandScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore
import uniffi.lime_core.OrgGroupInfo

/** NOT a test: the LIME-315d screenshots (what each person sees of a band; light, dark, 200% font) into files/shots (`tools/shots-night5.sh`). `@Staging` only so the plain pass skips it. */
@Staging
@RunWith(AndroidJUnit4::class)
class BandViewsShotsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private val alias = "lime.test.bandviewshots"
    private val fake = FakeBand { store.parseOrgInvite(it) }
    private val posts = listOf(Samples.jamPost("p1", "band", at = 3_000, plain = "Our first post as the band", displayAs = "jam"), Samples.jamPost("p2", "band", at = 2_000, kind = "article", title = "Planning together", plain = "How we plan", displayAs = "jam"))

    @Before fun setUp() {
        dir = File(context.cacheDir, "bandviewshots-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("bandviewshots-user")).store
        fake.groupList = mutableListOf(OrgGroupInfo("grp:open", "Everyone", true, false, false), OrgGroupInfo("grp:mine", "Planning", false, true, true), OrgGroupInfo("grp:closed", "Owners only", false, false, false))
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun click(tag: String) { runCatching { rule.onNodeWithTag(tag, useUnmergedTree = true).performScrollTo() }; rule.onNodeWithTag(tag, useUnmergedTree = true).performClick() }
    private fun shot(name: String) {
        rule.waitForIdle(); Thread.sleep(800)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(File(context.filesDir, "shots").also { it.mkdirs() }, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun followed(status: String = "active") = Samples.jam("band", "The Staff Room", mine = false, status = status).copy(about = "A school team: maths and planning together", topics = listOf("Maths", "Grade 4"), postCount = 2u, writer = "me")
    private fun owned() = Samples.jam("band", "The Staff Room", mine = true).copy(about = "A school team: maths and planning together", topics = listOf("Maths", "Grade 4"), postCount = 2u)
    private fun page(role: String?, jam: uniffi.lime_core.JamInfo, tab: String?, font: Float, dark: Boolean, name: String, after: () -> Unit = {}) {
        fake.myRole = role
        if (role != null && role != "owner") { fake.people.replaceAll { if (it.userId == "me") it.copy(role = role) else it.copy(canManage = false) } }
        val m = JamModel({ store }, { "Ben" }, source = { listOf(jam) to posts }, bandsBackend = fake).also { runBlocking { it.reload() } }
        rule.setContent {
            val d = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(d.density, font)) { LimeTheme(dark = dark) { BandScreen(jam, m, onBack = {}, onOpenPost = {}) } }
        }
        rule.waitUntil(5_000) { count("band-page") > 0 }
        if (role != null) rule.waitUntil(5_000) { count("band-tab-members") > 0 } else rule.waitUntil(5_000) { count("band-subscribe") > 0 }
        if (tab != null) click("band-tab-$tab")
        after()
        shot(name)
    }

    @Test fun ownerPosts() = page("owner", owned(), null, 1f, false, "1-owner-posts")
    @Test fun ownerMembers() = page("owner", owned(), "members", 1f, false, "2-owner-members-invite") { rule.waitUntil(5_000) { count("band-member-me") > 0 } }
    @Test fun ownerGroups() = page("owner", owned(), "groups", 1f, false, "3-owner-groups") { rule.waitUntil(5_000) { count("band-group-grp:open") > 0 } }
    @Test fun ownerNewGroup() = page("owner", owned(), "groups", 1f, false, "4-owner-new-group") { rule.waitUntil(5_000) { count("band-new-group") > 0 }; click("band-new-group"); rule.waitUntil(5_000) { count("band-group-name") > 0 }; rule.onNodeWithTag("band-group-name", useUnmergedTree = true).performTextInput("Staff chat") }
    @Test fun writerMembers() = page("writer", followed(), "members", 1f, false, "5-writer-members-leave") { rule.waitUntil(5_000) { count("band-member-me") > 0 } }
    @Test fun memberGroups() = page("member", followed(), "groups", 1f, false, "6-member-groups-no-new") { rule.waitUntil(5_000) { count("band-group-grp:open") > 0 } }
    @Test fun subscriberPosts() = page(null, followed(), null, 1f, false, "7-subscriber-posts-subscribed")
    @Test fun notFollowing() = page(null, followed("left"), null, 1f, false, "8-not-following-subscribe")
    @Test fun ownerMembersDarkLargestFont() = page("owner", owned(), "members", 2f, true, "9-owner-members-dark-font-2") { rule.waitUntil(5_000) { count("band-member-me") > 0 } }
    @Test fun subscriberDarkLargestFont() = page(null, followed(), null, 2f, true, "10-subscriber-dark-font-2")
    @Test fun joinDialogFull() {
        fake.joinStateAnswer = "full"
        val m = JamModel({ store }, { "Ben" }, source = { listOf(owned()) to posts }, bandsBackend = fake).also { runBlocking { it.reload() } }
        rule.setContent { LimeTheme { BandJoinDialog(m, onDismiss = {}) } }
        rule.waitUntil(5_000) { count("band-join-field") > 0 }
        rule.onNodeWithTag("band-join-field", useUnmergedTree = true).performTextInput("https://limemessenger.com/b/#jam9.writer9.tok9")
        click("band-join-go"); rule.waitUntil(5_000) { count("band-join-full") > 0 }
        shot("11-join-full")
    }
}
