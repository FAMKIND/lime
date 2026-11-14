// The partner: a small command-line "other phone" for the Mac lane. It is Ben or Cleo (mac-b / mac-c@example.invalid) on staging,
// using LimeCore's macOS slice through the same generated Swift bindings the app will use (no core change). Debug tooling, never shipped.
//
//   partner --as b|c send --to <username> "<text>"   send one message (the first message to someone is a chat request on their side)
//   partner --as b|c echo                            run until stopped: accept every chat request, and answer each new message from someone else
//                                                    with:  Ben here: got "<first 40 chars>"   (Cleo: "Cleo here: ...")
//   partner --as b|c inbox [--from <username>]       sync once, accept requests, print what arrived (test accounts only; this tool prints text)
//   partner --as b|c status                          sync once and say what the store holds (a short device-id prefix shows it is the same device each run)
//   partner --as b|c reset                           forget this account's store (do this whenever Ada's app signs in on a new Mac: her keys are new)
//
// Sessions come from ~/.lime/mac-test-accounts.json (mac/tools/staging-test-accounts.sh); the partner's own encrypted store and its key live in
// ~/.lime/mac-partner/<a|b|c>/ (outside the repo; the key file is chmod 600). The device registers once per account; later runs reuse the store.
// Nothing secret is printed.
import Foundation

private let home = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".lime")
private let accountsFile = home.appendingPathComponent("mac-test-accounts.json")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: arguments

var rawArgs = Array(CommandLine.arguments.dropFirst())
var persona = "b"
if let i = rawArgs.firstIndex(of: "--as") {
    guard i + 1 < rawArgs.count, ["b", "c"].contains(rawArgs[i + 1].lowercased()) else { fail("usage: --as b|c") }
    persona = rawArgs[i + 1].lowercased()
    rawArgs.removeSubrange(i...(i + 1))
}
var toName: String?
if let i = rawArgs.firstIndex(of: "--to") {
    guard i + 1 < rawArgs.count else { fail("usage: --to <username>") }
    toName = rawArgs[i + 1]
    rawArgs.removeSubrange(i...(i + 1))
}
var fromName: String?
if let i = rawArgs.firstIndex(of: "--from") {
    guard i + 1 < rawArgs.count else { fail("usage: --from <username>") }
    fromName = rawArgs[i + 1]
    rawArgs.removeSubrange(i...(i + 1))
}
guard let command = rawArgs.first else {
    fail("usage: partner --as b|c send --to <username> \"<text>\" | echo | inbox [--from <username>] | status | reset")
}
let personaName = persona == "c" ? "Cleo" : "Ben"
let dir = home.appendingPathComponent("mac-partner/\(persona)")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

if command == "reset" {
    for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasPrefix("lime.db") {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
    }
    print("reset: \(personaName)'s store is forgotten (a new device registers on the next command)")
    exit(0)
}

// MARK: accounts, sessions

struct Account { let userId: String; let username: String; let displayName: String }
final class Session { var access: String; var refresh: String; var expires: Double
    init(_ a: String, _ r: String, _ e: Double) { access = a; refresh = r; expires = e } }

guard let accountsData = try? Data(contentsOf: accountsFile),
      let root = try? JSONSerialization.jsonObject(with: accountsData) as? [String: Any],
      let apiURL = root["api_url"] as? String,
      let accountsJSON = root["accounts"] as? [String: [String: Any]],
      let mine = accountsJSON[persona]
else { fail("Run mac/tools/staging-test-accounts.sh first.") }

var byUsername: [String: Account] = [:]
for (_, a) in accountsJSON {
    if let u = a["user_id"] as? String, let n = a["username"] as? String {
        byUsername[n] = Account(userId: u, username: n, displayName: a["display_name"] as? String ?? n)
    }
}
func account(_ username: String) -> Account {
    guard let a = byUsername[username] else { fail("unknown username \(username) (known: \(byUsername.keys.sorted().joined(separator: ", ")))") }
    return a
}

