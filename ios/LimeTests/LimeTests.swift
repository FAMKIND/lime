import XCTest
import UIKit
@testable import Lime

/// A throwaway encrypted store in a temp directory, seeded with the sample data (as the app does).
enum TestStore {
    static let key = Data(repeating: 0x42, count: 32)

    static func make() throws -> (store: LimeStore, path: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("lime.db").path
        let store = try LimeStore.open(path: path, key: key)
        try store.seedSampleDataIfEmpty()
        return (store, path)
    }

    static func conversations(_ store: LimeStore) throws -> [Conversation] {
        try store.listConversations().map { Conversation($0, messages: try store.listMessages(conversationId: $0.id)) }
    }
}

final class SampleDataTests: XCTestCase {
    func testSeededStoreIsNonEmpty() throws {
        let (store, _) = try TestStore.make()
        XCTAssertFalse(try TestStore.conversations(store).isEmpty)
    }

    func testEveryConversationHasNameAndMessage() throws {
        let (store, _) = try TestStore.make()
        for c in try TestStore.conversations(store) {
            XCTAssertFalse(c.title.isEmpty, c.id)
            XCTAssertFalse(c.messages.isEmpty, c.id)
        }
    }
}

final class StorageTests: XCTestCase {
    func testWrongKeyIsRejectedAndRightKeyStillOpens() throws {
        let (_, path) = try TestStore.make()
        XCTAssertTrue(StorageBootstrap.rejectsWrongKey(path: path))
        XCTAssertNoThrow(try LimeStore.open(path: path, key: TestStore.key))
    }

    func testKeychainKeyIsCreatedOnceAndIs32Bytes() throws {
        let service = "app.lime.tests.\(UUID().uuidString)"
        defer { StorageKeychain.deleteKey(service: service) }
        let first = try StorageKeychain.loadOrCreateKey(service: service)
        let second = try StorageKeychain.loadOrCreateKey(service: service)
        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, Data(repeating: 0, count: 32))
    }
}

/// The store's lifecycle on disk: backups, an unopenable store, and the debug-only reset flag.
final class StorageRecoveryTests: XCTestCase {
    private func makeLocation() throws -> StorageBootstrap.Location {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lime-recovery-\(UUID().uuidString)", isDirectory: true)
        let service = "app.lime.tests.\(UUID().uuidString)"
        addTeardownBlock {
            StorageKeychain.deleteKey(service: service)
            try? FileManager.default.removeItem(at: directory)
        }
        return .init(directory: directory, keychainService: service)
    }

    private func conversationCount(_ opened: StorageBootstrap.Opened) throws -> Int {
        try opened.store.listConversations().count
    }

    func testFirstLaunchIsNotAnError() throws {
        let location = try makeLocation()
        XCTAssertNil(StorageKeychain.existingKey(service: location.keychainService))
        let opened = try StorageBootstrap.open(at: location)
        XCTAssertFalse(opened.startedFresh, "no key and no database is a first launch: no notice")
        XCTAssertEqual(try conversationCount(opened), 0, "a new account's store is empty (the sample chats are Debug-only)")
        XCTAssertTrue(StorageBootstrap.unreadableFileNames(in: location).isEmpty)
    }

    func testDatabaseIsExcludedFromBackupEveryLaunch() throws {
        let location = try makeLocation()
        _ = try StorageBootstrap.open(at: location)
        XCTAssertTrue(StorageBootstrap.isExcludedFromBackup(location.databaseURL))
        XCTAssertTrue(StorageBootstrap.isExcludedFromBackup(location.directory))

        // The attribute can be lost when a file is replaced; the next launch sets it again.
        var url = location.databaseURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try url.setResourceValues(values)
        XCTAssertFalse(StorageBootstrap.isExcludedFromBackup(url))
        _ = try StorageBootstrap.open(at: location)
        XCTAssertTrue(StorageBootstrap.isExcludedFromBackup(location.databaseURL))
    }

