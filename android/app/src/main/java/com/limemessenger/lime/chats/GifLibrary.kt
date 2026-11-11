package com.limemessenger.lime.chats

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.provider.Settings
import org.json.JSONObject
import uniffi.lime_core.OutgoingAttachment
import uniffi.lime_core.StickerEntry

// GIFs and stickers (LIME-313), as iOS's `GIF` (GIFSupport.swift) and `StickerPack`: the rules (what may be sent, which sticker a word finds) are the core's
// (`gif_rules.rs`); here are the files and the pictures.

/** A GIF as an attachment: the same bytes (a GIF carries no camera or location data), its first frame as the tiny preview. */
object GifFiles {
    class Refused(val words: String) : Exception(words)

    fun attachment(bytes: ByteArray, name: String = "GIF.gif"): Result<OutgoingAttachment> {
        uniffi.lime_core.gifProblem(bytes)?.let { return Result.failure(Refused(it)) }
        val info = uniffi.lime_core.gifInspect(bytes) ?: return Result.failure(Refused(uniffi.lime_core.gifProblem(bytes).orEmpty()))
        val frame = firstFrame(bytes) ?: return Result.failure(Refused("That isn’t a GIF"))
        return Result.success(OutgoingAttachment(bytes, name, "image/gif", info.width, info.height, null, AttachmentProcessing.thumbnail(frame), ByteArray(0), ""))
    }

    /** The first picture of a GIF, at most `maxEdge` on its long side (a still for grids and for when animations are off). */
    fun firstFrame(bytes: ByteArray, maxEdge: Int = 0): Bitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        if (maxEdge > 0) while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxEdge) sample *= 2
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }.getOrNull()

    /** The system's animations are off (Developer options or Remove animations): a GIF then waits for the person to press Play (WCAG 2.2.2, as iOS's Reduce Motion). */
    fun animationsOff(context: Context): Boolean = runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }.getOrDefault(false)
}

/** lime's own 24 stickers: animated GIFs drawn by lime and shipped in the app (`assets/stickers`, copied from `ios/Lime/Resources/Stickers`). Nothing is downloaded. */
object StickerPack {
    fun entries(context: Context): List<StickerEntry> = runCatching {
        val pack = JSONObject(context.assets.open("stickers/pack.json").bufferedReader().use { it.readText() }).getJSONArray("stickers")
        (0 until pack.length()).map { i ->
            val e = pack.getJSONObject(i)
            val find = e.optJSONArray("find")
            StickerEntry(e.getString("file").removeSuffix(".gif"), e.getString("words"), (0 until (find?.length() ?: 0)).map { find!!.getString(it) })
        }
    }.getOrDefault(emptyList())

    fun bytes(context: Context, file: String): ByteArray? = runCatching { context.assets.open("stickers/$file.gif").use { it.readBytes() } }.getOrNull()

    /** The sticker as an attachment, named so My GIFs does not keep a copy of it. */
    fun attachment(context: Context, entry: StickerEntry): OutgoingAttachment? =
        bytes(context, entry.file)?.let { GifFiles.attachment(it, uniffi.lime_core.stickerNamePrefix() + entry.file + ".gif").getOrNull() }
}