// The public (anon) key, from the same public env file the app builds with.
func anonKey() -> String {
    var candidates: [URL] = []
    if let p = ProcessInfo.processInfo.environment["LIME_PUBLIC_ENV"] { candidates.append(URL(fileURLWithPath: p)) }
    for start in [URL(fileURLWithPath: FileManager.default.currentDirectoryPath), URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()] {
        var d = start.standardizedFileURL
        for _ in 0..<8 { candidates.append(d.appendingPathComponent("supabase/.staging.public.env")); d.deleteLastPathComponent() }
    }
    for c in candidates {
        if let text = try? String(contentsOf: c, encoding: .utf8),
           let line = text.split(separator: "\n").first(where: { $0.hasPrefix("SUPABASE_ANON_KEY=") }) {
            return line.dropFirst("SUPABASE_ANON_KEY=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
        }
    }
    fail("Could not find supabase/.staging.public.env (set LIME_PUBLIC_ENV).")
}

let transport = URLSessionTransport(baseURL: URL(string: apiURL)!, apiKey: anonKey())

func jsonPost(_ path: String, _ body: [String: Any]) throws -> (Int, [String: Any]) {
    let data = try JSONSerialization.data(withJSONObject: body)
    let r = try transport.request(method: "POST", path: path, headers: [HeaderPair(name: "content-type", value: "application/json")], body: data)
    return (Int(r.status), (try? JSONSerialization.jsonObject(with: r.body) as? [String: Any]) ?? [:])
}

let sessionFile = dir.appendingPathComponent("session.json")
func lock(_ url: URL) { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
func writePrivate(_ url: URL, _ data: Data) {
    FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
    lock(url)
}

let session: Session = {
    let fromFile = Session(mine["access_token"] as! String, mine["refresh_token"] as! String, (mine["expires_at"] as? NSNumber)?.doubleValue ?? 0)
    func mtime(_ u: URL) -> Date { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date) ?? .distantPast }
    // A newer accounts file (the script ran again: new sessions) wins over the partner's own refreshed session.
    if let d = try? Data(contentsOf: sessionFile), mtime(sessionFile) > mtime(accountsFile),
       let s = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
       let a = s["access"] as? String, let r = s["refresh"] as? String, let e = (s["expires"] as? NSNumber)?.doubleValue {
        return Session(a, r, e)
    }
    return fromFile
}()

/// Refreshes the session when it is within five minutes of expiring, and keeps the new tokens (a refresh token is single-use).
func freshToken() -> String {
    if session.expires - Date().timeIntervalSince1970 > 300 { return session.access }
    guard let (status, body) = try? jsonPost("/auth/v1/token?grant_type=refresh_token", ["refresh_token": session.refresh]), status == 200,
          let a = body["access_token"] as? String, let r = body["refresh_token"] as? String
    else { fail("could not refresh \(personaName)'s session: run mac/tools/staging-test-accounts.sh again") }
    session.access = a; session.refresh = r
    session.expires = Date().timeIntervalSince1970 + ((body["expires_in"] as? NSNumber)?.doubleValue ?? 3600)
    let out = try! JSONSerialization.data(withJSONObject: ["access": a, "refresh": r, "expires": session.expires])
    writePrivate(sessionFile, out)
    return a
}

// MARK: the store

func openStore() -> LimeStore {
    let keyFile = dir.appendingPathComponent("key")
    if !FileManager.default.fileExists(atPath: keyFile.path) {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &bytes) == errSecSuccess else { fail("no random bytes") }
        writePrivate(keyFile, Data(bytes.map { String(format: "%02x", $0) }.joined().utf8))
    }
    let hex = (try! String(contentsOf: keyFile, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
    var key = Data()
    var i = hex.startIndex
    while i < hex.endIndex { let j = hex.index(i, offsetBy: 2); key.append(UInt8(hex[i..<j], radix: 16)!); i = j }
    do { return try LimeStore.open(path: dir.appendingPathComponent("lime.db").path, key: key) }
    catch { fail("could not open the store: \(error)") }
}

let store = openStore()
let device: DeviceInfo
do { device = try store.registerDevice(transport: transport, authToken: freshToken()) }
catch { fail("could not register the device: \(error)") }

func dmId(_ a: Account) -> String { "dm:\(a.userId)" }
func words(_ text: String) -> String { String(messagePlainText(text: text).replacingOccurrences(of: "\n", with: " ").prefix(40)) }
func syncAndAccept() {
    _ = try? store.sync(transport: transport, authToken: freshToken())
    for c in (try? store.listConversations()) ?? [] where c.requestState == "pending" { try? store.acceptRequest(conversationId: c.id) }
}

// MARK: commands

switch command {
case "send":
    guard let name = toName, let text = rawArgs.dropFirst().first else { fail("usage: partner --as b|c send --to <username> \"<text>\"") }
    do {
        _ = try store.sendTextIdentified(transport: transport, authToken: freshToken(), recipientUserId: account(name).userId, text: text)
        print("sent")
    } catch { fail("send failed: \(error)") }

case "status":
    _ = try? store.sync(transport: transport, authToken: freshToken())
    let all = (try? store.listConversations()) ?? []
    print("\(personaName): device \(device.deviceId.prefix(8)); conversations: \(all.count)")

case "inbox":
    syncAndAccept()
    var shown = 0
    for c in (try? store.listConversations()) ?? [] where !c.isGroup {
        if let f = fromName, c.id != dmId(account(f)) { continue }
        for m in (try? store.listMessages(conversationId: c.id)) ?? [] where m.senderId != nil && m.localState != "system" {
            print("\(c.title): \(words(m.text))"); shown += 1
        }
    }
    print("inbox: \(shown) message\(shown == 1 ? "" : "s")")

case "echo":
    // Everything already in the chats is history: only messages that arrive from now on are answered.
    var answered = Set<String>()
    syncAndAccept()
    for c in (try? store.listConversations()) ?? [] { for m in (try? store.listMessages(conversationId: c.id)) ?? [] { answered.insert(m.id) } }
    print("echo: listening as \(personaName) (Ctrl-C to stop)")
    fflush(stdout)
    while true {
        syncAndAccept()
        for c in (try? store.listConversations()) ?? [] where !c.isGroup {
            let fresh = ((try? store.listMessages(conversationId: c.id)) ?? []).filter { $0.senderId != nil && !answered.contains($0.id) && $0.localState != "system" }
            for m in fresh {
                answered.insert(m.id)
                // Never answer another echo (two echoes would talk forever).
                if messagePlainText(text: m.text).hasSuffix("here: got") || messagePlainText(text: m.text).contains(" here: got \"") { continue }
                _ = try? store.queueText(conversationId: c.id, text: "\(personaName) here: got \"\(words(m.text))\"")
                _ = try? store.deliverQueued(transport: transport, authToken: freshToken())
                print("echo: answered a message in \(c.title)"); fflush(stdout)
            }
        }
        Thread.sleep(forTimeInterval: 2)
    }

default:
    fail("unknown command \(command)")
}
