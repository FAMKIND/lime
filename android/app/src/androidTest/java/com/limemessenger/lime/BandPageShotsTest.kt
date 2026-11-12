package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.Samples
import com.limemessenger.lime.jam.BandBackend
import com.limemessenger.lime.jam.BandLinks
import com.limemessenger.lime.jam.JamModel
import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.KeystoreKey
import com.limemessenger.lime.keys.SecureBlobStore
import com.limemessenger.lime.storage.StorageBootstrap
import com.limemessenger.lime.ui.band.BandInviteSheet
import com.limemessenger.lime.ui.band.BandJoinDialog
import com.limemessenger.lime.ui.band.BandMembersScreen
import com.limemessenger.lime.ui.band.BandScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore
import uniffi.lime_core.OrgInvite
import uniffi.lime_core.OrgMemberInfo

/** NOT a test: the LIME-315b screenshots (the band page, Members, the invite sheet, the join dialog; light, dark, 200% font) into files/shots (`tools/shots-315b.sh`). `@Staging` only so the plain pass skips it. */
@Staging
@RunWith(AndroidJUnit4::class)
class BandPageShotsTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private val alias = "lime.test.bandshots2"

    /** Made-up members and codes; the *reading* of a code is the real core's (`parse_org_invite`), as is the rule the app follows (`can_manage` is whatever this fake reports, as the core would). */
    private inner class FakeBand : BandBackend {
        val people = mutableListOf(
            OrgMemberInfo("me", "Ada Android", 1u, "owner", true, false),
            OrgMemberInfo("ben", "Ben Android", 2u, "writer", false, true),
            OrgMemberInfo("cleo", "Cleo Android", 3u, "member", false, true),
        )
        var token = 1
        var inviteOn = true
        val roleChanges = mutableListOf<Triple<String, String, String>>()
        val removed = mutableListOf<String>()
        val joined = mutableListOf<String>()
        override suspend fun members(jamId: String) = people.toList()
        override suspend fun inviteCode(jamId: String) = if (inviteOn) "$jamId.me.token$token" else null
        override suspend fun resetInvite(jamId: String, on: Boolean): String? { inviteOn = on; if (on) token++; return inviteCode(jamId) }
        override suspend fun setRole(jamId: String, userId: String, role: String): Boolean { roleChanges += Triple(jamId, userId, role); people.replaceAll { if (it.userId == userId) it.copy(role = role) else it }; return true }
        override suspend fun remove(jamId: String, userId: String): Boolean { removed += userId; people.removeAll { it.userId == userId }; return true }
        override suspend fun parse(code: String): OrgInvite? = store.parseOrgInvite(code)
        override suspend fun join(code: String): Boolean { joined += code; return true }
    }
    private val fake = FakeBand()
    private val band = Samples.jam("band", "The Staff Room", mine = true, created = 2_000).copy(about = "A school team", topics = listOf("Maths", "Grade 4"), postCount = 2u)
    private val posts = listOf(
        Samples.jamPost("p1", "band", at = 3_000, plain = "Our first band post"),
        Samples.jamPost("p2", "band", at = 2_000, kind = "article", title = "Planning together", plain = "How we plan"),
        Samples.jamPost("other", "someone-else", at = 5_000, plain = "Not the band's"),
    )
    private fun model() = JamModel({ store }, { "Ben" }, source = { listOf(band) to posts }, bandsBackend = fake).also { runBlocking { it.reload() } }
    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun text(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString { it.text }
    private fun words(tag: String) = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()


    private fun shot(name: String) {
        rule.waitForIdle(); Thread.sleep(900)
        val bitmap = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        File(File(context.filesDir, "shots").also { it.mkdirs() }, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun themed(font: Float, dark: Boolean, content: @androidx.compose.runtime.Composable () -> Unit) = rule.setContent {
        val d = androidx.compose.ui.platform.LocalDensity.current
        androidx.compose.runtime.CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(d.density, font)) { LimeTheme(dark = dark) { content() } }
    }
    @Before fun setUp() {
        dir = File(context.cacheDir, "bandpageshots-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("bandpageshots-user")).store
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun page(info: Boolean, font: Float, dark: Boolean, name: String) {
        val m = model(); themed(font, dark) { BandScreen(band, m, onBack = {}, onOpenPost = {}) }
        rule.waitUntil(5_000) { count("band-page") > 0 }
        if (info) { rule.onNodeWithTag("band-tab-info", useUnmergedTree = true).performClick(); rule.waitUntil(5_000) { count("band-about") > 0 } }
        shot(name)
    }
    @Test fun bandPagePosts() = page(false, 1f, false, "1-band-posts")
    @Test fun bandPageInfo() = page(true, 1f, false, "2-band-info")
    @Test fun bandPageInfoDarkLargestFont() = page(true, 2f, true, "3-band-info-dark-font-2")
    private fun members(font: Float, dark: Boolean, name: String) {
        val m = model(); themed(font, dark) { BandMembersScreen(band, m, onBack = {}) }
        rule.waitUntil(5_000) { count("band-member-me") > 0 }
        shot(name)
    }
    @Test fun members() = members(1f, false, "4-members")
    @Test fun membersDarkLargestFont() = members(2f, true, "5-members-dark-font-2")
    @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
    @Test fun inviteSheet() {
        val m = model(); themed(1f, false) { BandInviteSheet(band, m, onDismiss = {}) }
        rule.waitUntil(5_000) { count("band-invite-text") > 0 }
        shot("6-invite")
    }
    @Test fun joinDialog() {
        val m = model(); themed(1f, false) { BandJoinDialog(m, onDismiss = {}) }
        rule.waitUntil(5_000) { count("band-join-field") > 0 }
        rule.onNodeWithTag("band-join-field", useUnmergedTree = true).performTextInput("not a code")
        rule.onNodeWithTag("band-join-go", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-join-bad") > 0 }
        shot("7-join-bad-code")
    }
}
