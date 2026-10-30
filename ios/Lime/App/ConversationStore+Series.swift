import Foundation
import UIKit

/// A series' own description and cover (LIME-260a/b): read from the jam's state on this phone; the writer sets them from Edit series.
extension ConversationStore {
    /// The jam a series belongs to, from any part this phone has.
    func seriesJam(_ seriesID: String) -> String? {
        for (jam, posts) in jamPosts where posts.contains(where: { $0.series?.id == seriesID }) { return jam }
        return discoverItems.first { $0.series?.id == seriesID }?.jamId
    }

    /// The other series of the same jam (their covers show under "More from …").
    func otherSeries(inJam jamID: String, except seriesID: String) -> [(id: String, title: String)] {
        var seen: [String: String] = [:]
        for post in jamPosts[jamID] ?? [] { if let s = post.series, s.id != seriesID { seen[s.id] = s.title } }
        return seen.map { (id: $0.key, title: $0.value) }.sorted { $0.title < $1.title }
    }

    /// Reads the series' description and cover this phone holds.
    func loadSeries(_ seriesID: String) async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard let core, let jam = seriesJam(seriesID) else { return }
        let held = await Task.detached(priority: .utility) { ((try? core.seriesMeta(jamId: jam, seriesId: seriesID)) ?? nil, (try? core.seriesCover(jamId: jam, seriesId: seriesID)) ?? nil) }.value
        seriesMetas[seriesID] = held.0
        seriesCovers[seriesID] = held.1
    }

    /// The writer describes the series (title, description, optionally a cover of at most 24 KB).
    @discardableResult
    func setSeriesMeta(_ seriesID: String, title: String, description: String, cover: Data?) async -> Bool {
        guard let jam = seriesJam(seriesID) else { return false }
        #if DEBUG
        if isDemo { seriesMetas[seriesID] = SeriesMeta(seriesId: seriesID, title: title, description: description, cover: cover); if let cover { seriesCovers[seriesID] = cover }; return true }
        #endif
        guard let core else { return false }
        let ok = (try? await Task.detached { try core.setSeriesMeta(jamId: jam, seriesId: seriesID, title: title, description: description, cover: cover) }.value) != nil
        await loadSeries(seriesID)
        if ok { await deliverNow() }
        return ok
    }
}

/// A series cover small enough for the state (24 KB): the picture drawn square at 360 px (smaller if it must be) and re-encoded.
enum SeriesCover {
    static func jpeg(_ image: UIImage) -> Data? {
        for side in [360, 300, 240, 180] as [CGFloat] {
            let size = CGSize(width: side, height: side)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let drawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                let cover = max(side / image.size.width, side / image.size.height)
                let box = CGSize(width: image.size.width * cover, height: image.size.height * cover)
                image.draw(in: CGRect(x: (side - box.width) / 2, y: (side - box.height) / 2, width: box.width, height: box.height))
            }
            for quality in [0.7, 0.55, 0.4, 0.3] as [CGFloat] {
                if let data = drawn.jpegData(compressionQuality: quality), data.count <= 23_000 { return data }
            }
        }
        return nil
    }
}