    func testWrongKeyMovesTheOldFileAsideAndStartsFresh() throws {
        let location = try makeLocation()
        do {
            let first = try StorageBootstrap.open(at: location)
            try first.store.seedSampleDataIfEmpty()
            _ = try first.store.sendLocalMessage(conversationId: "c1", text: "before the key was lost")
        }
        // A restore without the Keychain: the file survives, the key does not match.
        StorageKeychain.deleteKey(service: location.keychainService)
        _ = try StorageKeychain.loadOrCreateKey(service: location.keychainService)

        let recovered = try StorageBootstrap.open(at: location)
        XCTAssertTrue(recovered.startedFresh)
        XCTAssertEqual(try conversationCount(recovered), 0, "the fresh store starts empty")
        let texts = try recovered.store.listMessages(conversationId: "c1").map(\.text)
        XCTAssertFalse(texts.contains("before the key was lost"))
        let aside = StorageBootstrap.unreadableFileNames(in: location)
        XCTAssertEqual(aside.count, 1)
        XCTAssertTrue(aside[0].hasPrefix("lime-") && aside[0].hasSuffix(".unreadable.db"), aside[0])
        XCTAssertTrue(StorageBootstrap.isExcludedFromBackup(location.directory.appendingPathComponent(aside[0])))

        // The next launch is normal: no notice, nothing more moved aside.
        let next = try StorageBootstrap.open(at: location)
        XCTAssertFalse(next.startedFresh)
        XCTAssertEqual(StorageBootstrap.unreadableFileNames(in: location), aside)
    }

    func testMissingKeyWithAnExistingDatabaseTakesTheSamePath() throws {
        let location = try makeLocation()
        do { _ = try StorageBootstrap.open(at: location) }
        StorageKeychain.deleteKey(service: location.keychainService)

        let recovered = try StorageBootstrap.open(at: location)
        XCTAssertTrue(recovered.startedFresh)
        XCTAssertEqual(StorageBootstrap.unreadableFileNames(in: location).count, 1)
        XCTAssertEqual(try conversationCount(recovered), 0)
        XCTAssertNotNil(StorageKeychain.existingKey(service: location.keychainService))
    }

    func testAKeyWithNoDatabaseIsNotAnError() throws {
        let location = try makeLocation()
        _ = try StorageKeychain.loadOrCreateKey(service: location.keychainService)
        let opened = try StorageBootstrap.open(at: location)
        XCTAssertFalse(opened.startedFresh)
    }

    func testOnlyTheTwoNewestUnreadableFilesAreKept() throws {
        let location = try makeLocation()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        do { _ = try StorageBootstrap.open(at: location, now: start) }
        for step in 1...4 {
            StorageKeychain.deleteKey(service: location.keychainService)
            let opened = try StorageBootstrap.open(at: location, now: start.addingTimeInterval(Double(step) * 60))
            XCTAssertTrue(opened.startedFresh)
        }
        let names = StorageBootstrap.unreadableFileNames(in: location)
        XCTAssertEqual(names.count, StorageBootstrap.keptUnreadableFiles)
        let formatter = ISO8601DateFormatter()
        let expected = [3, 4].map { "lime-\(formatter.string(from: start.addingTimeInterval(Double($0) * 60))).unreadable.db" }
        XCTAssertEqual(names, expected, "the two newest are kept")
    }

    func testResetFlagIsIgnoredOutsideDebugBuilds() {
        let args = ["Lime", "-lime-reset-store"]
        XCTAssertFalse(StorageBootstrap.resetRequested(arguments: args, debugBuild: false), "a Release build ignores the flag")
        XCTAssertTrue(StorageBootstrap.resetRequested(arguments: args, debugBuild: true))
        XCTAssertFalse(StorageBootstrap.resetRequested(arguments: ["Lime"], debugBuild: true))
        #if DEBUG
        XCTAssertTrue(StorageBootstrap.isDebugBuild)
        #else
        XCTAssertFalse(StorageBootstrap.isDebugBuild)
        #endif
    }
}

final class ThemeTests: XCTestCase {
    private func hex(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    private func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Light is the web's `--lime-primary-bg` (lime-100), unchanged. Dark is native-only: the accent
    /// (LIME-87-fix4), since the web's dark value (#0D2016) vanishes on the dark canvas.
    func testOwnBubbleIsThePrimaryColour() {
        XCTAssertEqual(Theme.Name.primary, "OwnBubble")
        XCTAssertEqual(hex(Theme.uiColor(Theme.Name.primary, dark: false)), "E4F9BE")
        XCTAssertEqual(hex(Theme.uiColor(Theme.Name.primary, dark: true)), "8ECF73")
    }

    /// LIME-87-fix5: the dark own bubble (and send arrow) is a dimmer green than the accent, which
    /// the badges and the Messages "+" keep.
    func testDarkOwnBubbleIsDimmerThanTheAccent() {
        let bubble = hex(Theme.uiColor(Theme.Name.primary, dark: true))
        XCTAssertEqual(bubble, "8ECF73")
        XCTAssertNotEqual(bubble, hex(Theme.uiColor(Theme.Name.accent, dark: true)))
        XCTAssertEqual(hex(Theme.uiColor(Theme.Name.accent, dark: true)), "A3E18A")
        let ratio = contrast(Theme.uiColor(Theme.Name.primaryInk, dark: true), Theme.uiColor(Theme.Name.primary, dark: true))
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "ratio \(ratio)")
        // About 6-8% lower OKLab lightness than the accent.
        let drop = 1 - oklab(Theme.uiColor(Theme.Name.primary, dark: true)).0 / oklab(Theme.uiColor(Theme.Name.accent, dark: true)).0
        XCTAssertGreaterThan(drop, 0.06); XCTAssertLessThan(drop, 0.08)
    }

