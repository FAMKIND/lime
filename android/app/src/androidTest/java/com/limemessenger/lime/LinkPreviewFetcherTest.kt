package com.limemessenger.lime

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.limemessenger.lime.chats.LinkPreviewFetcher
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.ServerSocket
import java.net.URL
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * LIME-407: the link-preview fetch against a fake web server on this device (a plain socket; no real internet). The production fetcher is https-only, so the tests give it a
 * connection that goes to the fake server instead; what is checked is the fetcher's own behaviour: the card it makes, its limits (redirects, size, type), the one header it sends,
 * and that it never even connects to a private address (the real rules are used for those cases).
 */
@RunWith(AndroidJUnit4::class)
class LinkPreviewFetcherTest {
    private lateinit var server: ServerSocket
    private val requests = CopyOnWriteArrayList<String>()
    private val connections = AtomicInteger(0)
    private var running = true
    private val png: ByteArray = ByteArrayOutputStream().also { out ->
        Bitmap.createBitmap(1200, 630, Bitmap.Config.ARGB_8888).also { Canvas(it).drawColor(0xFF4CAF50.toInt()) }.compress(Bitmap.CompressFormat.PNG, 100, out)
    }.toByteArray()

    @Before fun start() {
        server = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        Thread {
            while (running) {
                val socket = runCatching { server.accept() }.getOrNull() ?: break
                connections.incrementAndGet()
                Thread { runCatching { serve(socket) } }.start()
            }
        }.start()
    }

    @After fun stop() { running = false; server.close() }

    private fun serve(socket: java.net.Socket) = socket.use { s ->
        val reader = s.getInputStream().bufferedReader()
        val head = StringBuilder()
        while (true) { val line = reader.readLine() ?: break; if (line.isEmpty()) break; head.append(line).append('\n') }
        requests += head.toString()
        val path = head.lineSequence().first().split(" ").getOrElse(1) { "/" }
        val out = s.getOutputStream()
        fun send(code: String, type: String, body: ByteArray, extra: String = "") {
            out.write("HTTP/1.1 $code\r\nContent-Type: $type\r\nContent-Length: ${body.size}\r\nConnection: close\r\n$extra\r\n".toByteArray()); out.write(body); out.flush()
        }
        fun redirect(to: String) = send("302 Found", "text/plain", ByteArray(0), "Location: $to\r\n")
        when (path) {
            "/page" -> send("200 OK", "text/html; charset=utf-8", """<html><head><title>Plain</title><meta property="og:title" content="Fractions &amp; friends"><meta property="og:site_name" content="Example Schools"><meta property="og:image" content="/cover.png"></head><body>x</body></html>""".toByteArray())
            "/cover.png" -> send("200 OK", "image/png", png)
            "/bigpicture.png" -> send("200 OK", "image/png", ByteArray(3 * 1024 * 1024) { 1 })
            "/one" -> redirect("/page")
            "/r1" -> redirect("/r2")
            "/r2" -> redirect("/r3")
            "/r3" -> redirect("/r4")
            "/r4" -> redirect("/page")
            "/json" -> send("200 OK", "application/json", "{}".toByteArray())
            "/huge" -> {
                val head2 = "<html><head><title>Start of a huge page</title></head><body>".toByteArray()
                val body = ByteArray(5 * 1024 * 1024) { 'x'.code.toByte() }
                out.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: ${head2.size + body.size}\r\nConnection: close\r\n\r\n".toByteArray()); out.write(head2); runCatching { out.write(body) }
            }
            "/redirect-private" -> redirect("https://192.168.1.1/admin")
            "/notitle" -> send("200 OK", "text/html", "<html><head></head><body>x</body></html>".toByteArray())
            else -> send("404 Not Found", "text/plain", "no".toByteArray())
        }
    }

    private val opened = AtomicInteger(0)
    /** The fetcher with a connection that goes to the fake server (path and query kept) and policies that let it through. */
    private fun fetcher() = LinkPreviewFetcher(
        open = { url -> opened.incrementAndGet(); URL("http://127.0.0.1:${server.localPort}${url.file}").openConnection() as HttpURLConnection },
        resolve = { listOf("93.184.216.34") }, addressAllowed = { true }, target = { it },
    )
    private fun make(path: String) = runBlocking { fetcher().make("https://example.org$path") }

