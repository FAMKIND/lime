package com.limemessenger.lime

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
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
import com.limemessenger.lime.ui.jam.JamReaderScreen
import com.limemessenger.lime.ui.jam.YourJamScreen
import com.limemessenger.lime.ui.theme.LimeTheme
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.lime_core.LimeStore
import uniffi.lime_core.OrgGroupInfo

/**
 * LIME-315d: what a band looks like to each person (the made-up band of `FakeBand`; the core's own `can_manage` answers are the fake's `canManage`, never a Kotlin copy): the **owner**, a **writer**, a **member** and a
 * **subscriber** (follows, not a member); the groups tab (Join/Open, New group), Leave band, the Subscribe pill's confirm, "View band" in the reader, "Bands you belong to", and the Join dialog's states.
 */
@RunWith(AndroidJUnit4::class)
class BandViewsUiTest {
    @get:Rule val rule = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var dir: File
    private lateinit var store: LimeStore
    private val alias = "lime.test.bandviews"
    private val fake = FakeBand { store.parseOrgInvite(it) }
    private val posts = listOf(Samples.jamPost("p1", "band", at = 3_000, plain = "A post by the band", displayAs = "jam"))

    @Before fun setUp() {
        dir = File(context.cacheDir, "bandviews-${System.nanoTime()}").also { it.mkdirs() }
        val secrets = SecureBlobStore(File(dir, "secrets"), KeyWrapper(KeystoreKey.getOrCreate(alias)))
        val storage = StorageBootstrap(File(dir, "data"), secrets)
        store = storage.open(storage.space("bandviews-user")).store
    }
    @After fun tearDown() { store.close(); dir.deleteRecursively(); KeystoreKey.delete(alias) }