    func testLightValuesUnchangedFromLime87() {
        let expected = ["Canvas": "F9F8F4", "Surface": "F0EEE6", "BubbleOther": "FFFEFE", "BubbleEdge": "DDDDD9",
                        "OwnBubble": "E4F9BE", "OwnInk": "131B17", "TextPrimary": "131B17",
                        "TextSecondary": "504840", "Hairline": "DDDDD9"]
        for (name, value) in expected {
            XCTAssertEqual(hex(Theme.uiColor(name, dark: false)), value, name)
        }
    }

    private func oklab(_ c: UIColor) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        let (R, G, B) = (lin(r), lin(g), lin(b))
        let l = cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B)
        let m = cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B)
        let s = cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// Distance in OKLab, scaled by 100 (the unit the web's tone checks use).
    func testDarkPrimaryIsVisibleOnDarkCanvas() {
        let p = oklab(Theme.uiColor(Theme.Name.primary, dark: true))
        let c = oklab(Theme.uiColor(Theme.Name.canvas, dark: true))
        let d = 100 * sqrt(pow(p.0 - c.0, 2) + pow(p.1 - c.1, 2) + pow(p.2 - c.2, 2))
        XCTAssertGreaterThanOrEqual(d, 8, "OKLab distance \(d)")
    }

    func testDarkInkOnDarkPrimaryMeetsContrast() {
        let ratio = contrast(Theme.uiColor(Theme.Name.primaryInk, dark: true), Theme.uiColor(Theme.Name.primary, dark: true))
        XCTAssertGreaterThanOrEqual(ratio, 4.5, "ratio \(ratio)")
    }

    func testAccentIsA3E18AInBothModes() {
        for dark in [false, true] {
            XCTAssertEqual(hex(Theme.uiColor(Theme.Name.accent, dark: dark)), "A3E18A", dark ? "dark" : "light")
        }
    }

    func testAccentInkMeetsContrast() {
        for dark in [false, true] {
            let ratio = contrast(Theme.uiColor(Theme.Name.accentInk, dark: dark), Theme.uiColor(Theme.Name.accent, dark: dark))
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(dark ? "dark" : "light") ratio \(ratio)")
        }
    }

    /// Light mode is unchanged: the own bubble keeps its light primary.
    func testLightOwnBubbleUnchanged() {
        XCTAssertEqual(hex(Theme.uiColor(Theme.Name.primary, dark: false)), "E4F9BE")
        XCTAssertEqual(hex(Theme.uiColor(Theme.Name.primaryInk, dark: false)), "131B17")
    }

    func testTextOnBubblesMeetsContrast() {
        for dark in [false, true] {
            let mode = dark ? "dark" : "light"
            let own = contrast(Theme.uiColor(Theme.Name.primaryInk, dark: dark), Theme.uiColor(Theme.Name.primary, dark: dark))
            let other = contrast(Theme.uiColor(Theme.Name.text, dark: dark), Theme.uiColor(Theme.Name.bubbleOther, dark: dark))
            XCTAssertGreaterThanOrEqual(own, 4.5, "own bubble \(mode)")
            XCTAssertGreaterThanOrEqual(other, 4.5, "other bubble \(mode)")
        }
    }
}

@MainActor
final class StoreTests: XCTestCase {
    private func loadedStore() async throws -> ConversationStore {
        let (core, path) = try TestStore.make()
        let store = ConversationStore(store: core, path: path)
        await store.reload()
        return store
    }

    func testSendAppendsOwnMessageAndPersistsIt() async throws {
        let store = try await loadedStore()
        let id = try XCTUnwrap(store.conversations.first).id
        let before = try XCTUnwrap(store.conversation(id)).messages.count
        await store.sendNow("  hello  ", in: id)
        let after = try XCTUnwrap(store.conversation(id)).messages
        XCTAssertEqual(after.count, before + 1)
        XCTAssertEqual(after.last?.text, "hello")
        XCTAssertTrue(after.last?.isOwn ?? false)
        // It was written to the encrypted store, not only shown.
        await store.reload()
        XCTAssertEqual(try XCTUnwrap(store.conversation(id)).messages.last?.text, "hello")
    }

