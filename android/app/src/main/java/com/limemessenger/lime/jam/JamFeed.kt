package com.limemessenger.lime.jam

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.compose.runtime.mutableStateMapOf
import org.json.JSONArray
import uniffi.lime_core.JamAttachmentInfo
import uniffi.lime_core.JamCommentInfo
import uniffi.lime_core.JamCountsInfo
import uniffi.lime_core.JamFeedFilter
import uniffi.lime_core.JamFeedSegment
import uniffi.lime_core.JamInfo
import uniffi.lime_core.JamPageInfo
import uniffi.lime_core.JamPostInfo
import uniffi.lime_core.LimeStore

// The feed's rules (which posts, the order, the byline, the excerpt, the segments and filters, which card) are the core's (LIME-311: jam_rules.rs).
// ANDROID DEBT: twin of ios/Lime/Features/Jam/JamPage.swift (JamDates: a date follows the phone's locale, so it stays here); moves into LimeCore in LIME-133

/** Dates on a card: "Oct 22", with the year only when it is not this year; no clock time (LIME-222). */
object JamDates {
    fun short(ms: Long, nowMs: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        val date = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
        val today: LocalDate = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
        return DateTimeFormatter.ofPattern(if (date.year == today.year) "MMM d" else "MMM d, yyyy", locale).format(date)
    }

    /** For TalkBack: "October 22". */
    fun spoken(ms: Long, nowMs: Long = System.currentTimeMillis(), zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        val date = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
        val today = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
        return DateTimeFormatter.ofPattern(if (date.year == today.year) "MMMM d" else "MMMM d, yyyy", locale).format(date)
    }
}

/** What the jam screens need from outside the core: the link, a token, and sending what was queued (as iOS's `ConversationStore` provides). */
class JamEnv(val transport: () -> com.limemessenger.lime.net.HttpTransport?, val token: suspend () -> String, val deliver: suspend () -> Unit)

/**
 * The jam tab: the posts of every jam I follow (an accepted subscription) and my own, newest first, in the segments All, Posts, Articles and Podcasts, with a
 * Saved filter (bookmarks kept on this phone); each post's likes and comments, a post's files, the comments (reply, delete my own), and subscribing to a
 * teacher's jam from their profile. The core stores the posts as they arrive in the mailbox; the feed, order, byline and excerpt are the core's.
 */
