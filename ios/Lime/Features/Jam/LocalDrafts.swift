import Observation
import SwiftUI
import UIKit

/// LIME-276: drafts of a podcast or a quick post, kept on this phone (never sent): `lime-drafts/<id>/` in the account's space with a small `draft.json` and the
/// recording, cover and photos as files beside it. The space's files are protected until first unlock and are deleted with "Remove everything" (268).
struct LocalDraft: Codable, Identifiable, Equatable {
    struct Item: Codable, Equatable {
        var file: String
        var name: String, mime: String
        var width: UInt32?, height: UInt32?, durationMs: UInt32?
    }

    var id: String
    /// `podcast` or `post`.
    var kind: String
    var updated: Date
    var title = ""
    var subtitle = ""
    /// A podcast's description, or a quick post's words (markdown).
    var words = ""
    var audience = "subscribers"
    var topics: [String] = []
    var postAsJam: String?
    var seriesID: String?, seriesTitle: String?, seriesPart: UInt32?, seriesOf: UInt32?
    var coauthors: [String] = []
    var trimStart = 0.0, trimEnd = 0.0
    /// The recording and its poster/thumbnail (a podcast), the cover, and a quick post's photos.
    var clip: Item?
    var cover: Item?
    var photos: [Item] = []

    var label: String { kind == "podcast" ? "Podcast" : "Post" }
    /// What the list shows: the title, or the first line of words.
    var headline: String {
        if !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        let line = words.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.isEmpty ? (kind == "podcast" ? "Untitled podcast" : "Untitled post") : line
    }
}

@Observable
final class LocalDrafts: @unchecked Sendable {
    nonisolated(unsafe) static let shared = LocalDrafts()

    private(set) var drafts: [LocalDraft] = []
    private var account: String?

    private var folder: URL? {
        guard let account, let location = try? StorageBootstrap.Location.live(for: account) else { return nil }
        return location.directory.appendingPathComponent("lime-drafts", isDirectory: true)
    }

    private func folder(_ id: String) -> URL? { folder?.appendingPathComponent(id, isDirectory: true) }

    #if DEBUG
    /// UI tests: forget every draft of the demo account before it loads.
    func resetForDemo() {
        account = "demo"
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }
    #endif

    func load(for account: String?) {
        self.account = account
        drafts = []
        guard let folder else { return }
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
            if let data = try? Data(contentsOf: folder.appendingPathComponent(name).appendingPathComponent("draft.json")),
               let draft = try? JSONDecoder().decode(LocalDraft.self, from: data) { drafts.append(draft) }
        }
        drafts.sort { $0.updated > $1.updated }
    }

    /// Keeps `draft` with its media (a media item's bytes go beside it as `file`). Replaces an earlier save of the same draft.
    @discardableResult
    func save(_ draft: LocalDraft, media: [String: Data]) -> Bool {
        guard let dir = folder(draft.id) else { return false }
        var draft = draft
        draft.updated = Date()
        do {
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            for (file, bytes) in media where !file.contains("/") { try bytes.write(to: dir.appendingPathComponent(file), options: options) }
            try JSONEncoder().encode(draft).write(to: dir.appendingPathComponent("draft.json"), options: options)
        } catch { return false }
        drafts.removeAll { $0.id == draft.id }
        drafts.insert(draft, at: 0)
        return true
    }

    func data(_ draft: LocalDraft, _ file: String) -> Data? {
        folder(draft.id).flatMap { try? Data(contentsOf: $0.appendingPathComponent(file)) }
    }

    func draft(_ id: String) -> LocalDraft? { drafts.first { $0.id == id } }

    func delete(_ id: String) {
        if let dir = folder(id) { try? FileManager.default.removeItem(at: dir) }
        drafts.removeAll { $0.id == id }
    }

    /// The recording, cover or photo of a draft as the attachment the studio and the composer use.
    func outgoing(_ draft: LocalDraft, _ item: LocalDraft.Item, thumb: Data = Data(), poster: Data = Data()) -> OutgoingAttachment? {
        guard let bytes = data(draft, item.file) else { return nil }
        return OutgoingAttachment(bytes: bytes, name: item.name, mime: item.mime, width: item.width, height: item.height, durationMs: item.durationMs,
                                  thumb: data(draft, item.file + ".thumb") ?? thumb, poster: data(draft, item.file + ".poster") ?? poster)
    }

    /// The item and the files that keep an attachment (its thumbnail and poster too).
    static func item(_ attachment: OutgoingAttachment, file: String) -> (LocalDraft.Item, [String: Data]) {
        var files = [file: attachment.bytes]
        if !attachment.thumb.isEmpty { files[file + ".thumb"] = attachment.thumb }
        if !attachment.poster.isEmpty { files[file + ".poster"] = attachment.poster }
        return (LocalDraft.Item(file: file, name: attachment.name, mime: attachment.mime, width: attachment.width, height: attachment.height, durationMs: attachment.durationMs), files)
    }
}
