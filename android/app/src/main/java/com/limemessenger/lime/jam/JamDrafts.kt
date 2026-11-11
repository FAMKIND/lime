package com.limemessenger.lime.jam

import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import uniffi.lime_core.OutgoingAttachment

/**
 * LIME-312 / iOS `LocalDrafts` (LIME-276): a post or an article that is not published yet, kept on this phone only (never sent): a folder per draft in the app's
 * private files with a small `draft.json` and each photo beside it (with its thumbnail). Opening the writing screen again finds it where it was left. A draft
 * saved before a field existed opens with that field empty.
 */
class JamDrafts(private val folder: File) {
    class Photo(val file: String, val name: String, val mime: String, val width: Int?, val height: Int?, val alt: String)
    class Draft(val id: String, val kind: String, val updated: Long, val title: String, val subtitle: String, val words: String, val photos: List<Photo>) {
        /** What the list shows: the title, or the first line of the words. */
        val headline: String get() = title.trim().ifEmpty { words.lineSequence().firstOrNull { it.isNotBlank() }?.trim().orEmpty() }
    }

    fun list(): List<Draft> = (folder.listFiles() ?: emptyArray()).mapNotNull { read(it.name) }.sortedByDescending { it.updated }

    fun read(id: String): Draft? = runCatching {
        val json = JSONObject(File(File(folder, id), "draft.json").readText())
        val photos = json.optJSONArray("photos") ?: JSONArray()
        Draft(
            id, json.optString("kind", "quick"), json.optLong("updated"), json.optString("title"), json.optString("subtitle"), json.optString("words"),
            (0 until photos.length()).map { i ->
                val p = photos.getJSONObject(i)
                Photo(p.getString("file"), p.optString("name", "Photo.jpg"), p.optString("mime", "image/jpeg"), p.optInt("width").takeIf { it > 0 }, p.optInt("height").takeIf { it > 0 }, p.optString("alt"))
            },
        )
    }.getOrNull()

    /** Keeps the draft with its photos (replacing an earlier save of the same id). False when the phone could not write it. */
    fun save(id: String, kind: String, title: String, subtitle: String, words: String, photos: List<OutgoingAttachment>, now: Long = System.currentTimeMillis()): Boolean = runCatching {
        val dir = File(folder, id)
        dir.deleteRecursively()
        dir.mkdirs()
        val list = JSONArray()
        photos.forEachIndexed { i, photo ->
            val file = "photo-$i"
            File(dir, file).writeBytes(photo.bytes)
            if (photo.thumb.isNotEmpty()) File(dir, "$file.thumb").writeBytes(photo.thumb)
            list.put(JSONObject().put("file", file).put("name", photo.name).put("mime", photo.mime).put("width", photo.width?.toInt() ?: 0).put("height", photo.height?.toInt() ?: 0).put("alt", photo.alt))
        }
        File(dir, "draft.json").writeText(JSONObject().put("kind", kind).put("updated", now).put("title", title).put("subtitle", subtitle).put("words", words).put("photos", list).toString())
        true
    }.getOrDefault(false)

    /** The photos of a draft as what the core publishes. */
    fun photos(draft: Draft): List<OutgoingAttachment> = draft.photos.mapNotNull { p ->
        val dir = File(folder, draft.id)
        val bytes = runCatching { File(dir, p.file).readBytes() }.getOrNull() ?: return@mapNotNull null
        OutgoingAttachment(bytes, p.name, p.mime, p.width?.toUInt(), p.height?.toUInt(), null, runCatching { File(dir, p.file + ".thumb").readBytes() }.getOrDefault(ByteArray(0)), ByteArray(0), p.alt)
    }

    fun delete(id: String) { File(folder, id).deleteRecursively() }

    /** Forgets every draft (Remove everything). */
    fun clear() { folder.deleteRecursively() }
}
