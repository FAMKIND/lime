package com.limemessenger.lime.storage

import com.limemessenger.lime.keys.KeyWrapper
import com.limemessenger.lime.keys.SecureBlobStore
import java.io.File
import java.time.Instant
import uniffi.lime_core.LimeStore
import uniffi.lime_core.StoreException

/**
 * Where the encrypted database lives and how it is opened (the twin of iOS's `StorageBootstrap`; the core's migrations run on open).
 * Blocking: call it off the main thread.
 *
 * The database is never backed up (a restored phone would get the file but not the this-device-only key). If the store cannot be
 * opened, the old file is moved aside and a fresh store is created; history comes back through lime's own recovery and device linking.
 * Space layout as iOS (LIME-268): one folder and one key per account, `accounts/<user id>`; `legacy` is the pre-accounts folder.
 */
class StorageBootstrap(private val root: File, private val keys: SecureBlobStore) {

    /** A folder for the database files and the name of the key that opens it. */
    data class Location(val directory: File, val keyName: String) {
        val database: File get() = File(directory, "lime.db")
    }

    class Opened(val store: LimeStore, val path: String, val startedFresh: Boolean)

    val legacy = Location(File(root, "lime"), "storage-key")

    fun space(userId: String): Location =
        Location(File(File(File(root, "lime"), "accounts"), userId), "storage-key.$userId")

    fun open(location: Location, now: Instant = Instant.now()): Opened {
        location.directory.mkdirs()
        var startedFresh = false
        val existing = keys.read(location.keyName)?.takeIf { it.size == KEY_BYTES }
        val store: LimeStore
        if (existing != null) {
            store = try {
                LimeStore.open(location.database.path, existing)
            } catch (e: StoreException) {
                if (!isUnopenable(e)) throw e
                startedFresh = location.database.exists()
                startFresh(location, startedFresh, now)
            }
        } else {
            // No key. With no database either this is a first launch, which is not an error.
            startedFresh = location.database.exists()
            store = startFresh(location, startedFresh, now)
        }
        return Opened(store, location.database.path, startedFresh)
    }

    /** Errors that mean "this file cannot be used with this key". Anything else is a bug and is not hidden by starting fresh. */
    private fun isUnopenable(e: StoreException): Boolean =
        e is StoreException.WrongKeyOrNotADatabase || e is StoreException.Migration || e is StoreException.Database

    private fun startFresh(location: Location, moveAside: Boolean, now: Instant): LimeStore {
        if (moveAside) moveDatabaseAside(location, now)
        keys.delete(location.keyName)
        val key = KeyWrapper.randomBytes(KEY_BYTES)
        keys.write(location.keyName, key)
        return LimeStore.open(location.database.path, key)
    }

    private fun moveDatabaseAside(location: Location, now: Instant) {
        val stamp = now.toString().replace(':', '-')
        var target = File(location.directory, "lime-$stamp.unreadable.db")
        var counter = 1
        while (target.exists()) target = File(location.directory, "lime-$stamp-$counter.unreadable.db").also { counter++ }
        location.database.renameTo(target)
        for (suffix in SIBLINGS) File(location.database.path + suffix).delete()
        prune(location)
    }

    /** Keeps the newest [KEPT_UNREADABLE] (the timestamps sort by name). */
    fun prune(location: Location) {
        unreadableFileNames(location).sortedDescending().drop(KEPT_UNREADABLE).forEach { File(location.directory, it).delete() }
    }

    fun unreadableFileNames(location: Location): List<String> =
        location.directory.list().orEmpty().filter { it.startsWith("lime-") && it.endsWith(".unreadable.db") }.sorted()

    /** Deletes this device's database, the files moved aside, and the key (Remove everything from this device; deleting the account). */
    fun wipe(location: Location) {
        location.directory.listFiles().orEmpty().filter { it.name.startsWith("lime") }.forEach { it.delete() }
        keys.delete(location.keyName)
    }

    /** True when the file cannot be opened with a key that is not ours (the app's own proof that the data on disk is encrypted). */
    fun rejectsWrongKey(path: String): Boolean = try {
        LimeStore.open(path, ByteArray(KEY_BYTES)).close()
        false
    } catch (e: Exception) {
        true
    }

    companion object {
        const val KEY_BYTES = 32
        const val KEPT_UNREADABLE = 2
        private val SIBLINGS = listOf("-wal", "-shm", "-journal")
    }
}
