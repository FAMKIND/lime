// The partner: a small command-line "other phone" for the Android prototype. It is Ben (android-b@example.invalid) on staging,
// using LimeCore's HOST library through the same generated Kotlin bindings the app uses (no core change). Debug tooling, never shipped.
//
//   partner send "<text>"   send one message to Ada
//   partner echo            run until stopped; accept Ada's first message and reply to each new message with: Ben here: got "<first 40 chars>"
//   partner photo <file>    send a picture to Ada (the echo also sends one back whenever Ada sends a photo)
//   partner status          print what Ben's store holds
//   partner reset           forget Ben's store (do this whenever Ada signs in on a new emulator: her keys are new, and Ben pins the old ones)
//
// Ben's sessions come from ~/.lime/android-test-accounts.json (android/tools/staging-test-accounts.sh); his own store and key live in
// ~/.lime/android-partner/ (outside the repo). Nothing secret is printed; message text is printed only as the replies it sends.
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import uniffi.lime_core.HeaderPair
import uniffi.lime_core.LimeStore
import uniffi.lime_core.OutgoingAttachment
import uniffi.lime_core.Transport
import uniffi.lime_core.TransportException
import uniffi.lime_core.TransportResponse
import uniffi.lime_core.messagePlainText

private val home = File(System.getProperty("user.home"), ".lime")
private val dir = File(home, "android-partner").also { it.mkdirs() }
private val accountsFile = File(home, "android-test-accounts.json")
private val sessionFile = File(dir, "session.json")

class Http(private val base: String, private val apiKey: String) : Transport {
    override fun request(method: String, path: String, headers: List<HeaderPair>, body: ByteArray): TransportResponse {
        try {
            val c = URL(base + path).openConnection() as HttpURLConnection
            try {
                c.requestMethod = method; c.connectTimeout = 30_000; c.readTimeout = 60_000; c.instanceFollowRedirects = false
                c.setRequestProperty("apikey", apiKey)
                for (h in headers) c.setRequestProperty(h.name, h.value)
                if (body.isNotEmpty()) { c.doOutput = true; c.outputStream.use { it.write(body) } }
                val status = c.responseCode
                val bytes = (if (status >= 400) c.errorStream else c.inputStream)?.use { it.readBytes() } ?: ByteArray(0)
                return TransportResponse(status.toUShort(), bytes)
            } finally { c.disconnect() }
        } catch (e: Exception) { throw TransportException.Failed() }
    }

    /** POST JSON, returns (status, body text). */
    fun post(path: String, json: String): Pair<Int, String> {
        val r = request("POST", path, listOf(HeaderPair("content-type", "application/json")), json.toByteArray())
        return r.status.toInt() to r.body.decodeToString()
    }
}

/** A small generated JPEG for the echo to send back (so no picture file has to exist). */
fun generatedPhoto(): OutgoingAttachment {
    fun jpeg(w: Int, h: Int): ByteArray {
        val image = java.awt.image.BufferedImage(w, h, java.awt.image.BufferedImage.TYPE_INT_RGB)
        val g = image.createGraphics()
        g.paint = java.awt.GradientPaint(0f, 0f, java.awt.Color(0x09, 0xa9, 0x50), w.toFloat(), h.toFloat(), java.awt.Color(0x13, 0x1b, 0x17))
        g.fillRect(0, 0, w, h); g.dispose()
        val out = java.io.ByteArrayOutputStream(); javax.imageio.ImageIO.write(image, "jpg", out); return out.toByteArray()
    }
    return OutgoingAttachment(jpeg(480, 300), "ben.jpg", "image/jpeg", 480u, 300u, null, jpeg(40, 25), ByteArray(0), "A green gradient fading to dark, from Ben")
}

private fun field(text: String, key: String): String? = Regex("\"$key\"\\s*:\\s*\"([^\"]*)\"").find(text)?.groupValues?.get(1)
private fun number(text: String, key: String): Long? = Regex("\"$key\"\\s*:\\s*([0-9.]+)").find(text)?.groupValues?.get(1)?.toDouble()?.toLong()
private fun section(text: String, name: String): String {
    val start = text.indexOf("\"$name\": {").takeIf { it >= 0 } ?: error("account '$name' not in ${accountsFile.path}")
    return text.substring(start, text.indexOf("}", start))
}

class Tokens(var access: String, var refresh: String, var expiresAtSec: Long, val userId: String)

fun loadAccounts(): Triple<String, Tokens, String> {   // (api url, Ben's tokens, Ada's user id)
    require(accountsFile.exists()) { "Run android/tools/staging-test-accounts.sh first." }
    val text = accountsFile.readText()
    val api = field(text, "api_url")!!
    val ben = section(text, "b")
    val ada = section(text, "a")
    val fromFile = Tokens(field(ben, "access_token")!!, field(ben, "refresh_token")!!, number(ben, "expires_at")!!, field(ben, "user_id")!!)
    // A newer accounts file (the script ran again: new sessions) wins over the partner's own refreshed session.
    val tokens = if (sessionFile.exists() && sessionFile.lastModified() > accountsFile.lastModified()) {
        val s = sessionFile.readText()
        Tokens(field(s, "access")!!, field(s, "refresh")!!, number(s, "expires")!!, fromFile.userId)
    } else fromFile
    return Triple(api, tokens, field(ada, "user_id")!!)
}

fun anonKey(): String = File(dir, "anon").readText().trim()

