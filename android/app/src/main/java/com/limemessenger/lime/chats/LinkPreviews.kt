package com.limemessenger.lime.chats

import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
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
 *
 * **The address is checked once and then used (LIME-408).** The name is resolved ONCE; every address it gave must be public; the connection then goes to that checked address itself
 * (a plain [Socket] to the pinned [InetAddress], TLS on top with the host name kept for SNI and for the certificate check), so there is no second lookup an attacker's DNS could answer
 * differently, and the connected peer is checked again before a single byte is sent. The HTTP exchange is written here (a GET, `Connection: close`) because `HttpURLConnection` resolves
 * the name again by itself and cannot be pinned. The hooks are for the tests (a fake server on this device); the defaults enforce every rule.
 */
open class LinkPreviewFetcher(
    private val connect: ((host: String, ip: String, port: Int, timeoutMs: Int) -> Socket)? = null,
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
            // Resolve ONCE. Every address the name gave must be public (a page cannot send this phone to its owner's own network by DNS); the first one is the one connected to.
            val addresses = resolve(url.host)
            if (addresses.isEmpty() || !addresses.all(addressAllowed)) return null
            val port = if (url.port > 0) url.port else 443
            val socket = (connect ?: ::pinnedTls).invoke(url.host, addresses.first(), port, timeoutMs)
            try {
                socket.soTimeout = timeoutMs
                val deadline = System.nanoTime() + timeoutMs * 1_000_000L   // the whole exchange, not each read: a server that drips one byte at a time cannot hold this open
                val hostHeader = if (url.port > 0 && url.port != 443) "${url.host}:${url.port}" else url.host
                val path = (url.file.ifEmpty { "/" }).let { if (it.startsWith("/")) it else "/$it" }
                socket.getOutputStream().apply {
                    write("GET $path HTTP/1.1\r\nHost: $hostHeader\r\nUser-Agent: $USER_AGENT\r\nAccept: */*\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n".toByteArray(Charsets.ISO_8859_1))
                    flush()
                }
                val input = java.io.BufferedInputStream(DeadlineInput(socket, deadline), 8 * 1024)
                val code = readStatus(input) ?: return null
                val headers = readHeaders(input) ?: return null
                if (code in 300..399) {
                    val location = headers["location"] ?: return null
                    current = target(URL(url, location).toString()) ?: return null
                    return@repeat
                }
                if (code != 200) return null
                val encoding = headers["content-encoding"]?.lowercase()
                if (encoding != null && encoding != "identity") return null
                val type = headers["content-type"]?.lowercase().orEmpty()
                if (!type.startsWith(typePrefix)) return null
                val declared = headers["content-length"]?.trim()?.toLongOrNull() ?: -1L
                if (typePrefix != "text/html" && declared > maxBytes) return null
                val body = if (headers["transfer-encoding"]?.lowercase()?.contains("chunked") == true) ChunkedInput(input) else input
                return (readLimited(body, maxBytes) ?: return null) to current
            } finally {
                runCatching { socket.close() }
            }
        }
        return null   // more redirects than allowed
    }

    /** A connection to exactly `ip` (a literal: no lookup happens), with TLS on top for `host` (SNI and the certificate are checked against the NAME). The peer is checked again once connected. */
    private fun pinnedTls(host: String, ip: String, port: Int, timeoutMs: Int): Socket {
        val literal = InetAddress.getByName(ip)   // an address literal: parsed, never resolved
        val pinned = InetAddress.getByAddress(host, literal.address)
        val raw = Socket()
        try {
            raw.connect(InetSocketAddress(pinned, port), timeoutMs)
            raw.soTimeout = timeoutMs
            if (!addressAllowed(raw.inetAddress.hostAddress.orEmpty())) throw java.io.IOException("peer not public")
            val tls = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(raw, host, port, true) as SSLSocket
            tls.startHandshake()
            if (!HttpsURLConnection.getDefaultHostnameVerifier().verify(host, tls.session)) { tls.close(); throw java.io.IOException("certificate is not for this name") }
            return tls
        } catch (e: Throwable) {
            runCatching { raw.close() }
            throw e
        }
    }

    private fun readLine(input: InputStream): String? {
        val sb = StringBuilder()
        while (sb.length < 16 * 1024) {
            val c = input.read()
            if (c < 0) return if (sb.isEmpty()) null else sb.toString()
            if (c == '\n'.code) return sb.toString().trimEnd('\r')
            sb.append(c.toChar())
        }
        return null
    }

    private fun readStatus(input: InputStream): Int? {
        val line = readLine(input) ?: return null
        val parts = line.split(' ')
        return if (parts.size >= 2 && parts[0].startsWith("HTTP/1.")) parts[1].toIntOrNull() else null
    }

    private fun readHeaders(input: InputStream): Map<String, String>? {
        val map = HashMap<String, String>()
        var size = 0
        repeat(100) {
            val line = readLine(input) ?: return null
            size += line.length + 2
            if (size > MAX_HEADER_BYTES) return null   // a header section past 16 KB is not a web page
            if (line.isEmpty()) return map
            val i = line.indexOf(':')
            if (i > 0) map.putIfAbsent(line.substring(0, i).trim().lowercase(), line.substring(i + 1).trim())
        }
        return null
    }

    /** The socket's input, where every read may take only what is left of the whole exchange's time (a read that would pass the deadline times out). */
    private class DeadlineInput(private val socket: Socket, private val deadline: Long) : InputStream() {
        private val inner = socket.getInputStream()
        private fun arm() {
            val left = (deadline - System.nanoTime()) / 1_000_000L
            if (left <= 0) throw java.net.SocketTimeoutException("the exchange took too long")
            socket.soTimeout = minOf(left, Int.MAX_VALUE.toLong()).toInt()
        }
        override fun read(): Int { arm(); return inner.read() }
        override fun read(b: ByteArray, off: Int, len: Int): Int { arm(); return inner.read(b, off, len) }
        override fun close() = inner.close()
    }

    /** The body of a `Transfer-Encoding: chunked` reply, de-chunked (extensions and trailers ignored). */
    private inner class ChunkedInput(private val input: InputStream) : InputStream() {
        private var left = 0L
        private var done = false
        override fun read(): Int { val one = ByteArray(1); return if (read(one, 0, 1) < 0) -1 else one[0].toInt() and 0xff }
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            if (done) return -1
            if (left == 0L) {
                val size = (readLine(input) ?: return -1).substringBefore(';').trim().toLongOrNull(16)
                if (size == null || size < 0) throw java.io.IOException("malformed chunk size")   // not a web server's reply: no card (LIME-410: it used to end quietly and give the host as a title)
                if (size == 0L) { done = true; return -1 }
                left = size
            }
            val n = input.read(b, off, minOf(len.toLong(), left).toInt())
            if (n < 0) { done = true; return -1 }
            left -= n
            if (left == 0L) readLine(input)   // the CRLF after a chunk
            return n
        }
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

    private companion object { const val USER_AGENT = "limeMessenger-link-preview"; const val MAX_HEADER_BYTES = 16 * 1024 }
}
