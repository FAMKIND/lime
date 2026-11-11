package com.limemessenger.lime.chats

import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import uniffi.lime_core.OutgoingPreview

/** Settings → Privacy → "Generate link previews" (iOS `LinkPreviewSetting`, `lime.linkPreviews`): **on by default**, kept on this phone only. Off: no page is fetched and no card is made. */
class LinkPreviewPrefs(private val prefs: SharedPreferences) {
    var enabled by mutableStateOf(prefs.getBoolean(KEY, true))
        private set

    fun change(value: Boolean) { enabled = value; prefs.edit().putBoolean(KEY, value).apply() }

    private companion object { const val KEY = "linkPreviews" }
}

/**
 * Builds a link card on this phone (LIME-407; iOS `LinkPreviewMaker.make`): fetches the page and its picture **from here, over https only**, reads its title, site and picture with the
 * core's rules (`link_preview_rules.rs`), and returns what `queue_text_with_preview` takes: the card travels sealed inside the message. Plain `HttpsURLConnection`, no library.
 *
 * What it will not do: connect to anything that is not a public address (the core's [uniffi.lime_core.linkPreviewTarget] for the address and [uniffi.lime_core.linkPreviewAddressAllowed]
 * for **every address the name resolves to**, at every redirect); follow more than 3 redirects; read more than 512 KB of a page or 2 MB of a picture; take anything but `text/html` for the
 * page and an image type for the picture; send anything but a plain User-Agent (no cookies, no referrer, no account, no token); log an address (nothing here logs at all).
 * The five hooks are for the tests (a fake server on this device); the defaults enforce every rule.
 */
open class LinkPreviewFetcher(
    private val open: (URL) -> HttpURLConnection = { it.openConnection() as HttpURLConnection },
    private val resolve: (String) -> List<String> = { host -> InetAddress.getAllByName(host).mapNotNull { it.hostAddress } },
    private val addressAllowed: (String) -> Boolean = { uniffi.lime_core.linkPreviewAddressAllowed(it) },
    private val target: (String) -> String? = { uniffi.lime_core.linkPreviewTarget(it) },
) {
    private val limits = uniffi.lime_core.linkPreviewLimits()

    /** The card for `address`, or null (no address to fetch, nothing came, or no title and no site). Runs on the IO dispatcher and stops when cancelled. */
    open suspend fun make(address: String): OutgoingPreview? = withContext(Dispatchers.IO) {
        try {
            val first = target(address) ?: return@withContext null
            val (html, finalUrl) = fetch(first, limits.pageTimeoutMs.toInt(), limits.maxPageBytes.toInt(), "text/html") ?: return@withContext null
            val page = uniffi.lime_core.linkPreviewParsePage(String(html, charsetOf(html)), finalUrl) ?: return@withContext null
            var jpeg = ByteArray(0)
            var width: UInt? = null
            var height: UInt? = null
            page.imageUrl?.let { picture ->
                ensureActive()
                val bytes = fetch(picture, limits.pictureTimeoutMs.toInt(), limits.maxPictureBytes.toInt(), "image/")?.first
                val scaled = bytes?.let { scaleToJpeg(it, limits.pictureWidth.toInt(), limits.maxJpegBytes.toInt()) }
                if (scaled != null) { jpeg = scaled.bytes; width = scaled.width.toUInt(); height = scaled.height.toUInt() }
            }
            OutgoingPreview(first, page.title, page.site, jpeg, width, height)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            null   // (no message, no address: nothing about the page is kept anywhere)
        }
    }

    /** Fetches `start` (and the redirects it makes, each checked again) and returns the body (at most `maxBytes`: a longer one is cut, a picture that is longer is refused) and the final address. */
    private suspend fun fetch(start: String, timeoutMs: Int, maxBytes: Int, typePrefix: String): Pair<ByteArray, String>? {
        var current = start
        repeat(limits.maxRedirects.toInt() + 1) {
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            val url = URL(current)
            // Every address the name resolves to must be public (a page cannot send this phone to its owner's own network by DNS).
            val addresses = resolve(url.host)
            if (addresses.isEmpty() || !addresses.all(addressAllowed)) return null
            val connection = open(url)
            try {
                connection.instanceFollowRedirects = false
                connection.useCaches = false
                connection.connectTimeout = timeoutMs
                connection.readTimeout = timeoutMs
                connection.requestMethod = "GET"
                connection.setRequestProperty("User-Agent", USER_AGENT)
                val code = connection.responseCode
                if (code in 300..399) {
                    val location = connection.getHeaderField("Location") ?: return null
                    current = target(URL(url, location).toString()) ?: return null
                    return@repeat
                }
                if (code != 200) return null
                val type = connection.contentType?.lowercase().orEmpty()
                if (!type.startsWith(typePrefix)) return null
                val declared = connection.contentLengthLong
                if (typePrefix != "text/html" && declared > maxBytes) return null
                val body = readLimited(connection.inputStream, maxBytes) ?: return null
                return body to current
            } finally {
                connection.disconnect()
            }
        }
        return null   // more redirects than allowed
    }

    /** At most `max` bytes; for a page that is the start of it, for a picture (which must be whole) null when it is longer. */
    private fun readLimited(input: InputStream, max: Int): ByteArray? = input.use { stream ->
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        while (out.size() < max) {
            val n = stream.read(buffer, 0, minOf(buffer.size, max - out.size()))
            if (n < 0) break
            out.write(buffer, 0, n)
        }
        out.toByteArray()
    }

    private fun charsetOf(html: ByteArray): java.nio.charset.Charset {
        val head = String(html, 0, minOf(html.size, 2_048), Charsets.ISO_8859_1).lowercase()
        val name = Regex("charset\\s*=\\s*[\"']?([a-z0-9_-]+)").find(head)?.groupValues?.get(1)
        return runCatching { java.nio.charset.Charset.forName(name ?: "utf-8") }.getOrDefault(Charsets.UTF_8)
    }

    class Scaled(val bytes: ByteArray, val width: Int, val height: Int)

    /** The picture as a JPEG at most `maxWidth` wide and `maxJpeg` bytes (the quality steps down as iOS's does); null when it is not a picture or will not fit. */
    private fun scaleToJpeg(bytes: ByteArray, maxWidth: Int, maxJpeg: Int): Scaled? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= maxWidth) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val bitmap = if (decoded.width > maxWidth) Bitmap.createScaledBitmap(decoded, maxWidth, (decoded.height.toFloat() * maxWidth / decoded.width).toInt().coerceAtLeast(1), true) else decoded
        var quality = 75
        while (quality > 20) {
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
            if (out.size() <= maxJpeg) return Scaled(out.toByteArray(), bitmap.width, bitmap.height)
            quality -= 15
        }
        return null
    }

    private companion object { const val USER_AGENT = "limeMessenger-link-preview" }
}