    func testBlankSendIsIgnored() async throws {
        let store = try await loadedStore()
        let id = try XCTUnwrap(store.conversations.first).id
        let before = try XCTUnwrap(store.conversation(id)).messages.count
        await store.sendNow("  \n ", in: id)
        XCTAssertEqual(try XCTUnwrap(store.conversation(id)).messages.count, before)
    }

    func testStorageReportsEncrypted() async throws {
        let store = try await loadedStore()
        let encrypted = await store.storageIsEncrypted()
        XCTAssertTrue(encrypted)
    }
}

final class ChatRowTests: XCTestCase {
    /// A DM's incoming message shows an avatar, as a group's does.
    func testDirectMessageIncomingHasAvatar() throws {
        let (store, _) = try TestStore.make()
        let dm = try XCTUnwrap(try TestStore.conversations(store).first { !$0.isGroup && $0.messages.contains { !$0.isOwn } })
        let avatars = ChatRow.rows(for: dm).compactMap { row -> Bool? in
            if case .message(let m, let showAvatar) = row.kind, !m.isOwn { return showAvatar }
            return nil
        }
        XCTAssertFalse(avatars.isEmpty)
        XCTAssertTrue(avatars.first ?? false, "the first incoming DM message shows the sender's avatar")
    }

    func testConsecutiveIncomingMessagesShareOneAvatar() {
        let person = Person(id: "p", name: "Test Person", tone: 3)
        let now = Date()
        let c = Conversation(id: "t", title: "t", members: [person], messages: [
            Message(id: "1", senderID: person.id, text: "a", date: now),
            Message(id: "2", senderID: person.id, text: "b", date: now),
        ])
        let flags = ChatRow.rows(for: c).compactMap { row -> Bool? in
            if case .message(_, let a) = row.kind { return a }
            return nil
        }
        XCTAssertEqual(flags, [true, false])
    }
}

final class LimeCoreTests: XCTestCase {
    /// Real vodozemac Olm and Megolm round trips, through the UniFFI Swift bindings.
    func testEncryptionSelfTestPasses() {
        let report = encryptionSelfTest()
        XCTAssertTrue(report.olmOk, report.detail)
        XCTAssertTrue(report.megolmOk, report.detail)
        XCTAssertFalse(report.detail.isEmpty)
    }

    func testCoreVersionIsReported() {
        XCTAssertFalse(coreVersion().isEmpty)
    }
}

/// Stands in for the network: records the request and returns a canned response.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            // The body of a request made through URLSession arrives as a stream.
            if let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n <= 0 { break }
                    data.append(buffer, count: n)
                }
                stream.close()
                Self.lastBody = data
            } else {
                Self.lastBody = request.httpBody
            }
            let (status, body) = try (Self.handler ?? { _ in (500, Data()) })(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

final class URLSessionTransportTests: XCTestCase {
    private func makeTransport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionTransport(baseURL: URL(string: "https://example.invalid")!, apiKey: "public-key",
                                   session: URLSession(configuration: configuration))
    }

    func testSendsTheRequestAndReturnsStatusAndBody() throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/functions/v1/send")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "public-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Bearer token")
            return (409, Data("{\"error\":\"x\"}".utf8))
        }
        let response = try makeTransport().request(
            method: "POST", path: "/functions/v1/send",
            headers: [HeaderPair(name: "authorization", value: "Bearer token")],
            body: Data("{}".utf8))
        XCTAssertEqual(response.status, 409, "an error status is a response, not a failure")
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "{\"error\":\"x\"}")
        XCTAssertEqual(StubURLProtocol.lastBody, Data("{}".utf8))
    }

    func testANetworkFailureIsATransportError() {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertThrowsError(try makeTransport().request(method: "POST", path: "/x", headers: [], body: Data())) { error in
            XCTAssertEqual(error as? TransportError, .Failed)
        }
    }

    /// LimeCore accepts the Swift transport as its callback interface (the protocol is Sendable and
    /// usable from a background thread, as the app calls it).
    func testLimeCoreCanCallThroughTheTransport() throws {
        StubURLProtocol.handler = { _ in (404, Data("{\"error\":\"not_found\"}".utf8)) }
        let found = try lookupUserByEmail(transport: makeTransport(), authToken: "token", email: "nobody@example.invalid")
        XCTAssertNil(found, "a 404 means nobody has that email")
    }
}
