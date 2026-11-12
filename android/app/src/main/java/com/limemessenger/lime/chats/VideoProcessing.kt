package com.limemessenger.lime.chats

import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer
import uniffi.lime_core.OutgoingAttachment

/**
 * Makes the video lime sends (iOS `VideoProcessing`, LIME-314): an MP4 of at most 3 minutes and about 50 MB (a little under the file limit, so chunks and tags fit), with a tiny
 * blurred thumbnail and a sharp poster frame (JPEG, about 480 px, at most 30 KB). **No place and no other personal metadata leaves the phone**: the recording is made with no
 * location, and the file is copied sample by sample into a fresh MP4 (`MediaMuxer`, no re-encoding) that has none of the recorder's tags; if that cannot be done and the file
 * carries a location, it is refused.
 */
object VideoProcessing {
    const val MAX_SECONDS = 180.0
    const val MAX_BYTES = 50 * 1024 * 1024 - 256 * 1024
    const val MAX_POSTER_BYTES = 30 * 1024

    sealed class Problem {
        data class TooLong(val seconds: Int) : Problem()
        object TooLarge : Problem()
        object Unreadable : Problem()
    }

    class Made(val attachment: OutgoingAttachment, val poster: Bitmap?)

    sealed class Result {
        data class Ok(val made: Made) : Result()
        data class Failed(val problem: Problem) : Result()
    }

    /** `file` is the recording; the clean copy is made next to it and the recording itself is left for the caller to delete. */
    fun prepare(file: File, maxBytes: Int = MAX_BYTES): Result {
        val clean = File(file.parentFile, "clean-${file.name}")
        try {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(file.absolutePath)
                val ms = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                if (ms <= 0) return Result.Failed(Problem.Unreadable)
                if (ms / 1000.0 > MAX_SECONDS + 0.5) return Result.Failed(Problem.TooLong((ms / 1000.0).toInt()))
                val hadLocation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_LOCATION) != null
                val source = if (remux(file, clean)) clean else if (hadLocation) return Result.Failed(Problem.Unreadable) else file
                val bytes = source.readBytes()
                if (bytes.size > maxBytes) return Result.Failed(Problem.TooLarge)
                val (w, h, poster) = describe(source)
                val thumb = poster?.let { AttachmentProcessing.thumbnail(it) } ?: ByteArray(0)
                val posterJpeg = poster?.let { posterBytes(it) } ?: ByteArray(0)
                val item = OutgoingAttachment(bytes, "Video.mp4", "video/mp4", w.toUInt(), h.toUInt(), ms.toUInt(), thumb, posterJpeg, "")
                return Result.Ok(Made(item, poster))
            } finally {
                retriever.release()
            }
        } catch (e: Exception) {
            return Result.Failed(Problem.Unreadable)
        } finally {
            clean.delete()
        }
    }

    /** The display size (the rotation applied) and a frame from near the start, upright. */
    private fun describe(file: File): Triple<Int, Int, Bitmap?> {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(file.absolutePath)
            var w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 1280
            var h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 720
            val rotation = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) { val t = w; w = h; h = t }
            val frame = r.getFrameAtTime(500_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: r.getFrameAtTime(0)
            val small = frame?.let { AttachmentProcessing.redraw(it, 480) }
            return Triple(w, h, small)
        } finally {
            r.release()
        }
    }

    private fun posterBytes(bitmap: Bitmap): ByteArray {
        var quality = 80
        while (quality >= 30) {
            val data = AttachmentProcessing.jpeg(bitmap, quality)
            if (data.size <= MAX_POSTER_BYTES) return data
            quality -= 10
        }
        return ByteArray(0)   // a poster that will not fit: the blurred thumbnail stands in
    }

    /** Copies every track's samples into a new MP4 with none of the recorder's tags (no location is ever set). False when anything about it fails. */
    private fun remux(input: File, output: File): Boolean {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        return try {
            extractor.setDataSource(input.absolutePath)
            val retriever = MediaMetadataRetriever().also { it.setDataSource(input.absolutePath) }
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            retriever.release()
            muxer = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val map = HashMap<Int, Int>()
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("video/") || mime.startsWith("audio/")) { map[i] = muxer.addTrack(format); extractor.selectTrack(i) }
            }
            if (map.isEmpty()) return false
            muxer.setOrientationHint(rotation)
            muxer.start()
            val buffer = ByteBuffer.allocate(1 shl 20)
            val info = android.media.MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                info.set(0, size, extractor.sampleTime, if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) android.media.MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                muxer.writeSampleData(map.getValue(extractor.sampleTrackIndex), buffer, info)
                extractor.advance()
            }
            muxer.stop()
            true
        } catch (e: Exception) {
            false
        } finally {
            runCatching { muxer?.release() }
            extractor.release()
        }
    }
}