    private fun count(tag: String) = rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().size
    private fun text(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().config[SemanticsProperties.Text].joinToString { it.text }   // (the merged tree: a pill's words are its child)
    private fun click(tag: String) { runCatching { rule.onNodeWithTag(tag, useUnmergedTree = true).performScrollTo() }; rule.onNodeWithTag(tag, useUnmergedTree = true).performClick() }
    private fun model(jam: uniffi.lime_core.JamInfo) = JamModel({ store }, { "Ben" }, source = { listOf(jam) to posts }, bandsBackend = fake).also { runBlocking { it.reload() } }
    /** A band I follow (a writer, a member or a subscriber) vs one I made. */
    private fun followed(status: String = "active") = Samples.jam("band", "The Staff Room", mine = false, status = status).copy(about = "A school team", writer = "me")
    private fun owned() = Samples.jam("band", "The Staff Room", mine = true).copy(about = "A school team")
    private fun show(jam: uniffi.lime_core.JamInfo, onBack: () -> Unit = {}, onChat: (String) -> Unit = {}) {
        val m = model(jam)
        rule.setContent { LimeTheme { BandScreen(jam, m, onBack = onBack, onOpenPost = {}, onOpenChat = onChat) } }
        rule.waitUntil(5_000) { count("band-page") > 0 && count("band-your-role") + count("band-subscribe") + count("band-tab-info") > 0 }
    }
    private fun nobodyCanBeManaged() { fake.people.replaceAll { it.copy(canManage = false) } }

    @Test fun theOwnerSeesEveryTabInviteAndNewGroup() {
        fake.myRole = "owner"
        show(owned())
        rule.waitUntil(5_000) { count("band-tab-members") > 0 }
        for (t in listOf("band-tab-posts", "band-tab-info", "band-tab-members", "band-tab-groups")) assertEquals(t, 1, count(t))
        assertEquals("Your role: Owner", text("band-your-role"))
        assertEquals("no Subscribe pill on my own band", 0, count("band-subscribe"))
        click("band-tab-members"); rule.waitUntil(5_000) { count("band-member-me") > 0 }
        assertEquals("the owner can invite", 1, count("band-invite-open"))
        assertEquals("the owner cannot leave their own band", 0, count("band-leave"))
        click("band-tab-groups"); rule.waitUntil(5_000) { count("band-groups") > 0 }
        assertEquals("the owner can make a group", 1, count("band-new-group"))
    }

    @Test fun aWriterSeesMembersAndGroupsReadOnlyAndCanLeaveButNotInviteOrMakeAGroup() {
        fake.myRole = "writer"; fake.people.replaceAll { if (it.userId == "me") it.copy(role = "writer") else it }; nobodyCanBeManaged()
        show(followed())
        rule.waitUntil(5_000) { count("band-tab-members") > 0 }
        assertEquals("Your role: Writer", text("band-your-role"))
        click("band-tab-members"); rule.waitUntil(5_000) { count("band-member-me") > 0 }
        assertEquals("no Invite for a writer", 0, count("band-invite-open"))
        rule.onNodeWithTag("band-member-ben", useUnmergedTree = true).performClick()   // not manageable: no sheet
        rule.waitForIdle()
        assertEquals(0, count("band-member-sheet"))
        assertEquals("a writer can leave", 1, count("band-leave"))
        click("band-tab-groups"); rule.waitUntil(5_000) { count("band-groups") > 0 }
        assertEquals("no New group for a writer", 0, count("band-new-group"))
    }

    @Test fun aMemberCanLeaveAfterTheQuestionAndLeavingClosesThePage() {
        fake.myRole = "member"; fake.people.replaceAll { if (it.userId == "me") it.copy(role = "member") else it }; nobodyCanBeManaged()
        var closed = false
        show(followed(), onBack = { closed = true })
        rule.waitUntil(5_000) { count("band-tab-members") > 0 }
        assertEquals("Your role: Member", text("band-your-role"))
        click("band-tab-members"); rule.waitUntil(5_000) { count("band-leave") > 0 }
        click("band-leave")
        rule.waitUntil(5_000) { count("band-leave-confirm") > 0 }
        assertTrue("nothing happens before the question is answered", !fake.left)
        click("band-leave-confirm")
        rule.waitUntil(5_000) { closed }
        assertTrue(fake.left)
    }

    @Test fun aSubscriberSeesPostsAndInfoAndSubscribedAndNoMembersNoInviteNoGroups() {
        fake.myRole = null
        show(followed())
        rule.waitUntil(5_000) { count("band-subscribe") > 0 }
        assertEquals("only the public tabs", 0, count("band-tab-members")); assertEquals(0, count("band-tab-groups"))
        assertEquals(0, count("band-your-role")); assertEquals(0, count("band-invite-open"))
        assertEquals("Subscribed ✓", text("band-subscribe"))
        assertEquals("the band's post is there to read", 1, count("band-post-p1"))
        click("band-subscribe")   // asks before it unsubscribes
        rule.waitUntil(5_000) { count("band-unsubscribe-confirm") > 0 }
    }

    @Test fun aBandIDoNotFollowOffersSubscribeAndSaysSubscribeToRead() {
        fake.myRole = null
        val jam = followed(status = "left")
        val m = JamModel({ store }, { "Ben" }, source = { listOf(jam) to emptyList() }, bandsBackend = fake).also { runBlocking { it.reload() } }
        rule.setContent { LimeTheme { BandScreen(jam, m, onBack = {}, onOpenPost = {}) } }
        rule.waitUntil(5_000) { count("band-subscribe") > 0 }
        assertEquals("Subscribe", text("band-subscribe"))
        assertEquals(1, count("band-no-posts"))
        assertEquals("Subscribe to read their posts.", text("band-no-posts"))
    }

    @Test fun theGroupsTabJoinsAnOpenGroupOpensOneIAmInAndAnOwnerMakesAGroup() {
        fake.myRole = "owner"
        fake.groupList = mutableListOf(OrgGroupInfo("grp:open", "Everyone", true, false, false), OrgGroupInfo("grp:mine", "Planning", false, true, true), OrgGroupInfo("grp:closed", "Owners only", false, false, false))
        var opened: String? = null
        show(owned(), onChat = { opened = it })
        rule.waitUntil(5_000) { count("band-tab-groups") > 0 }
        click("band-tab-groups"); rule.waitUntil(5_000) { count("band-group-grp:open") > 0 }
        assertEquals("an open group I am not in has Join", 1, count("band-group-join-grp:open"))
        assertEquals("an invite-only group I am not in has neither", 0, count("band-group-join-grp:closed") + count("band-group-open-grp:closed"))
        click("band-group-open-grp:mine"); assertEquals("grp:mine", opened)
        click("band-group-join-grp:open")
        rule.waitUntil(5_000) { count("band-group-open-grp:open") > 0 }
        assertEquals(listOf("grp:open"), fake.joinedGroups)
        // New group: a name, Open, and someone to start with.
        click("band-new-group"); rule.waitUntil(5_000) { count("band-group-name") > 0 }
        assertTrue("Create is off without a name", SemanticsProperties.Disabled in rule.onNodeWithTag("band-group-create", useUnmergedTree = true).fetchSemanticsNode().config)
        rule.onNodeWithTag("band-group-name", useUnmergedTree = true).performTextInput("Staff chat")
        click("band-group-pick-ben")
        rule.waitUntil(5_000) { SemanticsProperties.Disabled !in rule.onNodeWithTag("band-group-create", useUnmergedTree = true).fetchSemanticsNode().config }
        click("band-group-create")
        rule.waitUntil(5_000) { fake.createdGroups.isNotEmpty() }
        assertEquals(Triple("Staff chat", true, listOf("ben")), fake.createdGroups.single())
        rule.waitUntil(5_000) { count("band-group-grp:new-3") > 0 }
    }

    @Test fun aPostMadeAsABandOffersViewBandAndAPersonalPostDoesNot() {
        val m = model(owned())
        var viewed: String? = null
        rule.setContent { LimeTheme { JamReaderScreen(posts[0], m, myId = "me", onViewBand = { viewed = it }, onBack = {}) } }
        rule.waitUntil(5_000) { count("jam-reader-view-band") > 0 }
        click("jam-reader-view-band"); assertEquals("band", viewed)
    }

    @Test fun aPersonalPostHasNoViewBand() {
        val m = model(owned())
        val personal = Samples.jamPost("p2", "band", at = 2_000, plain = "A personal post", displayAs = "person")
        rule.setContent { LimeTheme { JamReaderScreen(personal, m, myId = "me", onViewBand = {}, onBack = {}) } }
        rule.waitUntil(5_000) { count("jam-reader") > 0 }
        assertEquals(0, count("jam-reader-view-band"))
    }

    @Test fun yourJamListsTheBandsIBelongToWithoutOwningAndOpensOne() {
        fake.myRole = "writer"
        val own = Samples.jam("own", "Ada's notes", mine = true, created = 1_000)
        val m = JamModel({ store }, { "Ben" }, source = { listOf(own) to emptyList() }, bandsBackend = fake).also { runBlocking { it.reload() } }
        var opened: String? = null
        rule.setContent { LimeTheme { YourJamScreen(m, com.limemessenger.lime.jam.JamDrafts(dir), onBack = {}, onCompose = {}, onOpenBand = { opened = it }) } }
        rule.waitUntil(5_000) { count("band-belong-band") > 0 }
        click("band-belong-band"); assertEquals("band", opened)
    }

    private fun joinWith(answer: String?, text: String = "https://limemessenger.com/b/#jam9.writer9.tok9", joinOk: Boolean = true, expect: String) {
        fake.joinStateAnswer = answer; fake.joinOk = joinOk
        val m = model(owned())
        rule.setContent { LimeTheme { BandJoinDialog(m, onDismiss = {}) } }
        rule.waitUntil(5_000) { count("band-join-field") > 0 }
        rule.onNodeWithTag("band-join-field", useUnmergedTree = true).performTextInput(text)
        click("band-join-go")
        rule.waitUntil(5_000) { count(expect) > 0 }
    }

    @Test fun joiningWithABadTextSaysSoAndSendsNothing() { joinWith("asked", text = "not a band", expect = "band-join-bad"); assertTrue(fake.joined.isEmpty()) }
    @Test fun joiningShowsAskedWhenAnOwnersPhoneHasNotAddedMeYet() { joinWith("asked", expect = "band-join-asked"); assertEquals(1, count("band-join-done")); assertEquals(listOf("jam9.writer9.tok9"), fake.joined) }
    @Test fun joiningShowsJoinedWhenIAmIn() { joinWith("joined", expect = "band-join-joined"); assertEquals(1, count("band-join-done")) }
    @Test fun joiningShowsFullWhenTheBandIsFull() { joinWith("full", expect = "band-join-full") }
    @Test fun joiningShowsRefusedWhenTheOwnerRefused() { joinWith("refused", expect = "band-join-refused") }
    @Test fun joiningSaysItCouldNotAskWhenTheSendFails() { joinWith("asked", joinOk = false, expect = "band-join-failed") }
}
