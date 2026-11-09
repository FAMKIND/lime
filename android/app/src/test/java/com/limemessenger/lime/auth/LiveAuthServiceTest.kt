package com.limemessenger.lime.auth

import com.limemessenger.lime.net.HttpTransport
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/** The error mapping and the replies, against a local server standing in for the Edge Functions. */
class LiveAuthServiceTest {
    private lateinit var server: HttpServer
    private var status = 200
    private var reply = "{}"
    private var lastPath = ""
    private var lastAuth: String? = null
    private lateinit var service: LiveAuthService

    @Before fun start() {
        server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { ex ->
            lastPath = ex.requestURI.toString(); lastAuth = ex.requestHeaders.getFirst("authorization")
            ex.requestBody.readBytes()
            val out = reply.toByteArray()
            ex.sendResponseHeaders(status, out.size.toLong()); ex.responseBody.use { it.write(out) }
        }
        server.start()
        service = LiveAuthService(HttpTransport("http://127.0.0.1:${server.address.port}", "k", 2000, 2000))
    }

    @After fun stop() = server.stop(0)

    private fun answer(code: Int, json: String) { status = code; reply = json }

    private suspend fun errorOf(block: suspend () -> Unit): AuthError = try { block(); fail("no error"); throw IllegalStateException() } catch (e: AuthError) { e }

    @Test fun identifyMapsTheAnswers() = runTest {
        answer(200, """{"kind":"email","exists":true}"""); assertEquals(IdentifyResult.ExistingEmail, service.identify("a@b.co"))
        answer(200, """{"kind":"email","exists":false}"""); assertEquals(IdentifyResult.NewEmail, service.identify("a@b.co"))
        answer(200, """{"kind":"username","hint":"s•••@x.com"}"""); assertEquals(IdentifyResult.ExistingUsername("s•••@x.com"), service.identify("sam"))
        answer(404, """{"error":"not_found"}"""); assertEquals(IdentifyResult.UnknownUsername, service.identify("nobody"))
        assertEquals("/functions/v1/identify", lastPath)
    }

    @Test fun errorsSpeakInTheAppsWords() = runTest {
        val cases = mapOf(
            (401 to "invalid_credentials") to "That email, username or password isn't right.",
            (400 to "locked") to "Too many wrong codes. Go back and start again to get a new one.",
            (409 to "account_exists") to "That email already has an account. Sign in instead.",
            (400 to "weak_password") to "Use at least 10 characters.",
            (409 to "username_taken") to "That username is taken. Try another.",
            (429 to "") to "Too many tries. Wait a moment and try again.",
            (500 to "email_failed") to "We couldn't send the code. Try again in a moment.",
            (403 to "not_verified") to "Finish signing in first.",
            (401 to "") to "Finish signing in first.",
            (503 to "") to "lime's server had a problem. Try again in a moment.",
        )
        for ((input, words) in cases) {
            answer(input.first, """{"error":"${input.second}"}""")
            assertEquals(words, errorOf { service.signIn("a", "b") }.message)
        }
        answer(400, """{"error":"bad_code"}""")
        assertEquals("That code isn't right.", errorOf { service.verifySignInCode("1", AuthTokens("a", "r", 0, "u")) }.message)
        answer(400, """{"error":"bad_username","message":"Nope."}""")
        assertEquals("Nope.", errorOf { service.saveProfile(ProfileDraft("A"), AuthTokens("a", "r", 0, "u")) }.message)
        answer(400, """{"error":"weird"}""")
        assertEquals("Something went wrong.", errorOf { service.startReset("a") }.message)
    }

    @Test fun signInReturnsTokensAndTheMaskedEmail() = runTest {
        answer(200, """{"access_token":"A","refresh_token":"R","user_id":"U","expires_in":3600,"masked_email":"s•••@x.com"}""")
        val result = service.signIn("sam", "pw")
        assertEquals("A", result.tokens.accessToken); assertEquals("U", result.tokens.userId); assertEquals("s•••@x.com", result.maskedEmail)
        assertTrue(result.tokens.expiresAtMs > System.currentTimeMillis() + 3_000_000)
    }

    @Test fun tokensAreSentAsBearerAndRefreshKeepsTheUser() = runTest {
        answer(200, """{"access_token":"A2","refresh_token":"R2","expires_in":3600,"user":{"id":"U9"}}""")
        val fresh = service.refresh(AuthTokens("a", "r", 0, "U"))
        assertEquals("/auth/v1/token?grant_type=refresh_token", lastPath); assertEquals("U9", fresh.userId)
        answer(200, """{}""")
        service.resendSignInCode(AuthTokens("tok", "r", 0, "U")); assertEquals("Bearer tok", lastAuth)
        answer(400, """{}""")
        assertEquals("Finish signing in first.", errorOf { service.refresh(AuthTokens("a", "r", 0, "U")) }.message)
        answer(500, """{}""")
        assertEquals(AuthError.Unavailable, errorOf { service.refresh(AuthTokens("a", "r", 0, "U")) })
    }

    @Test fun loadProfileReadsTheDirectoryFields() = runTest {
        answer(200, """{"profile":{"display_name":"Ada","username":"ada","about_emoji":"👋","about_text":"Hi"},"masked_email":"a•••@x.com"}""")
        val p = service.loadProfile(AuthTokens("a", "r", 0, "U"))!!
        assertEquals("Ada", p.displayName); assertEquals("👋 Hi", p.about); assertEquals("a•••@x.com", p.maskedEmail)
        answer(200, """{}"""); assertEquals(null, service.loadProfile(AuthTokens("a", "r", 0, "U")))
    }

    @Test fun noServerIsANetworkError() = runTest {
        server.stop(0)
        assertEquals(AuthError.Network, errorOf { service.identify("a@b.co") })
    }
}