class JamModel(
    private val store: () -> LimeStore?,
    private val nameOf: (String) -> String?,
    /** Where the jams and posts come from (the core's store; tests give their own). */
    private val source: (suspend () -> Pair<List<JamInfo>, List<JamPostInfo>>)? = null,
    private val env: JamEnv? = null,
    /** Bookmarks: the ids of saved posts (kept on this phone only). */
    private val savedStore: SavedPosts = SavedPosts.None,
) {
    var posts by mutableStateOf<List<JamPostInfo>>(emptyList())
        private set
    var jams by mutableStateOf<List<JamInfo>>(emptyList())
        private set
    var isLoaded by mutableStateOf(false)
        private set
    /** Counts every read of the jams, so a screen that lists something of them (my subscribers) reads it again when a sync brought news. */
    var reloads by mutableStateOf(0)
        private set
    var segment by mutableStateOf(JamFeedSegment.ALL)
    var savedOnly by mutableStateOf(false)

    /** Each post's likes and comments, as the core has them (mine are counted live). */
    val counts = mutableStateMapOf<String, JamCountsInfo>()
    var saved by mutableStateOf(savedStore.all())
        private set

    /** The filter sheet's choices (LIME-412; the core's `JamFeedFilter`): a media kind, Co-authored, Subscribed, Bands, and Saved (which the pill below also toggles). */
    var mediaFilter by mutableStateOf<uniffi.lime_core.JamFeedMedia?>(null)
    var coauthoredOnly by mutableStateOf(false)
    var subscribedOnly by mutableStateOf(false)
    var bandsOnly by mutableStateOf(false)
    /** The kinds of each post's files (`image`, `video`, `audio`, `file`), for the media filter. */
    private val fileKinds = mutableStateMapOf<String, List<String>>()

    val filter: uniffi.lime_core.JamFeedFilter get() = JamFeedFilter(mediaFilter, coauthoredOnly, subscribedOnly, bandsOnly, savedOnly)
    val activeFilters: Int get() = uniffi.lime_core.jamFilterActiveCount(filter).toInt()
    fun clearFilters() { mediaFilter = null; coauthoredOnly = false; subscribedOnly = false; bandsOnly = false; savedOnly = false }

    /** The posts the segment and the filters let through. */
    val shown: List<JamPostInfo> get() {
        val filter = filter
        return posts.filter { post ->
            uniffi.lime_core.jamFilterMatches(
                post.kind, fileKinds[post.postId].orEmpty(), post.coauthors.isNotEmpty(), post.displayAs == "jam", !isMine(post), post.postId in saved, segment, filter,
            )
        }
    }

    suspend fun reload() {
        try {
            if (source != null) {
                val (found, all) = source.invoke()
                jams = found
                posts = uniffi.lime_core.jamFeedPosts(all, found)
            } else {
                val core = store() ?: return
                val (mine, followed, all) = withContext(Dispatchers.IO) {
                    val mine = core.listMyJams()
                    val followed = core.listJamSubscriptions()
                    val live = (followed.filter { it.status == "active" } + mine).map { it.jamId }.toSet()
                    Triple(mine, followed, live.flatMap { core.listJamPosts(it) })
                }
                jams = mine + followed
                posts = uniffi.lime_core.jamFeedPosts(all, jams)
                refreshCounts()
            }
            reloads += 1
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Keep what is shown.
        }
        isLoaded = true
    }

    private suspend fun refreshCounts() {
        val core = store() ?: return
        val fresh = withContext(Dispatchers.IO) { posts.mapNotNull { p -> runCatching { core.jamPostCounts(p.postId) }.getOrNull() } }
        fresh.forEach { counts[it.postId] = it }
        withContext(Dispatchers.IO) { posts.forEach { p -> runCatching { core.listJamAttachments(p.postId) }.getOrNull()?.let { list -> fileKinds[p.postId] = list.map { it.kind } } } }
    }

    fun countsOf(postId: String): JamCountsInfo = counts[postId] ?: JamCountsInfo(postId, 0u, 0u, 0u, emptyList(), false, false)

    /** The jam's title, or "jam" when it is not known. */
    fun jamTitle(jamId: String): String = jams.firstOrNull { it.jamId == jamId }?.title?.ifEmpty { null } ?: "jam"

    /** The name shown for an author: the jam's title for a post shown as the jam, else the teacher's name. */
    fun authorName(post: JamPostInfo): String = if (post.displayAs == "jam") jamTitle(post.jamId) else teacherName(post.author)

    fun teacherName(userId: String): String = nameOf(userId)?.ifEmpty { null } ?: "A teacher"

    fun byline(post: JamPostInfo): String? = uniffi.lime_core.jamByline(post.coauthors.map { teacherName(it) })

    fun isMine(post: JamPostInfo): Boolean = jams.any { it.mine && it.jamId == post.jamId }

    // ---- ♥ and comments

    /** ♥ or un-♥: my own heart shows at once, and the like goes to the writer with the next delivery. */
    suspend fun toggleLike(post: JamPostInfo) {
        val core = store() ?: return
        val on = !countsOf(post.postId).likedByMe
        withContext(Dispatchers.IO) { runCatching { core.reactToJamPost(post.postId, on) } }
        counts[post.postId] = withContext(Dispatchers.IO) { runCatching { core.jamPostCounts(post.postId) }.getOrNull() } ?: countsOf(post.postId)
        env?.deliver?.invoke()
    }

    suspend fun comments(postId: String): List<JamCommentInfo> {
        val core = store() ?: return emptyList()
        return withContext(Dispatchers.IO) { runCatching { core.listJamComments(postId) }.getOrDefault(emptyList()) }
    }

    /** Writes a comment (or a reply): on someone else's post it waits as pending until the writer's phone publishes it. False when it was refused (blank, over 2,000 characters). */
    suspend fun comment(postId: String, text: String, parent: String?): Boolean {
        val core = store() ?: return false
        val words = text.trim()
        if (words.isEmpty() || words.length > 2000) return false
        val ok = withContext(Dispatchers.IO) { runCatching { core.commentOnJamPost(postId, words, parent) }.isSuccess }
        refreshOne(postId)
        env?.deliver?.invoke()
        return ok
    }

    suspend fun deleteComment(postId: String, commentId: String) {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.deleteJamComment(commentId) } }
        refreshOne(postId)
        env?.deliver?.invoke()
    }

    /** The writer has looked at the comments on a post. */
    suspend fun markSeen(postId: String) {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.markJamPostSeen(postId) } }
        refreshOne(postId)
    }

    suspend fun refreshOne(postId: String) {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.jamPostCounts(postId) }.getOrNull() }?.let { counts[postId] = it }
    }

    // ---- a post's files

    suspend fun attachments(postId: String): List<JamAttachmentInfo> {
        val core = store() ?: return emptyList()
        return withContext(Dispatchers.IO) { runCatching { core.listJamAttachments(postId) }.getOrDefault(emptyList()) }
    }

    /** The description a writer gave a photo, by attachment id (it travels inside the encrypted post). */
    fun altOf(post: JamPostInfo): Map<String, String> = runCatching {
        val list = JSONArray(post.attachmentsJson)
        (0 until list.length()).mapNotNull { i -> list.optJSONObject(i)?.let { it.optString("id") to it.optString("alt") } }.filter { it.first.isNotEmpty() && it.second.isNotEmpty() }.toMap()
    }.getOrDefault(emptyMap())

    /** A file of a post: what this phone has, else downloaded now (no session) and kept. */
    suspend fun attachmentBytes(postId: String, attachmentId: String): ByteArray? {
        val core = store() ?: return null
        val link = env?.transport?.invoke() ?: return withContext(Dispatchers.IO) { null }
        return withContext(Dispatchers.IO) { runCatching { core.jamAttachmentData(link, postId, attachmentId) }.getOrNull() }
    }

    // ---- subscribing

    /** A teacher's live jam page, if they have one (the server learns that this account looked, as it does for a profile). */
    suspend fun pageOf(userId: String): JamPageInfo? {
        val core = store() ?: return null
        val e = env ?: return null
        val link = e.transport() ?: return null
        val token = runCatching { e.token() }.getOrNull() ?: return null
        return withContext(Dispatchers.IO) { runCatching { core.fetchJamPage(link, token, userId) }.getOrNull() }
    }

    /** What my subscription to a jam says: null (none), "requested" (waiting for the writer's phone), "active". */
    fun subscriptionStatus(jamId: String): String? = jams.firstOrNull { it.jamId == jamId && !it.mine }?.status

    suspend fun subscribe(page: JamPageInfo) {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.subscribeToJam(page.jamId, page.writerId) } }
        reload()
        env?.deliver?.invoke()
    }

    suspend fun unsubscribe(jamId: String) {
        val core = store() ?: return
        withContext(Dispatchers.IO) { runCatching { core.unsubscribeFromJam(jamId) } }
        reload()
        env?.deliver?.invoke()
    }

    // ---- writing (LIME-312): my jam, my posts, my subscribers. Everything is sent after it is saved (the core queues it; `deliver` sends it).

    /** My live jam, if I have one (a teacher has one profile jam; bands are a later brief). */
    /**
     * My jams (LIME-315a): **my own space first** (the oldest jam I write: the core's rule `jam_own_space_id`), then my bands, oldest first. A teacher with one jam has a list of one and sees no change.
     */
    val myJams: List<JamInfo> get() {
        val live = jams.filter { it.mine && !it.ended }
        val own = uniffi.lime_core.jamOwnSpaceId(jams.filter { it.mine })
        return live.sortedWith(compareBy<JamInfo>({ if (it.jamId == own) 0 else 1 }, { it.created }, { it.jamId }))
    }

    /** The jam the Your jam page and a new post are about: my choice this session, else my own space. */
    var chosenJamId by mutableStateOf<String?>(null)

    fun mine(): JamInfo? = myJams.let { list -> list.firstOrNull { it.jamId == chosenJamId } ?: list.firstOrNull() }

    /** True for a jam of mine that is a band (not my own space). */
    fun isBand(jam: JamInfo): Boolean = jam.mine && jam.jamId != uniffi.lime_core.jamOwnSpaceId(jams.filter { it.mine })

    /** Makes a band: a second jam of mine (the core's `create_jam`), its members group opened so I can post as it (`org_start`), and its picture when I chose one. The band's id, or null when the core refused. */
    suspend fun createBand(title: String, about: String, topics: List<String>, picture: ByteArray?): String? {
        val created = writing { it.createJam(title.trim(), about.trim(), topics) }.getOrNull() ?: return null
        val jamId = created.removePrefix("jam:")
        writing { it.orgStart(jamId) }
        if (picture != null) setPicture(jamId, picture)
        chosenJamId = jamId
        return jamId
    }

    private suspend fun <T> writing(block: (LimeStore) -> T): Result<T> {
        val core = store() ?: return Result.failure(IllegalStateException("no store"))
        val result = withContext(Dispatchers.IO) { runCatching { block(core) } }
        if (result.isSuccess) { reload(); env?.deliver?.invoke() }
        return result
    }

    /** The server blob that holds a post now (the core's `jam_post_blob_id`), for a report's "Hide post". */
    fun blobIdOf(postId: String): String? = store()?.jamPostBlobId(postId)

    /** How much of what is queued for my jam has gone out (the core's `jam_send_progress`): pending and total, both zero when nothing waits. */
    suspend fun sendProgress(jamId: String): uniffi.lime_core.JamSendProgress? {
        val core = store() ?: return null
        return withContext(Dispatchers.IO) { runCatching { core.jamSendProgress(jamId) }.getOrNull() }
    }

    /** My jam's public picture, if this phone holds one (the core's cache). */
    fun picture(jamId: String): ByteArray? = runCatching { store()?.jamPicture(jamId) }.getOrNull()

    /** Puts a picture (a JPEG of at most 1 MiB) on my jam's page: the core sends it to the server (public, like the title) and keeps a copy. */
    suspend fun setPicture(jamId: String, jpeg: ByteArray): Boolean {
        val core = store() ?: return false
        val e = env ?: return false
        val link = e.transport() ?: return false
        val token = runCatching { e.token() }.getOrNull() ?: return false
        val ok = withContext(Dispatchers.IO) { runCatching { core.setJamPicture(link, token, jamId, jpeg) }.isSuccess }
        if (ok) reload()
        return ok
    }

    suspend fun removePicture(jamId: String): Boolean {
        val core = store() ?: return false
        val e = env ?: return false
        val link = e.transport() ?: return false
        val token = runCatching { e.token() }.getOrNull() ?: return false
        val ok = withContext(Dispatchers.IO) { runCatching { core.removeJamPicture(link, token, jamId) }.isSuccess }
        if (ok) reload()
        return ok
    }

    suspend fun createJam(title: String, about: String, topics: List<String>): Boolean = writing { it.createJam(title.trim(), about.trim(), topics) }.isSuccess
    suspend fun updateJam(jamId: String, title: String, about: String, topics: List<String>): Boolean = writing { it.updateJam(jamId, title.trim(), about.trim(), topics) }.isSuccess
    suspend fun endJam(jamId: String): Boolean = writing { it.endJam(jamId) }.isSuccess

    /** Publishes a post for my subscribers, as iOS does: the free tier (every subscriber is free: lime has no paid tier) with the audience "subscribers" (the audience choices for open posts are not on Android yet). The new post's id, or null when the core refused it (too long, too many files). */
    /** Tests: what would be published (jam id, display_as); true = handled, nothing goes to the core. */
    var publishHook: ((String, String) -> Boolean)? = null

    suspend fun publish(jamId: String, kind: String, title: String, subtitle: String, markdown: String, files: List<uniffi.lime_core.OutgoingAttachment>, displayAs: String = "person"): String? =
        if (publishHook?.invoke(jamId, displayAs) == true) "hooked" else writing { it.publishJamPostWith(jamId, kind, title.trim(), subtitle.trim(), markdown, "free", files, emptyList(), displayAs, uniffi.lime_core.PostOptions("subscribers", null, emptyList())) }.getOrNull()

    suspend fun editPost(post: JamPostInfo, title: String, subtitle: String, markdown: String): Boolean =
        writing { it.editJamPost(post.postId, title.trim(), subtitle.trim(), markdown, emptyList(), "", false, null) }.isSuccess

    suspend fun deletePost(postId: String): Boolean = writing { it.deleteJamPost(postId) }.isSuccess

    suspend fun subscribers(jamId: String): List<uniffi.lime_core.JamSubscriberInfo> {
        val core = store() ?: return emptyList()
        return withContext(Dispatchers.IO) { runCatching { core.listJamSubscribers(jamId) }.getOrDefault(emptyList()) }
    }

    suspend fun removeSubscriber(jamId: String, userId: String): Boolean = writing { it.removeJamSubscriber(jamId, userId) }.isSuccess

    // ---- bookmarks

    fun toggleSaved(postId: String) {
        savedStore.set(postId, postId !in saved)
        saved = savedStore.all()
    }

    companion object {
        /** The first words of a post for a card: the core's `jam_excerpt`. */
        fun excerpt(post: JamPostInfo, limit: Int = 280): String = uniffi.lime_core.jamExcerpt(post, limit.toUInt())
    }
}

/** Bookmarks of jam posts, kept on this phone only. */
interface SavedPosts {
    fun all(): Set<String>
    fun set(postId: String, on: Boolean)

    object None : SavedPosts {
        override fun all(): Set<String> = emptySet()
        override fun set(postId: String, on: Boolean) {}
    }

    class Prefs(private val prefs: android.content.SharedPreferences) : SavedPosts {
        override fun all(): Set<String> = prefs.getStringSet("saved", emptySet()).orEmpty().toSet()
        override fun set(postId: String, on: Boolean) { prefs.edit().putStringSet("saved", all().let { if (on) it + postId else it - postId }).apply() }
    }
}
