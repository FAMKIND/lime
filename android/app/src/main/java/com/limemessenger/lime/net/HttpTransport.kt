package com.limemessenger.lime.net

import java.net.HttpURLConnection
import java.net.URL
import uniffi.lime_core.HeaderPair
import uniffi.lime_core.Transport
import uniffi.lime_core.TransportException
import uniffi.lime_core.TransportResponse

/**
 * LimeCore's network on Android (the twin of iOS's `URLSessionTransport`): the core decides what to call, this makes the HTTPS request.
 * Calls are blocking, as LimeCore expects, so call them from a background thread (`Dispatchers.IO`), never the main thread.
 *
 * `baseUrl` is the Supabase project URL; `apiKey` is its public key and goes in the `apikey` header. The user's token comes from LimeCore
 * per call. The service-role key never belongs here. Nothing here logs URLs, headers or bodies.
 */
class HttpTransport(
    private val baseUrl: String,
    private val apiKey: String,
    private val connectTimeoutMs: Int = 30_000,
    private val readTimeoutMs: Int = 60_000,
) : Transport {

    override fun request(method: String, path: String, headers: List<HeaderPair>, body: ByteArray): TransportResponse {
        val connection = try {
            URL(baseUrl + path).openConnection() as HttpURLConnection
        } catch (e: Exception) {
            throw TransportException.Failed()
        }
        try {
            connection.requestMethod = method
            connection.connectTimeout = connectTimeoutMs
            connection.readTimeout = readTimeoutMs
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.setRequestProperty("apikey", apiKey)
            for (header in headers) connection.setRequestProperty(header.name, header.value)
            if (body.isNotEmpty()) {
                connection.doOutput = true
                connection.outputStream.use { it.write(body) }
            }
            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val bytes = stream?.use { it.readBytes() } ?: ByteArray(0)
            return TransportResponse(status.toUShort(), bytes)
        } catch (e: Exception) {
            throw TransportException.Failed()
        } finally {
            connection.disconnect()
        }
    }
}