/** Refreshes Ben's session when it is within five minutes of expiring, and keeps the new tokens (a refresh token is single-use). */
fun freshToken(http: Http, t: Tokens): String {
    if (t.expiresAtSec - System.currentTimeMillis() / 1000 > 300) return t.access
    val (status, body) = http.post("/auth/v1/token?grant_type=refresh_token", """{"refresh_token":"${t.refresh}"}""")
    check(status == 200) { "could not refresh Ben's session ($status): run android/tools/staging-test-accounts.sh again" }
    t.access = field(body, "access_token")!!; t.refresh = field(body, "refresh_token")!!
    t.expiresAtSec = System.currentTimeMillis() / 1000 + (number(body, "expires_in") ?: 3600)
    sessionFile.writeText("""{"access":"${t.access}","refresh":"${t.refresh}","expires":${t.expiresAtSec}}""")
    sessionFile.setReadable(false, false); sessionFile.setReadable(true, true); sessionFile.setWritable(true, true)
    return t.access
}

fun openStore(): LimeStore {
    val keyFile = File(dir, "key")
    if (!keyFile.exists()) {
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        keyFile.writeText(bytes.joinToString("") { "%02x".format(it) })
        keyFile.setReadable(false, false); keyFile.setReadable(true, true); keyFile.setWritable(true, true)
    }
    val key = keyFile.readText().trim().chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    return LimeStore.open(File(dir, "lime.db").path, key)
}

fun main(args: Array<String>) {
    val command = args.firstOrNull() ?: run { System.err.println("usage: partner send \"<text>\" | echo | status | reset"); return }
    if (command == "reset") {
        dir.listFiles()?.filter { it.name.startsWith("lime.db") }?.forEach { it.delete() }
        println("reset: Ben's store is forgotten (a new device registers on the next command)")
        return
    }
    val (api, tokens, adaId) = loadAccounts()
    // The public (anon) key: from the same public env file the app builds with.
    val envFile = generateSequence(File(".").absoluteFile) { it.parentFile }.map { File(it, "supabase/.staging.public.env") }.firstOrNull { it.exists() }
        ?: File(System.getenv("LIME_PUBLIC_ENV") ?: "supabase/.staging.public.env")
    val anon = envFile.readLines().first { it.startsWith("SUPABASE_ANON_KEY=") }.substringAfter("=").trim().trim('"')
    val http = Http(api, anon)
    val store = openStore()
    store.registerDevice(http, freshToken(http, tokens))
    val dm = "dm:$adaId"
    when (command) {
        "send" -> {
            val text = args.getOrNull(1) ?: error("usage: partner send \"<text>\"")
            store.sendTextIdentified(http, freshToken(http, tokens), adaId, text)
            println("sent")
        }
        "photo" -> {
            val file = File(args.getOrNull(1) ?: error("usage: partner photo <file>"))
            val mime = when (file.extension.lowercase()) { "png" -> "image/png"; "gif" -> "image/gif"; else -> "image/jpeg" }
            store.startDm(adaId, "Ada")
            store.sendAttachments(dm, args.getOrNull(2).orEmpty(), listOf(OutgoingAttachment(file.readBytes(), file.name, mime, null, null, null, ByteArray(0), ByteArray(0), "")), null)
            store.deliverQueued(http, freshToken(http, tokens))
            println("sent")
        }
        "status" -> {
            store.sync(http, freshToken(http, tokens))
            val all = store.listConversations()
            println("conversations: ${all.size}; with Ada: ${all.any { it.id == dm }}")
        }
        "echo" -> {
            // Everything already in the chat is history: only messages that arrive from now on are answered.
            val answered = mutableSetOf<String>()
            runCatching { store.sync(http, freshToken(http, tokens)) }
            runCatching { store.listMessages(dm) }.getOrNull()?.forEach { answered += it.id }
            println("echo: listening as Ben (Ctrl-C to stop)")
            while (true) {
                try {
                    store.sync(http, freshToken(http, tokens))
                    store.listConversations().firstOrNull { it.id == dm && it.requestState == "pending" }?.let { store.acceptRequest(dm) }
                    val fresh = store.listMessages(dm).filter { it.senderId != null && it.id !in answered && it.localState != "system" }
                    for (m in fresh) {
                        answered += m.id
                        val words = messagePlainText(m.text).replace("\n", " ").take(40)
                        val photos = m.attachments.filter { it.mime.startsWith("image/") }
                        if (photos.isNotEmpty()) {
                            // Prove the photo arrived whole: download it, decrypt it, and report how big it came out.
                            val sizes = photos.map { p -> store.downloadAttachment(http, freshToken(http, tokens), p.id); store.attachmentData(p.id)?.size ?: -1 }
                            store.queueText(dm, "Ben here: got ${photos.size} photo${if (photos.size == 1) "" else "s"} (${sizes.joinToString { "$it bytes" }})" + (if (words.isNotEmpty()) " and \"$words\"" else ""))
                            store.sendAttachments(dm, "Ben's photo", listOf(generatedPhoto()), null)
                        } else {
                            store.queueText(dm, "Ben here: got \"$words\"")
                        }
                        store.deliverQueued(http, freshToken(http, tokens))
                        println("replied to a message")
                    }
                } catch (e: uniffi.lime_core.StoreException.KeyMismatch) {
                    System.err.println("echo: Ada's keys changed (a new emulator or a fresh sign-in): stop, run `partner reset`, and start echo again")
                } catch (e: Exception) {
                    System.err.println("echo: ${e::class.simpleName} (will retry)")
                }
                Thread.sleep(2000)
            }
        }
        else -> System.err.println("unknown command: $command")
    }
}
