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