    @Test fun aPageGivesItsCardWithTheTitleTheSiteAndAScaledJpegPicture() {
        val card = make("/page")
        assertNotNull(card)
        assertEquals("Fractions & friends", card!!.title)
        assertEquals("Example Schools", card.site)
        assertEquals("https://example.org/page", card.url)
        assertTrue("a JPEG", card.image.size > 4 && card.image[0] == 0xFF.toByte() && card.image[1] == 0xD8.toByte())
        assertTrue("at most 190 KB", card.image.size <= 190_000)
        assertEquals("scaled to 640 wide", 640u, card.imageWidth)
        assertEquals(336u, card.imageHeight)
    }

    @Test fun theOnlyThingSentIsAPlainUserAgent() {
        make("/page")
        val first = requests.first().lowercase().lines().filter { it.isNotBlank() }
        val names = first.drop(1).map { it.substringBefore(":") }
        assertTrue("headers: $names", names.all { it in setOf("host", "user-agent", "accept", "accept-encoding", "connection") })
        assertTrue(first.any { it == "user-agent: limemessenger-link-preview" })
        for (never in listOf("cookie", "authorization", "referer", "origin", "x-")) assertFalse("no $never header: $names", names.any { it.startsWith(never) })
    }

    @Test fun oneRedirectIsFollowedAndMoreThanThreeAreNot() {
        run { val c = make("/one"); assertNotNull("requests=${requests.map { it.lines().first() }} connections=${connections.get()} opened=${opened.get()}", c) }
        assertNull("four redirects are one too many", make("/r1"))
    }

    @Test fun onlyAnHtmlPageIsReadAndAPageWithNothingToShowMakesNoCard() {
        assertNull(make("/json"))
        assertNull(make("/missing"))
        assertNull("no title and no site name: the host is the site, so there is a card", make("/notitle")?.takeIf { it.title.isEmpty() })
        assertEquals("the host stands in", "example.org", make("/notitle")!!.site)
    }

    @Test fun aHugePageIsCutAtItsStartAndStillGivesItsCard() {
        val card = make("/huge")
        assertEquals("Start of a huge page", card!!.title)
    }

    @Test fun aPicturePastTwoMegabytesIsLeftOutButTheCardStays() {
        val big = LinkPreviewFetcher(
            open = { url -> URL("http://127.0.0.1:${server.localPort}${url.file.replace("/cover.png", "/bigpicture.png")}").openConnection() as HttpURLConnection },
            resolve = { listOf("93.184.216.34") }, addressAllowed = { true }, target = { it },
        )
        val card = runBlocking { big.make("https://example.org/page") }
        assertNotNull(card)
        assertEquals("a picture that does not arrive is no picture; the title and site do", "Fractions & friends", card!!.title)
    }

    @Test fun anAddressOnThisPhonesOwnNetworkIsNeverConnectedTo() {
        // The real rules: the address itself ...
        val real = LinkPreviewFetcher(open = { opened.incrementAndGet(); it.openConnection() as HttpURLConnection })
        for (address in listOf("http://127.0.0.1:${server.localPort}/page", "https://localhost/page", "https://192.168.1.1/", "https://10.0.0.1/", "https://[::1]/", "https://printer.local/", "ftp://example.org/x")) {
            assertNull(address, runBlocking { real.make(address) })
        }
        assertEquals("not one connection was opened", 0, opened.get())
        assertEquals("and the server saw none", 0, connections.get())
        // ... and a public name that resolves to a private address (DNS pointing inside).
        val rebinding = LinkPreviewFetcher(open = { opened.incrementAndGet(); it.openConnection() as HttpURLConnection }, resolve = { listOf("93.184.216.34", "192.168.1.5") })
        assertNull(runBlocking { rebinding.make("https://example.org/page") })
        assertEquals(0, opened.get())
    }

    @Test fun aRedirectToAPrivateAddressIsRefused() {
        // The first hop is a public name; its Location points at the phone's own network: the fetcher checks it again and stops.
        val hop = AtomicInteger(0)
        val f = LinkPreviewFetcher(
            open = { url -> hop.incrementAndGet(); URL("http://127.0.0.1:${server.localPort}/redirect-private").openConnection() as HttpURLConnection },
            resolve = { listOf("93.184.216.34") },
        )
        assertNull(runBlocking { f.make("https://example.org/start") })
        assertEquals("one request went out (the first hop) and no second", 1, hop.get())
    }
}
