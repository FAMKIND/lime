package com.limemessenger.lime.chats

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.limemessenger.lime.auth.ConnectionProblem
import com.limemessenger.lime.auth.IdentifierKind
import com.limemessenger.lime.auth.OnboardingModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.lime_core.ConversationSummary
import uniffi.lime_core.FoundUser
import uniffi.lime_core.findUser

// ANDROID DEBT: twin of the lookup parts of ios/Lime/Features/Messages/NewMessageSheet.swift (TeacherLookup, LookupKind, KnownTeachers); moves into LimeCore in LIME-133

/** A teacher's lookup, as the screen says it: nothing partial, only an exact username or email. */
class TeacherLookup {
    sealed class State {
        object Idle : State()
        object Searching : State()
        data class Found(val person: FoundUser) : State()
        object Nobody : State()
        data class Problem(val text: String) : State()

        /** What is said when the state changes (the lookup appears with no focus move): nothing for idle (LIME-130-3a). */
        val spokenWords: String? get() = when (this) {
            Idle -> null
            Searching -> "Searching"
            is Found -> "1 found"
            Nobody -> "No teacher found"
            is Problem -> text
        }
    }

    var state by mutableStateOf<State>(State.Idle)
        private set
    private var generation = 0

    fun reset() { generation++; state = State.Idle }

    suspend fun run(text: String, find: suspend (String) -> FoundUser?) {
        generation++
        val mine = generation
        state = State.Searching
        try {
            val person = find(query(text))
            if (mine != generation) return
            state = person?.let { State.Found(it) } ?: State.Nobody
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (mine != generation) return
            state = State.Problem(ConnectionProblem.from(e).message)
        }
    }

    companion object {
        /** True when `text` is a complete username or email, so the search can run. */
        fun accepts(text: String): Boolean = OnboardingModel.classify(text).let { it is IdentifierKind.Username || it is IdentifierKind.Email }

        /** The text sent to the server: a username without a leading "@". */
        fun query(text: String): String {
            val trimmed = text.trim()
            return if (OnboardingModel.classify(trimmed) is IdentifierKind.Email) trimmed else trimmed.trim('@')
        }
    }
}

/** A teacher I already message, for the A–Z list of New message. */
data class KnownTeacher(val id: String, val name: String, val tone: Int, val initials: String)

object KnownTeachers {
    /** The people of my one-to-one chats (not groups, not requests), one each. */
    fun from(conversations: List<ConversationSummary>): List<KnownTeacher> =
        conversations.filter { !it.isGroup && !it.isRequest }.mapNotNull { c -> c.members.firstOrNull()?.let { KnownTeacher(it.id, it.name, it.tone.toInt(), it.initials) } }
            .distinctBy { it.id }

    /** The index letter of a name: its first letter, accents and case ignored; "#" for anything else. */
    /** Accents and case ignored, for the index letter and the sort ("Ángel" sorts as "angel"). */
    fun fold(name: String): String = java.text.Normalizer.normalize(name.trim(), java.text.Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase()

    fun letter(name: String): String {
        val folded = fold(name)
        val first = folded.firstOrNull()?.uppercaseChar() ?: return "#"
        return if (first in 'A'..'Z') first.toString() else "#"
    }

    /** The A–Z sections (with "#" last), names sorted inside each, narrowed to the names the filter matches (every typed word starts a word of the name). */
    fun sections(teachers: List<KnownTeacher>, filter: String = ""): List<Pair<String, List<KnownTeacher>>> {
        val words = filter.trim().lowercase().split(" ").filter { it.isNotEmpty() }
        val shown = if (words.isEmpty()) teachers else teachers.filter { t -> val name = t.name.lowercase().split(" "); words.all { w -> name.any { it.startsWith(w) } } }
        val grouped = shown.groupBy { letter(it.name) }
        val order = grouped.keys.filter { it != "#" }.sorted() + (if (grouped.containsKey("#")) listOf("#") else emptyList())
        return order.map { key -> key to grouped.getValue(key).sortedBy { fold(it.name) } }
    }
}

/** What New message does with the server: find one exact person, start a chat with them. */
suspend fun ChatsModel.find(query: String): FoundUser? {
    val link = transportOrNull() ?: throw uniffi.lime_core.StoreException.Network()
    val bearer = bearer()
    return withContext(Dispatchers.IO) { findUser(link, bearer, query) }
}

/** Starts (or finds) the one-to-one chat with a person I chose, then gives them my delivery key by delivering (as iOS `startChat`). Returns the chat's id. */
suspend fun ChatsModel.startChat(userId: String, displayName: String): String? {
    val core = core() ?: return null
    val id = withContext(Dispatchers.IO) { runCatching { core.startDm(userId, displayName) }.getOrNull() } ?: return null
    reload()
    deliverNow()
    return id
}

/** A person's public profile from the server (null when they have none yet). */
suspend fun ChatsModel.profileOf(userId: String): uniffi.lime_core.PublicProfile? {
    val core = core() ?: return null
    val link = transportOrNull() ?: return null
    val bearer = bearer()
    return withContext(Dispatchers.IO) { core.fetchProfile(link, bearer, userId) }
}
