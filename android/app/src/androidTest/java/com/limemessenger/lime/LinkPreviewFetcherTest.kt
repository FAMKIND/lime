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
    private val bigWritten = AtomicInteger(0)
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
            "/loop" -> redirect("https://example.org/loop")
            "/chunked" -> {
                val html = """<html><head><meta property="og:title" content="Chunked title"><meta property="og:site_name" content="Chunky"></head><body>x</body></html>"""
                out.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n".toByteArray())
                val bytes = html.toByteArray()
                var at = 0
                while (at < bytes.size) { val n = minOf(17, bytes.size - at); out.write("${Integer.toHexString(n)};ext=1\r\n".toByteArray()); out.write(bytes, at, n); out.write("\r\n".toByteArray()); at += n }
                out.write("0\r\n\r\n".toByteArray()); out.flush()
            }
            "/chunked-big" -> {
                // The first chunk holds the head; the second claims 2 GB and sends 1 MB: the reader stops at its 512 KB cap and still has the card.
                val head2 = """<html><head><meta property="og:title" content="Cut at the cap"><meta property="og:site_name" content="Big"></head><body>""".toByteArray()
                out.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n".toByteArray())
                out.write("${Integer.toHexString(head2.size)}\r\n".toByteArray()); out.write(head2); out.write("\r\n7fffffff\r\n".toByteArray())
                val piece = ByteArray(64 * 1024) { 'x'.code.toByte() }
                bigWritten.set(0)
                runCatching { repeat(128) { out.write(piece); out.flush(); bigWritten.addAndGet(piece.size); Thread.sleep(20) } }   // 8 MB offered over ~2.5 s; a reader with a cap closes after ~0.5 MB
            }
            "/chunked-bad" -> { out.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\nzzzz\r\n<html>".toByteArray()); out.flush(); Thread.sleep(20_000) }
            "/silent" -> Thread.sleep(20_000)
            "/drip" -> {
                out.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n".toByteArray()); out.flush()
                repeat(40) { out.write('x'.code); out.flush(); Thread.sleep(1_000) }
            }
            "/bigheader" -> { out.write(("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nX-Big: " + "a".repeat(20 * 1024) + "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n").toByteArray()); out.flush() }
            "/manyheaders" -> { out.write(("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n" + (1..30).joinToString("") { "X-$it: " + "b".repeat(700) + "\r\n" } + "Content-Length: 0\r\nConnection: close\r\n\r\n").toByteArray()); out.flush() }
            "/notitle" -> send("200 OK", "text/html", "<html><head></head><body>x</body></html>".toByteArray())
            else -> send("404 Not Found", "text/plain", "no".toByteArray())
        }
    }

    private val opened = AtomicInteger(0)
    private val resolved = AtomicInteger(0)
    private val pinnedTo = CopyOnWriteArrayList<String>()
    /** The fetcher with a connection that goes to the fake server (path and query kept) and policies that let it through. */
    private fun fetcher() = LinkPreviewFetcher(
        connect = { _, ip, _, _ -> opened.incrementAndGet(); pinnedTo += ip; java.net.Socket("127.0.0.1", server.localPort) },
        resolve = { resolved.incrementAndGet(); listOf("93.184.216.34") }, addressAllowed = { true }, target = { it },
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
            connect = { _, _, _, _ -> java.net.Socket("127.0.0.1", server.localPort) },
            resolve = { listOf("93.184.216.34") }, addressAllowed = { true }, target = { it.replace("/cover.png", "/bigpicture.png") },
        )
        val card = runBlocking { big.make("https://example.org/page") }
        assertNotNull(card)
        assertEquals("a picture that does not arrive is no picture; the title and site do", "Fractions & friends", card!!.title)
    }

    @Test fun anAddressOnThisPhonesOwnNetworkIsNeverConnectedTo() {
        // The real rules: the address itself ...
        val real = LinkPreviewFetcher(connect = { _, _, _, _ -> opened.incrementAndGet(); java.net.Socket("127.0.0.1", server.localPort) })
        for (address in listOf("http://127.0.0.1:${server.localPort}/page", "https://localhost/page", "https://192.168.1.1/", "https://10.0.0.1/", "https://[::1]/", "https://printer.local/", "ftp://example.org/x")) {
            assertNull(address, runBlocking { real.make(address) })
        }
        assertEquals("not one connection was opened", 0, opened.get())
        assertEquals("and the server saw none", 0, connections.get())
        // ... and a public name that resolves to a private address (DNS pointing inside).
        val rebinding = LinkPreviewFetcher(connect = { _, _, _, _ -> opened.incrementAndGet(); java.net.Socket("127.0.0.1", server.localPort) }, resolve = { listOf("93.184.216.34", "192.168.1.5") })
        assertNull(runBlocking { rebinding.make("https://example.org/page") })
        assertEquals(0, opened.get())
    }

    @Test fun aRedirectToAPrivateAddressIsRefused() {
        // The first hop is a public name; its Location points at the phone's own network: the fetcher checks it again and stops.
        val hop = AtomicInteger(0)
        val f = LinkPreviewFetcher(
            connect = { _, _, _, _ -> hop.incrementAndGet(); java.net.Socket("127.0.0.1", server.localPort) },
            resolve = { listOf("93.184.216.34") }, target = { if (it.contains("/start")) "https://example.org/redirect-private" else uniffi.lime_core.linkPreviewTarget(it) },
        )
        assertNull(runBlocking { f.make("https://example.org/start") })
        assertEquals("one request went out (the first hop) and no second", 1, hop.get())
    }

    // ---- LIME-408: the address is checked once and then used

    @Test fun theNameIsResolvedOnceAndTheConnectionGoesToTheCheckedAddress() {
        val card = make("/page")   // a page with a picture: two fetches, so two lookups, one each
        assertNotNull(card)
        assertEquals("one lookup per fetch (page, picture), never a second one inside a fetch", 2, resolved.get())
        assertEquals("every connection was told the checked address itself", listOf("93.184.216.34", "93.184.216.34"), pinnedTo.toList())
    }

    @Test fun aNameThatAnswersPublicFirstAndLoopbackSecondFetchesNothing() {
        val sneaky = LinkPreviewFetcher(connect = { _, _, _, _ -> opened.incrementAndGet(); java.net.Socket("127.0.0.1", server.localPort) }, resolve = { listOf("93.184.216.34", "127.0.0.1") })
        assertNull(runBlocking { sneaky.make("https://example.org/page") })
        assertEquals("no connection at all", 0, opened.get())
        assertEquals(0, connections.get())
        // The other order, and a name whose answer changes between two lookups (the first public, the second inside): only the first is ever used, so there is nothing to change.
        val answers = java.util.concurrent.atomic.AtomicInteger(0)
        val flipping = LinkPreviewFetcher(connect = { _, ip, _, _ -> pinnedTo += "flip:$ip"; java.net.Socket("127.0.0.1", server.localPort) },
            resolve = { if (answers.getAndIncrement() == 0) listOf("93.184.216.34") else listOf("127.0.0.1") }, addressAllowed = { it != "127.0.0.1" }, target = { it })
        assertNotNull(runBlocking { flipping.make("https://example.org/page") })
        assertEquals("the page's connection used the first (checked) answer", "flip:93.184.216.34", pinnedTo.first { it.startsWith("flip:") })
    }

    @Test fun aPeerThatTurnsOutPrivateAfterTheConnectionIsRefusedBeforeAnyByteIsSent() {
        // The default connection to a public-looking address that is really this phone's own server: the address check passes (a stand-in rule), the connected peer fails it.
        val calls = AtomicInteger(0)
        val f = LinkPreviewFetcher(resolve = { listOf("127.0.0.1") }, addressAllowed = { calls.incrementAndGet() == 1 }, target = { "https://127.0.0.1:${server.localPort}/page" })
        assertNull(runBlocking { f.make("https://example.org/page") })
        assertEquals("the second check (the connected peer) ran and said no", 2, calls.get())
        assertTrue("the server saw the connection but not one byte of a request: $requests", requests.all { it.isBlank() })
    }

    // ---- LIME-410: the edges of the hand-written HTTP client

    @Test fun aChunkedReplyIsDeChunkedAndExtensionsAreIgnored() {
        val card = make("/chunked")
        assertNotNull(card)
        assertEquals("Chunked title", card!!.title)
        assertEquals("Chunky", card.site)
    }

    @Test fun aChunkThatClaimsMoreThanTheCapStopsAtTheCapAndTheCardStays() {
        val started = System.nanoTime()
        val card = make("/chunked-big")
        assertNotNull("the start of the page is enough for the card", card)
        assertEquals("Cut at the cap", card!!.title)
        assertTrue("it did not wait for 2 GB", (System.nanoTime() - started) / 1_000_000 < 6_000)
        Thread.sleep(1_500)   // the server keeps offering; once the client has closed its writes fail and the count stops
        assertTrue("the client stopped reading at its cap: the server managed to send only ${bigWritten.get()} of 8 MB", bigWritten.get() < 4 * 1024 * 1024)
    }

    @Test fun aMalformedChunkSizeGivesNoCardAndNeverHangs() {
        val started = System.nanoTime()
        assertNull(make("/chunked-bad"))
        assertTrue("answered at once though the server keeps the connection open", (System.nanoTime() - started) / 1_000_000 < 6_000)
    }

    @Test fun aServerThatNeverAnswersIsGivenUpOnAtTheTimeout() {
        val started = System.nanoTime()
        assertNull(make("/silent"))
        val took = (System.nanoTime() - started) / 1_000_000
        assertTrue("gave up after the page timeout (8 s), took $took ms", took in 6_000..14_000)
    }

    @Test fun aServerThatDripsOneByteAtATimeCannotHoldTheFetchPastTheTimeout() {
        val started = System.nanoTime()
        assertNull("a page that is still arriving when the time is up is not used", make("/drip"))
        val took = (System.nanoTime() - started) / 1_000_000
        assertTrue("the whole exchange is bounded, not each read: took $took ms", took < 14_000)
    }

    @Test fun aHeaderSectionPastSixteenKilobytesIsRefused() {
        assertNull("one header line of 20 KB", make("/bigheader"))
        assertNull("thirty headers of 700 bytes (21 KB in all)", make("/manyheaders"))
    }

    @Test fun aRedirectLoopStopsAfterThreeRedirects() {
        val before = connections.get()
        assertNull(runBlocking { LinkPreviewFetcher(connect = { _, _, _, _ -> java.net.Socket("127.0.0.1", server.localPort) }, resolve = { listOf("93.184.216.34") }, addressAllowed = { true }, target = { it }).make("https://example.org/loop") })
        assertTrue("at most the first request and three redirects: ${connections.get() - before}", connections.get() - before <= 4)
    }
}
