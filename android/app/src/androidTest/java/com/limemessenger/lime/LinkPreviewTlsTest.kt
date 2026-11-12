package com.limemessenger.lime

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.limemessenger.lime.chats.LinkPreviewFetcher
import java.net.InetAddress
import java.net.ServerSocket
import java.security.KeyFactory
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * LIME-410: the link-preview client's TLS guards against a LOCAL TLS server (a certificate chain checked for real; the debug build trusts one throw-away test CA, see
 * `assets/tls/README.txt`). The fetcher uses its DEFAULT connection here (a pinned socket and TLS over it); only the name lookup and the address policy are stubbed so that
 * `good.example` reaches this device. What is proved: a certificate that is wrong in any way gives no card and **not one request byte is sent** to that server.
 */
@RunWith(AndroidJUnit4::class)
class LinkPreviewTlsTest {
    private val servers = mutableListOf<TlsServer>()

    /** A TLS web server on 127.0.0.1 presenting the certificate `cert` (assets/tls/<cert>.pem + .pk8). Counts what the client sends after the handshake. */
    private inner class TlsServer(cert: String, private val body: (path: String, out: java.io.OutputStream) -> Unit) {
        val requestBytes = AtomicInteger(0)
        val requests = AtomicInteger(0)
        val handshakeFailures = AtomicInteger(0)
        private val socket: SSLServerSocket
        @Volatile private var running = true
        val port get() = socket.localPort

        init {
            val assets = InstrumentationRegistry.getInstrumentation().context.assets
            val certificate = assets.open("tls/$cert.pem").use { CertificateFactory.getInstance("X.509").generateCertificate(it) }
            val key = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(assets.open("tls/$cert.pk8").use { it.readBytes() }))
            val store = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null); setKeyEntry("k", key, CharArray(0), arrayOf(certificate)) }
            val managers = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(store, CharArray(0)) }.keyManagers
            val context = SSLContext.getInstance("TLS").apply { init(managers, null, null) }
            socket = context.serverSocketFactory.createServerSocket(0, 50, InetAddress.getByName("127.0.0.1")) as SSLServerSocket
            Thread {
                while (running) {
                    val client = runCatching { socket.accept() as SSLSocket }.getOrNull() ?: break
                    Thread { serve(client) }.start()
                }
            }.start()
            servers += this
        }

        private fun serve(client: SSLSocket) = runCatching {
            client.use { c ->
                c.soTimeout = 3_000
                try { c.startHandshake() } catch (e: Exception) { handshakeFailures.incrementAndGet(); return@use }
                val input = c.getInputStream()
                val head = StringBuilder()
                while (!head.endsWith("\r\n\r\n")) { val b = input.read(); if (b < 0) break; requestBytes.incrementAndGet(); head.append(b.toChar()) }
                if (head.isEmpty()) return@use
                requests.incrementAndGet()
                body(head.lineSequence().first().split(" ").getOrElse(1) { "/" }, c.getOutputStream())
            }
        }

        fun close() { running = false; runCatching { socket.close() } }
    }

    @After fun stop() { servers.forEach { it.close() } }

    private val page = """<html><head><meta property="og:title" content="Over TLS"><meta property="og:site_name" content="Good Example"></head><body>x</body></html>"""
    private fun ok(out: java.io.OutputStream, body: String = page) {
        out.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: ${body.toByteArray().size}\r\nConnection: close\r\n\r\n$body".toByteArray()); out.flush()
    }
    private fun redirect(out: java.io.OutputStream, to: String) { out.write("HTTP/1.1 302 Found\r\nLocation: $to\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray()); out.flush() }

    /** The default connection (pinned socket + TLS); `good.example` is "resolved" to this device and let through the address policy; every other address uses the real rules. */
    private fun fetcher() = LinkPreviewFetcher(
        resolve = { listOf("127.0.0.1") }, addressAllowed = { true },
        target = { if (it.startsWith("https://good.example:")) it else uniffi.lime_core.linkPreviewTarget(it) },
    )
    private fun make(server: TlsServer, path: String = "/page") = runBlocking { fetcher().make("https://good.example:${server.port}$path") }

    @Test fun aGoodCertificateForTheRightNameGivesTheCard() {
        val server = TlsServer("good") { _, out -> ok(out) }
        val card = make(server)
        assertNotNull("the harness itself works: a valid chain for the right name is accepted", card)
        assertEquals("Over TLS", card!!.title)
        assertEquals(1, server.requests.get())
    }

    @Test fun aSelfSignedCertificateGivesNothingAndNoRequestByteIsSent() {
        val server = TlsServer("selfsigned") { _, out -> ok(out) }
        assertNull(make(server))
        assertEquals("not one request byte reached the server", 0, server.requestBytes.get())
        assertEquals(0, server.requests.get())
    }

    @Test fun aValidChainForAnotherNameIsRefusedByTheNameCheckBeforeAnyRequestByte() {
        val server = TlsServer("other") { _, out -> ok(out) }   // signed by the trusted test CA, but for other.example
        assertNull(make(server))
        assertEquals("the request was never written", 0, server.requestBytes.get())
        assertEquals(0, server.requests.get())
    }

    @Test fun aRedirectToAPrivateAddressOverTlsFetchesNothingMore() {
        val server = TlsServer("good") { _, out -> redirect(out, "https://192.168.1.1/admin") }
        assertNull(make(server))
        assertEquals("the first hop only; the private address was never asked for", 1, server.requests.get())
    }

    @Test fun aRedirectLoopStopsAfterTheLimit() {
        val server = TlsServer("good") { _, out -> redirect(out, "https://good.example:${servers.first().port}/loop") }
        assertNull(make(server, "/loop"))
        assertEquals("the first request and three redirects, no more", 4, server.requests.get())
    }

    @Test fun aRedirectToAnotherNameChecksThatNamesCertificateToo() {
        // The second hop goes to the same server by another name: its certificate is for good.example, so other names are refused.
        val server = TlsServer("good") { path, out -> if (path == "/start") redirect(out, "https://good.example:${servers.first().port}/page") else ok(out) }
        assertNotNull("a redirect on the same name works", make(server, "/start"))
        assertEquals(2, server.requests.get())
    }

    @Test fun theLoopbackAddressItselfIsNeverUsedByTheRealPolicy() {
        // The same server, but with the real address rules: 127.0.0.1 is private, so the name is refused before any connection.
        val server = TlsServer("good") { _, out -> ok(out) }
        val real = LinkPreviewFetcher(resolve = { listOf("127.0.0.1") }, target = { it })
        assertNull(runBlocking { real.make("https://good.example:${server.port}/page") })
        assertTrue(server.handshakeFailures.get() == 0 && server.requestBytes.get() == 0 && server.requests.get() == 0)
    }
}
