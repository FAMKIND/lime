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
import uniffi.lime_core.JamInfo
import uniffi.lime_core.JamPostInfo
import uniffi.lime_core.LimeStore

// ANDROID DEBT: twin of the read parts of ios/Lime/App/ConversationStore+Jam.swift (jamFeed, byline, teacherName, jamTitle) and
// ios/Lime/Features/Jam/JamPage.swift (JamDates); moves into LimeCore in LIME-133

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

/**
 * The jam tab, read only: the posts of every jam I follow (an accepted subscription) and my own, newest first. The core stores the posts as
 * they arrive in the mailbox; this only reads them. Writing, comments, likes, saving, hiding and discovery are not built.
 */
class JamModel(
    private val store: () -> LimeStore?,
    private val nameOf: (String) -> String?,
    /** Where the jams and posts come from (the core's store; tests give their own). */
    private val source: (suspend () -> Pair<List<JamInfo>, List<JamPostInfo>>)? = null,
) {
    var posts by mutableStateOf<List<JamPostInfo>>(emptyList())
        private set
    var jams by mutableStateOf<List<JamInfo>>(emptyList())
        private set
    var isLoaded by mutableStateOf(false)
        private set

    suspend fun reload() {
        try {
            if (source != null) {
                val (found, all) = source.invoke()
                jams = found
                posts = feed(all, found)
            } else {
                val core = store() ?: return
                val (mine, followed, all) = withContext(Dispatchers.IO) {
                    val mine = core.listMyJams()
                    val followed = core.listJamSubscriptions()
                    val live = (followed.filter { it.status == "active" } + mine).map { it.jamId }.toSet()
                    Triple(mine, followed, live.flatMap { core.listJamPosts(it) })
                }
                jams = mine + followed
                posts = feed(all, jams)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Keep what is shown.
        }
        isLoaded = true
    }

    /** The jam's title, or "jam" when it is not known. */
    fun jamTitle(jamId: String): String = jams.firstOrNull { it.jamId == jamId }?.title?.ifEmpty { null } ?: "jam"

    /** The name shown for an author: the jam's title for a post shown as the jam, else the teacher's name. */
    fun authorName(post: JamPostInfo): String = if (post.displayAs == "jam") jamTitle(post.jamId) else teacherName(post.author)

    fun teacherName(userId: String): String = nameOf(userId)?.ifEmpty { null } ?: "A teacher"

    fun byline(post: JamPostInfo): String? = byline(post.coauthors.map { teacherName(it) })

    companion object {
        /** Newest first, only posts that are ready to read (a post still arriving or removed has nothing to show). */
        fun feed(all: List<JamPostInfo>, jams: List<JamInfo>): List<JamPostInfo> {
            val live = jams.filter { it.mine || it.status == "active" }.map { it.jamId }.toSet()
            return all.filter { it.jamId in live && it.state == "ready" }.distinctBy { it.postId }.sortedByDescending { it.created }
        }

        /** "with Jean Chung and Lee Wong" for the co-authors who accepted, or null. */
        fun byline(coauthorNames: List<String>): String? {
            if (coauthorNames.isEmpty()) return null
            val list = if (coauthorNames.size < 2) coauthorNames.first() else "${coauthorNames.dropLast(1).joinToString(", ")} and ${coauthorNames.last()}"
            return "with $list"
        }

        /** The first words of a post for a card: a quick post's text, an article's subtitle or opening, cut at a word. */
        fun excerpt(post: JamPostInfo, limit: Int = 280): String {
            val body = post.plain.replace("\n", " ").trim()
            val source = if (post.kind == "article" && post.subtitle.isNotBlank()) post.subtitle.trim() else body
            if (source.length <= limit) return source
            val cut = source.take(limit)
            return cut.substring(0, cut.lastIndexOf(' ').takeIf { it > limit / 2 } ?: limit).trimEnd() + "…"
        }
    }
}
