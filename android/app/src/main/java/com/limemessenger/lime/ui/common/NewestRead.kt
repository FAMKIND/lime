package com.limemessenger.lime.ui.common

/**
 * The newest read wins (LIME-417; the rule LIME-412b added to `ChatsModel.reload`): a read takes a ticket when it STARTS; when it finishes it is applied only if no read that started later has
 * already been applied. A slow read (a poll, a reload begun before a change) therefore can never put back older news over a faster, newer one.
 *
 * Use one per thing that is read and shown, and call [read] from the thread that owns the state (the main thread): the ticket is taken and the result applied there, the fetch can run anywhere.
 */
class NewestRead {
    private var started = 0L
    private var shown = 0L
    private val lock = Any()

    /** Fetches (on whatever thread `fetch` uses) and applies the value with `apply` unless a later read has been applied first. True when it was applied. */
    suspend fun <T> read(fetch: suspend () -> T, apply: (T) -> Unit): Boolean {
        val ticket = synchronized(lock) { ++started }
        val value = fetch()
        val fresh = synchronized(lock) { if (ticket > shown) { shown = ticket; true } else false }
        if (fresh) apply(value)
        return fresh
    }
}
