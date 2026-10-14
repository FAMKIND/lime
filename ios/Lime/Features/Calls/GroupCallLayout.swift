import CoreGraphics

/// Where a group call's tiles go (LIME-148): pure functions, so every shape of screen can be tested. Nothing scrolls: every tile (up to 9)
/// fits the visible area at once and tiles shrink instead. A tile is never a thin strip: its shape stays between 3:4 and 16:9 and the
/// video aspect-fills it (a little crop, never squashed). FaceTime's own layout is not public API, so it is computed here.
enum GroupCallLayout {
    /// The shapes a tile may take (width / height).
    static let minAspect: CGFloat = 0.75
    static let maxAspect: CGFloat = 16.0 / 9.0
    static let gap: CGFloat = 6

    /// A frame per tile (in the area's own coordinates), in order. The rows x columns that give the largest tiles win, a lone last row is
    /// centred, and a nearly square block is preferred to one long column or row. 2 people sit side by side in landscape and stacked in portrait;
    /// 4 make 2 x 2.
    static func grid(count: Int, in size: CGSize, gap: CGFloat = gap) -> [CGRect] {
        guard count > 0, size.width > 0, size.height > 0 else { return [] }
        var best: (score: CGFloat, columns: Int, rows: Int, tile: CGSize)?
        for columns in 1...count {
            let rows = (count + columns - 1) / columns
            // A tidy grid has no empty row.
            if (rows - 1) * columns >= count { continue }
            let cell = CGSize(width: (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                              height: (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
            guard cell.width > 0, cell.height > 0 else { continue }
            let tile = fit(cell)
            // Largest tiles first; a mild preference for a block that is not one long strip.
            let balance = pow(CGFloat(min(columns, rows)) / CGFloat(max(columns, rows)), 0.3)
            let score = tile.width * tile.height * balance
            if best == nil || score > best!.score + 0.5 { best = (score, columns, rows, tile) }
        }
        guard let chosen = best else { return [] }
        let columns = chosen.columns, rows = chosen.rows, tile = chosen.tile
        let blockHeight = tile.height * CGFloat(rows) + gap * CGFloat(rows - 1)
        let top = (size.height - blockHeight) / 2
        var frames: [CGRect] = []
        for row in 0..<rows {
            let inRow = min(columns, count - row * columns)
            let rowWidth = tile.width * CGFloat(inRow) + gap * CGFloat(inRow - 1)
            let left = (size.width - rowWidth) / 2
            for column in 0..<inRow {
                frames.append(CGRect(x: left + CGFloat(column) * (tile.width + gap), y: top + CGFloat(row) * (tile.height + gap), width: tile.width, height: tile.height))
            }
        }
        return frames
    }

    /// The largest rectangle inside `cell` whose shape is within the allowed range.
    static func fit(_ cell: CGSize) -> CGSize {
        let aspect = cell.width / cell.height
        if aspect > maxAspect { return CGSize(width: cell.height * maxAspect, height: cell.height) }
        if aspect < minAspect { return CGSize(width: cell.width, height: cell.width / minAspect) }
        return cell
    }

    enum Corner: CaseIterable { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    /// My own picture as a small floating tile (once three or more people are in), kept inside the area with a margin; 3:4 in portrait and
    /// 4:3 in landscape.
    static func selfView(in size: CGSize, corner: Corner, margin: CGFloat = 10) -> CGRect {
        let landscape = size.width > size.height
        let longSide = min(max(min(size.width, size.height) * 0.3, 96), 180)
        let tile = landscape ? CGSize(width: longSide * 4 / 3 * 0.75 + 20, height: longSide * 0.75 + 15) : CGSize(width: longSide * 0.75, height: longSide)
        let x = (corner == .topLeading || corner == .bottomLeading) ? margin : size.width - margin - tile.width
        let y = (corner == .topLeading || corner == .topTrailing) ? margin : size.height - margin - tile.height
        return CGRect(origin: CGPoint(x: max(0, x), y: max(0, y)), size: tile)
    }

    /// Where the nearest corner is for a dragged self-view centre.
    static func nearestCorner(to point: CGPoint, in size: CGSize) -> Corner {
        let left = point.x < size.width / 2, top = point.y < size.height / 2
        switch (left, top) {
        case (true, true): return .topLeading
        case (false, true): return .topTrailing
        case (true, false): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    /// How far the header must sit below the top of a window that iPadOS draws its own window controls (the "•••") over: a windowed iPad scene
    /// (smaller than its screen) leaves room for them; a full-screen window or a phone leaves none beyond the safe area.
    static func windowControlsMargin(idiomIsPad: Bool, window: CGSize, screen: CGSize) -> CGFloat {
        guard idiomIsPad else { return 0 }
        let windowed = window.width < screen.width - 1 || window.height < screen.height - 1
        return windowed ? 52 : 0
    }
}
