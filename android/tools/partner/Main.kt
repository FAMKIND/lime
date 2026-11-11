// The partner: a small command-line "other phone" for the Android prototype. It is Ben (android-b@example.invalid) on staging,
// using LimeCore's HOST library through the same generated Kotlin bindings the app uses (no core change). Debug tooling, never shipped.
//
//   partner send "<text>"   send one message to Ada
//   partner echo            run until stopped; accept Ada's first message and reply to each new message with: Ben here: got "<first 40 chars>"
//   partner photo <file>    send a picture to Ada (the echo also sends one back whenever Ada sends a photo)
//   partner voice [file]    send a voice message to Ada (a generated one-second tone when no file is given); the echo answers a voice message with its length and sends one back
//   partner file <file>     send a file to Ada; the echo answers a file with its name and the bytes it downloaded
//   partner jam-publish     (LIME-311) Ben's jam "Ben's classroom notes" (made if missing) and, if not already there, three posts for Ada's phone to read: a quick post,
//                           an article with a photo (with its description), a podcast clip; subscribers-only jam, "free" tier posts
//   partner jam-echo        (LIME-311) runs until stopped: handles subscriptions, answers every comment with "Ben here: thanks!" (a reply), likes are counted by the core, and prints
//                           what it receives ("jam: subscriber …", "jam: comment …", "jam: like …")
//   partner status          print what Ben's store holds
//   partner actions-echo    like echo, and also reacts 👍 to every new message and prints "edited: …" / "deleted: …" when Ada edits or deletes one (LIME-304)
//   partner group-echo      like echo, for every GROUP: accept invitations and answer each new message from someone else with: Ben here: got "<first 40 chars>"
//   partner accept          accept every pending chat request and group invitation once, then stop
//   --as ben|cleo           (anywhere on the line) who this partner is; Cleo has her own store under ~/.lime/android-partner/cleo/
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
private val accountsFile = File(home, "android-test-accounts.json")

/** Who this partner is: `--as ben` (the default; the store lives in android-partner/) or `--as cleo` (android-partner/cleo/). */
private var persona = "ben"
private val account get() = if (persona == "cleo") "c" else "b"
private val personaName get() = if (persona == "cleo") "Cleo" else "Ben"
private val dir get() = (if (persona == "cleo") File(home, "android-partner/cleo") else File(home, "android-partner")).also { it.mkdirs() }
private val sessionFile get() = File(dir, "session.json")

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

/** One second of a 440 Hz tone as a WAV (16-bit mono, 22.05 kHz): a voice message Ada's phone can play, with its 64 loudness bars. */
fun generatedVoice(): OutgoingAttachment {
    val rate = 22_050
    val samples = rate
    val pcm = java.io.ByteArrayOutputStream()
    for (i in 0 until samples) {
        val v = (Math.sin(2 * Math.PI * 440.0 * i / rate) * 0.4 * Short.MAX_VALUE).toInt().toShort()
        pcm.write(v.toInt() and 0xFF); pcm.write((v.toInt() shr 8) and 0xFF)
    }
    val data = pcm.toByteArray()
    fun le(n: Int, bytes: Int) = ByteArray(bytes) { ((n shr (8 * it)) and 0xFF).toByte() }
    val header = "RIFF".toByteArray() + le(36 + data.size, 4) + "WAVEfmt ".toByteArray() + le(16, 4) + le(1, 2) + le(1, 2) + le(rate, 4) + le(rate * 2, 4) + le(2, 2) + le(16, 2) + "data".toByteArray() + le(data.size, 4)
    val bars = ByteArray(64) { (100 + 100 * Math.abs(Math.sin(it / 5.0))).toInt().toByte() }
    return OutgoingAttachment(header + data, "Ben's voice.wav", "audio/wav", null, null, 1000u, bars, ByteArray(0), "")
}

private fun clock(ms: Long): String { val s = (ms + 500) / 1000; return "%d:%02d".format(s / 60, s % 60) }

