package com.limemessenger.lime

import com.limemessenger.lime.net.HttpTransport
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import uniffi.lime_core.HeaderPair
import uniffi.lime_core.TransportException

class HttpTransportTest {
    @Test
    fun sendsTheApiKeyHeadersAndBodyAndReturnsStatusAndBody() {
        var seenKey: String? = null
        var seenAuth: String? = null
        var seenBody = ""
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/functions/v1/identify") { ex ->
            seenKey = ex.requestHeaders.getFirst("apikey")
            seenAuth = ex.requestHeaders.getFirst("authorization")
            seenBody = ex.requestBody.readBytes().decodeToString()
            val out = """{"error":"nope"}""".toByteArray()
            ex.sendResponseHeaders(404, out.size.toLong())
            ex.responseBody.use { it.write(out) }
        }
        server.start()
        try {
            val transport = HttpTransport("http://127.0.0.1:${server.address.port}", "anon-key")
            val response = transport.request(
                "POST", "/functions/v1/identify",
                listOf(HeaderPair("authorization", "Bearer t"), HeaderPair("content-type", "application/json")),
                """{"identifier":"x"}""".toByteArray(),
            )
            assertEquals(404.toUShort(), response.status)
            assertEquals("""{"error":"nope"}""", response.body.decodeToString())
            assertEquals("anon-key", seenKey)
            assertEquals("Bearer t", seenAuth)
            assertEquals("""{"identifier":"x"}""", seenBody)
        } finally {
            server.stop(0)
        }
    }

    @Test
    fun noResponseIsATransportExceptionNotAStatus() {
        val transport = HttpTransport("http://127.0.0.1:1", "k", connectTimeoutMs = 500, readTimeoutMs = 500)
        try {
            transport.request("GET", "/x", emptyList(), ByteArray(0))
            fail("expected a failure")
        } catch (e: TransportException) {
            assertTrue(e is TransportException.Failed)
        }
    }
}
