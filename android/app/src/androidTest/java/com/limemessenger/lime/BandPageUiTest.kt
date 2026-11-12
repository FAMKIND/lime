package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
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

/** LIME-315b: the band page (Posts | Info), members with roles, the invite link and joining by a code, against a made-up band (the core reads the codes: no network, no account). */
@RunWith(AndroidJUnit4::class)
class BandPageUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private val alias = "lime.test.bandpage"

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

    @Before fun setUp() {
        dir = File(context.cacheDir, "bandpage-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("bandpage-user")).store
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    @Test fun theBandPageShowsOnlyItsOwnPostsAndInfoHasTheAboutTheTagsAndTheMemberCount() {
        val m = model()
        val opened = mutableListOf<String>()
        rule.setContent { LimeTheme { BandScreen(band, m, onBack = {}, onOpenPost = { opened += it.postId }) } }
        rule.waitUntil(5_000) { count("band-page") > 0 }
        assertEquals("The Staff Room", text("band-title"))
        assertEquals("only the band's posts, newest first", 1, count("band-post-p1")); assertEquals(1, count("band-post-p2")); assertEquals(0, count("band-post-other"))
        rule.onNodeWithTag("band-post-p2", useUnmergedTree = true).performClick()
        assertEquals(listOf("p2"), opened)
        rule.onNodeWithTag("band-tab-info", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-about") > 0 }
        assertEquals("A school team", text("band-about")); assertEquals("Maths · Grade 4", text("band-topics"))
        rule.waitUntil(5_000) { words("band-info-members") == "Members, 3" }
        assertTrue("the tabs say selected to TalkBack", rule.onNodeWithTag("band-tab-info", useUnmergedTree = true).fetchSemanticsNode().config[SemanticsProperties.Selected])
    }

    @Test fun membersListsMeAsOwnerAsOneStopPerRowAndTheOwnerChangesARoleAndRemovesSomeone() {
        val m = model()
        rule.setContent { LimeTheme { BandMembersScreen(band, m, onBack = {}) } }
        rule.waitUntil(5_000) { count("band-member-me") > 0 }
        assertEquals("You, Owner", words("band-member-me"))
        assertEquals("Ben Android, Writer", words("band-member-ben"))
        assertEquals("3 of 100", text("band-members-count"))
        // The core says who can be managed: Ben can, I cannot (myself).
        rule.onNodeWithTag("band-member-ben", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-member-sheet") > 0 }
        rule.onNodeWithTag("band-role-member", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { words("band-member-ben") == "Ben Android, Member" }
        assertEquals(listOf(Triple("band", "ben", "member")), fake.roleChanges)
        rule.onNodeWithTag("band-member-cleo", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-remove") > 0 }
        rule.onNodeWithTag("band-remove", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-remove-confirm") > 0 }
        assertTrue("nothing is removed before the question is answered", fake.removed.isEmpty())
        rule.onNodeWithTag("band-remove-confirm", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-member-cleo") == 0 }
        assertEquals(listOf("cleo"), fake.removed)
    }

    @Test fun theInviteSheetShowsALinkWhoseCodeTheCoreAcceptsAndNewLinkChangesItAndOffTurnsItOff() {
        val m = model()
        rule.setContent { LimeTheme { BandInviteSheet(band, m, onDismiss = {}) } }
        rule.waitUntil(5_000) { count("band-invite-text") > 0 }
        val first = text("band-invite-text")
        assertTrue(first, first.startsWith("https://limemessenger.com/b/#band.me.token1"))
        val parsed = store.parseOrgInvite(BandLinks.code(first))
        assertNotNull("the core reads the code out of the link", parsed)
        assertEquals("band", parsed!!.jamId)
        rule.onNodeWithTag("band-invite-new", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-invite-new-confirm") > 0 }
        assertEquals("the old link is still the one until the question is answered", first, text("band-invite-text"))
        rule.onNodeWithTag("band-invite-new-confirm", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-invite-text") > 0 && text("band-invite-text") != first }
        assertTrue(text("band-invite-text").endsWith("token2"))
        rule.onNodeWithTag("band-invite-off", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-invite-is-off") > 0 }
        rule.onNodeWithTag("band-invite-on", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-invite-text") > 0 }
    }

    @Test fun joiningWithAWrongCodeSaysSoAndAGoodLinkOrCodeAsksToJoin() {
        val m = model()
        rule.setContent { LimeTheme { BandJoinDialog(m, onDismiss = {}) } }
        rule.waitUntil(5_000) { count("band-join-field") > 0 }
        assertTrue("nothing to send for an empty field", SemanticsProperties.Disabled in rule.onNodeWithTag("band-join-go", useUnmergedTree = true).fetchSemanticsNode().config)
        rule.onNodeWithTag("band-join-field", useUnmergedTree = true).performTextInput("this is not a code")
        rule.onNodeWithTag("band-join-go", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-join-bad") > 0 }
        assertTrue("nothing was sent", fake.joined.isEmpty())
        rule.onNodeWithTag("band-join-field", useUnmergedTree = true).performTextInput("")
        rule.onNodeWithTag("band-join-field", useUnmergedTree = true).performTextReplacement2("https://limemessenger.com/b/#jam9.writer9.tok9")
        rule.onNodeWithTag("band-join-go", useUnmergedTree = true).performClick()
        rule.waitUntil(5_000) { count("band-join-asked") > 0 }
        assertEquals("the code was read out of the pasted link", listOf("jam9.writer9.tok9"), fake.joined)
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.performTextReplacement2(t: String) = performTextReplacement(t)
}