private fun mimeOf(file: File) = when (file.extension.lowercase()) {
    "png" -> "image/png"; "gif" -> "image/gif"; "jpg", "jpeg" -> "image/jpeg"; "m4a" -> "audio/mp4"; "wav" -> "audio/wav"; "pdf" -> "application/pdf"; "txt" -> "text/plain"
    else -> "application/octet-stream"
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
    val ben = section(text, account)
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
    val asIndex = args.indexOf("--as")
    if (asIndex >= 0) persona = args.getOrNull(asIndex + 1)?.lowercase()?.takeIf { it == "ben" || it == "cleo" } ?: error("usage: --as ben|cleo")
    val args = if (asIndex >= 0) args.filterIndexed { i, _ -> i != asIndex && i != asIndex + 1 }.toTypedArray() else args
    val command = args.firstOrNull() ?: run { System.err.println("usage: partner send \"<text>\" | echo | status | reset"); return }
    if (command == "reset") {
        dir.listFiles()?.filter { it.name.startsWith("lime.db") }?.forEach { it.delete() }
        println("reset: $personaName's store is forgotten (a new device registers on the next command)")
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
        "voice" -> {
            val file = args.getOrNull(1)?.let { File(it) }
            val note = if (file == null) generatedVoice() else OutgoingAttachment(file.readBytes(), file.name, mimeOf(file), null, null, args.getOrNull(2)?.toUIntOrNull() ?: 1000u, ByteArray(64) { 128.toByte() }, ByteArray(0), "")
            store.startDm(adaId, "Ada")
            store.sendAttachments(dm, "", listOf(note), null)
            store.deliverQueued(http, freshToken(http, tokens))
            println("sent")
        }
        "file" -> {
            val file = File(args.getOrNull(1) ?: error("usage: partner file <file>"))
            store.startDm(adaId, "Ada")
            store.sendAttachments(dm, "", listOf(OutgoingAttachment(file.readBytes(), file.name, mimeOf(file), null, null, null, ByteArray(0), ByteArray(0), "")), null)
            store.deliverQueued(http, freshToken(http, tokens))
            println("sent")
        }
        "jam-publish" -> {
            store.sync(http, freshToken(http, tokens))
            val mine = store.listMyJams().firstOrNull { !it.ended }
            if (mine == null) store.createJam("Ben's classroom notes", "Notes and short clips from Ben's classroom.", listOf("science", "grade 4"))   // (returns the conversation id, not the jam id)
            val jamId = store.listMyJams().first { !it.ended }.jamId
            // Pages left live by an earlier reset of Ben's store (nothing local owns them) would be served first, being older: end them (Ben's own test jams).
            fun jamPage(json: String) = http.request("POST", "/functions/v1/jam-page", listOf(HeaderPair("content-type", "application/json"), HeaderPair("authorization", "Bearer " + freshToken(http, tokens))), json.toByteArray()).body.decodeToString()
            val live = Regex(""""jam_id":"([0-9a-f-]{36})"""").findAll(jamPage("""{"action":"by_writer","writer_id":"${tokens.userId}"}""")).map { it.groupValues[1] }.toSet()
            for (orphan in live - store.listMyJams().map { it.jamId }.toSet()) { jamPage("""{"action":"end","jam_id":"$orphan"}"""); println("jam: ended an orphan page ${orphan.take(8)}") }
            val have = if (mine != null) store.listJamPosts(jamId).map { it.title.ifEmpty { it.plain.take(20) } }.toSet() else emptySet()
            val quick = "First day of the magnets unit! Who has a favourite experiment?"
            if (quick.take(20) !in have) store.publishJamPost(jamId, "quick", "", "", quick, "free", emptyList(), emptyList())
            if ("How we built a bridge" !in have) {
                val photo = generatedPhoto()
                store.publishJamPost(
                    jamId, "article", "How we built a bridge", "A week of engineering with grade 4",
                    "We spent a week on bridges.\n\n![Students testing the bridge](attachment:0)\n\nThe **strongest** one held 40 books.\n\n- tape\n- straws\n- patience",
                    "free", listOf(photo), emptyList(),
                )
            }
            if ("Ben's quick physics tip" !in have) store.publishJamPost(jamId, "record", "Ben's quick physics tip", "One second of a tone", "", "free", listOf(generatedVoice()), emptyList())
            store.deliverQueued(http, freshToken(http, tokens))
            println("jam: $jamId with ${store.listJamPosts(jamId).size} posts")
        }
        "jam-echo" -> {
            val answered = mutableSetOf<String>()
            val noted = mutableSetOf<String>()
            val seenPosts = mutableMapOf<String, String>()
            val seenLabels = mutableMapOf<String, String>()
            println("jam-echo: listening as $personaName (Ctrl-C to stop)")
            while (true) {
                try {
                    store.sync(http, freshToken(http, tokens))
                    for (jam in store.listMyJams().filter { !it.ended }) {
                        for (sub in store.listJamSubscribers(jam.jamId)) if (noted.add("s:" + sub.userId + sub.status)) println("jam: subscriber ${sub.name.ifEmpty { sub.userId.take(8) }} (${sub.status})")
                        for (post in store.listJamPosts(jam.jamId)) {
                            val counts = store.jamPostCounts(post.postId)
                            if (counts.likes > 0u && noted.add("l:${post.postId}:${counts.likes}")) println("jam: like on \"${post.title.ifEmpty { post.plain.take(20) }}\" (${counts.likes})")
                            for (c in store.listJamComments(post.postId)) {
                                if (c.mine || c.commentId in answered) continue
                                answered += c.commentId
                                println("jam: comment \"${c.text.take(40)}\"")
                                store.commentOnJamPost(post.postId, "Ben here: thanks!", c.parentId ?: c.commentId)
                            }
                        }
                    }
                    // A teacher who writes to Ben first becomes a chat request: accept it, so each can send to the other (a subscription travels like a message).
                    store.listConversations().filter { it.requestState == "pending" }.forEach { runCatching { store.acceptRequest(it.id) } }
                    // LIME-312: Ben follows Ada's jam when she has one, says what arrives (a new post, an edit, a delete) and comments on each new post.
                    val followed = store.listJamSubscriptions()
                    if (followed.none { it.writer == adaId && it.status != "left" && !it.ended }) {
                        store.fetchJamPage(http, freshToken(http, tokens), adaId)?.let { page ->
                            store.subscribeToJam(page.jamId, page.writerId)
                            println("jam: subscribed to Ada's jam \"${page.title}\"")
                        }
                    }
                    followed.filter { it.writer == adaId }.forEach { j ->
                        val states = store.listJamPosts(j.jamId).joinToString(",") { it.state }
                        if (noted.add("a:${j.status}:$states")) println("jam: Ada's jam is ${j.status}; posts [$states]")
                    }
                    for (jam in followed.filter { it.writer == adaId && it.status == "active" }) {
                        val now = store.listJamPosts(jam.jamId)
                        // A deleted post leaves the list (or turns "gone"): say so once.
                        for (id in seenPosts.keys.toList()) if (now.none { it.postId == id && it.state != "gone" } && noted.add("g:$id")) println("jam: post removed \"${seenLabels[id].orEmpty()}\"")
                        for (post in now) {
                            val label = post.title.ifEmpty { post.plain.take(40) }
                            if (post.state == "gone") continue
                            if (post.state != "ready") continue
                            val signature = post.title + "|" + post.subtitle + "|" + post.markdown
                            seenLabels[post.postId] = label
                            val before = seenPosts.put(post.postId, signature)
                            if (before == null) {
                                println("jam: received ${post.kind} \"$label\" (${post.attachmentsJson.split("\"mime\"").size - 1} files)")
                                store.commentOnJamPost(post.postId, "Ben here: nice ${post.kind}!", null)
                            } else if (before != signature) println("jam: edited \"$label\"")
                        }
                    }
                    store.deliverQueued(http, freshToken(http, tokens))
                } catch (e: Exception) {
                    System.err.println("jam-echo: ${e::class.simpleName} (will retry)")
                }
                Thread.sleep(2000)
            }
        }
        "status" -> {
            store.sync(http, freshToken(http, tokens))
            val all = store.listConversations()
            println("conversations: ${all.size}; with Ada: ${all.any { it.id == dm }}")
        }
        "echo", "actions-echo" -> {
            // `actions-echo` (LIME-304) also reacts 👍 to each new message and prints "edited: …" / "deleted: …" when Ada changes one.
            val actions = command == "actions-echo"
            val seen = mutableMapOf<String, String>()
            // Everything already in the chat is history: only messages that arrive from now on are answered.
            val answered = mutableSetOf<String>()
            runCatching { store.sync(http, freshToken(http, tokens)) }
            runCatching { store.listMessages(dm) }.getOrNull()?.forEach { answered += it.id }
            println("echo: listening as $personaName (Ctrl-C to stop)")
            while (true) {
                try {
                    store.sync(http, freshToken(http, tokens))
                    store.listConversations().firstOrNull { it.id == dm && it.requestState == "pending" }?.let { store.acceptRequest(dm) }
                    val fresh = store.listMessages(dm).filter { it.senderId != null && it.id !in answered && it.localState != "system" }
                    for (m in fresh) {
                        answered += m.id
                        val words = messagePlainText(m.text).replace("\n", " ").take(40)
                        println("markdown: " + m.text.replace("\n", "\\n"))   // what arrived, exactly (LIME-405 compares it with what Android sent)
                        val photos = m.attachments.filter { it.mime.startsWith("image/") }
                        if (photos.isNotEmpty()) {
                            // Prove the photo arrived whole: download it, decrypt it, and report how big it came out.
                            val sizes = photos.map { p -> store.downloadAttachment(http, freshToken(http, tokens), p.id); store.attachmentData(p.id)?.size ?: -1 }
                            store.queueText(dm, "$personaName here: got ${photos.size} photo${if (photos.size == 1) "" else "s"} (${sizes.joinToString { "$it bytes" }})" + (if (words.isNotEmpty()) " and \"$words\"" else ""))
                            store.sendAttachments(dm, "Ben's photo", listOf(generatedPhoto()), null)
                        } else if (m.attachments.any { it.mime.startsWith("audio/") }) {
                            // Prove the voice message arrived whole, say how long it is, and answer with one of our own.
                            val v = m.attachments.first { it.mime.startsWith("audio/") }
                            store.downloadAttachment(http, freshToken(http, tokens), v.id)
                            store.queueText(dm, "$personaName here: got a voice message (${clock((v.durationMs ?: 0u).toLong())}, ${store.attachmentData(v.id)?.size ?: -1} bytes)")
                            store.sendAttachments(dm, "", listOf(generatedVoice()), null)
                        } else if (m.attachments.isNotEmpty()) {
                            val f = m.attachments.first()
                            store.downloadAttachment(http, freshToken(http, tokens), f.id)
                            store.queueText(dm, "$personaName here: got a file \"${f.name}\" (${store.attachmentData(f.id)?.size ?: -1} bytes)")
                        } else {
                            store.queueText(dm, "$personaName here: got \"$words\"")
                        }
                        if (actions) { store.react(dm, m.id, "👍", true); seen[m.id] = m.text }
                        store.deliverQueued(http, freshToken(http, tokens))
                        println("replied to a message")
                    }
                    if (actions) {
                        val now = store.listMessages(dm).associateBy { it.id }
                        for ((id, was) in seen.toMap()) {
                            val m = now[id] ?: continue
                            if (m.deleted && was != "\u0000deleted") { seen[id] = "\u0000deleted"; println("deleted: ${messagePlainText(was).replace("\n", " ").take(40)}") }
                            else if (!m.deleted && m.text != was && was != "\u0000deleted") { seen[id] = m.text; println("edited: ${messagePlainText(m.text).replace("\n", " ").take(40)}") }
                        }
                    }
                } catch (e: uniffi.lime_core.StoreException.KeyMismatch) {
                    System.err.println("echo: Ada's keys changed (a new emulator or a fresh sign-in): stop, run `partner reset`, and start echo again")
                } catch (e: Exception) {
                    System.err.println("echo: ${e::class.simpleName} (will retry)")
                }
                Thread.sleep(2000)
            }
        }
        "accept" -> {
            store.sync(http, freshToken(http, tokens))
            val pending = store.listConversations().filter { it.requestState == "pending" }
            for (c in pending) store.acceptRequest(c.id)
            store.deliverQueued(http, freshToken(http, tokens))
            println("accepted ${pending.size}")
        }
        "group-echo" -> {
            // `--direct` also answers one-to-one chats (the night-2 recording uses one partner process each for Ben and Cleo).
            val answerDirect = "--direct" in args
            // Every message already in a group is history; only what arrives from now on is answered (and own messages never are).
            val answered = mutableSetOf<String>()
            runCatching { store.sync(http, freshToken(http, tokens)) }
            for (c in runCatching { store.listConversations() }.getOrDefault(emptyList()).filter { it.isGroup || answerDirect }) runCatching { store.listMessages(c.id) }.getOrNull()?.forEach { answered += it.id }
            println("group-echo: listening as $personaName (Ctrl-C to stop)")
            while (true) {
                try {
                    store.sync(http, freshToken(http, tokens))
                    for (c in store.listConversations().filter { it.requestState == "pending" }) { store.acceptRequest(c.id); println("accepted an invitation") }
                    for (c in store.listConversations().filter { it.requestState != "pending" && (it.isGroup || answerDirect) }) {
                        // A group's own lines ("Ada left", "Ada renamed the group to …") are only printed, for the test run to check.
                        for (m in store.listMessages(c.id).filter { it.localState == "system" && it.id !in answered }) { answered += m.id; println("system: ${m.text}") }
                        // (Never answer another partner's echo: Ben and Cleo would answer each other for ever.)
                        val fresh = store.listMessages(c.id).filter { it.senderId != null && it.id !in answered && it.localState != "system" && !Regex("^(Ben|Cleo) here: ").containsMatchIn(messagePlainText(it.text)) }
                        for (m in fresh) {
                            answered += m.id
                            val words = messagePlainText(m.text).replace("\n", " ").take(40)
                            println("markdown: " + m.text.replace("\n", "\\n"))   // what arrived, exactly (LIME-406 B compares a mention's markup)
                            store.queueText(c.id, "$personaName here: got \"$words\"")
                            store.deliverQueued(http, freshToken(http, tokens))
                            println("replied in a group")
                        }
                    }
                } catch (e: Exception) {
                    System.err.println("group-echo: ${e::class.simpleName} (will retry)")
                }
                Thread.sleep(2000)
            }
        }
        else -> System.err.println("unknown command: $command")
    }
}
