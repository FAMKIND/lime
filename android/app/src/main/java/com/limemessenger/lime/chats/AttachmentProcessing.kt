package com.limemessenger.lime.chats

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.media.ExifInterface
import android.net.Uri
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import uniffi.lime_core.OutgoingAttachment

// ANDROID DEBT: twin of ios/Lime/Features/Attachments/AttachmentModels.swift `AttachmentProcessing` (photo rules); moves into LimeCore in LIME-133

/**
 * Makes the files lime sends: a photo is at most 2048 px on its long edge, upright, redrawn so EXIF, GPS and camera details are gone, as JPEG
 * (quality 80), plus a tiny preview (at most 2 KB) for the message.
 */
object AttachmentProcessing {
    const val MAX_PHOTO_EDGE = 2048
    const val MAX_FILE_BYTES = 50 * 1024 * 1024
    const val MAX_THUMB_BYTES = 2048
    const val MAX_PER_MESSAGE = 10
    const val MAX_ALT_LENGTH = 250

    /** The size after fitting the long edge into `maxEdge` (never enlarged, never below 1 px). Pure, so the rule is tested without pictures. */
    fun fit(width: Int, height: Int, maxEdge: Int): Pair<Int, Int> {
        val factor = min(1.0, maxEdge.toDouble() / max(width, height))
        return max(1, (width * factor).roundToInt()) to max(1, (height * factor).roundToInt())
    }

    /** The thumbnail ladder: long edge 40 px down to 8 px by 8, at JPEG quality 50, 30, 15, the first that fits 2 KB. */
    val thumbnailEdges = listOf(40, 32, 24, 16, 8)
    val thumbnailQualities = listOf(50, 30, 15)

    /** A photo from the system Photo Picker (no storage permission is needed). Null when it cannot be read or is too large. */
    fun photo(resolver: ContentResolver, uri: Uri, name: String = "Photo.jpg"): OutgoingAttachment? {
        val upright = decodeUpright(resolver, uri) ?: return null
        return photo(upright, name)
    }

    fun photo(upright: Bitmap, name: String = "Photo.jpg"): OutgoingAttachment? {
        val drawn = redraw(upright, MAX_PHOTO_EDGE)
        val jpeg = jpeg(drawn, 80)
        if (jpeg.isEmpty() || jpeg.size > MAX_FILE_BYTES) return null
        return OutgoingAttachment(jpeg, name, "image/jpeg", drawn.width.toUInt(), drawn.height.toUInt(), null, thumbnail(upright), ByteArray(0), "")
    }

    /** At most `maxEdge` pixels on the long edge, on a white ground, no metadata (a fresh bitmap carries none). */
    fun redraw(source: Bitmap, maxEdge: Int): Bitmap {
        val (w, h) = fit(source.width, source.height, maxEdge)
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(source, null, android.graphics.Rect(0, 0, w, h), Paint(Paint.FILTER_BITMAP_FLAG))
        return out
    }

    fun jpeg(bitmap: Bitmap, quality: Int): ByteArray = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()

    /** A very small JPEG (at most 2 KB), shown blurred until the real picture arrives. */
    fun thumbnail(source: Bitmap): ByteArray {
        for (edge in thumbnailEdges) {
            val small = redraw(source, edge)
            for (quality in thumbnailQualities) {
                val data = jpeg(small, quality)
                if (data.size <= MAX_THUMB_BYTES) return data
            }
        }
        return ByteArray(0)
    }

    /** Decodes with a power-of-two sample (so a 12 MP photo is not held whole) and applies the EXIF orientation. */
    fun decodeUpright(resolver: ContentResolver, uri: Uri): Bitmap? = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) null else {
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_PHOTO_EDGE) sample *= 2
            val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
            val orientation = resolver.openInputStream(uri)?.use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) } ?: ExifInterface.ORIENTATION_NORMAL
            decoded?.let { applyOrientation(it, orientation) }
        }
    } catch (e: Exception) {
        null
    }

    fun applyOrientation(bitmap: Bitmap, orientation: Int): Bitmap {
        val m = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> m.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> m.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { m.postRotate(90f); m.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> { m.postRotate(270f); m.postScale(-1f, 1f) }
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
    }

    /** Decodes stored image bytes for display, at most `maxEdge` on the long edge (power-of-two sampled). */
    fun decodeForDisplay(bytes: ByteArray, maxEdge: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxEdge) sample *= 2
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
    }
}
