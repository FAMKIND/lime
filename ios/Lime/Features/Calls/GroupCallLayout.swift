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

    // MARK: Modes and the speaker layouts (LIME-148b)

    /// How tiles are arranged: everyone equal, or the speaker large with the others in a strip.
    enum Mode: String, CaseIterable { case grid, speaker }

    /// The shape of the container (Element's "window modes", chosen from the container's size and not the device): a short wide strip
    /// ("flat": a phone on its side, a short iPad window) gets the speaker layout so everything fits without scrolling.
    enum Shape: Equatable { case normal, narrow, flat }

    static func shape(of size: CGSize) -> Shape {
        if size.height < 280 && size.width > size.height * 1.8 { return .flat }
        if size.width < 330 { return .narrow }
        return .normal
    }

    /// The default when the person has not chosen: one-on-one for 2, the grid up to 4 people, the speaker layout above 4, and always the speaker layout in a
    /// flat strip with 3 or more (a grid of tiny tiles is no use there).
    static func defaultMode(people: Int, in size: CGSize) -> Mode {
        // Two people: one-on-one (the other person fills the area, my picture floats), which is the speaker layout with nobody in the strip.
        if people == 2 { return .speaker }
        if shape(of: size) == .flat && people >= 3 { return .speaker }
        return people <= 4 ? .grid : .speaker
    }

    /// The speaker's tile may be larger and a little less constrained than a strip tile.
    static let speakerMinAspect: CGFloat = 0.6
    static let speakerMaxAspect: CGFloat = 2.0

    struct Spotlight: Equatable {
        var speaker: CGRect
        var strip: [CGRect]
    }

    /// The speaker large and `others` small tiles (everyone but the speaker and me: I float). Portrait: the speaker on top and the strip below
    /// it; landscape (or flat): the speaker on the left and the strip down the right side. The strip is laid out like the grid inside its own
    /// area, so up to 8 small tiles fit without scrolling. With no others the speaker fills the area (one-on-one: the other person edge to edge).
    static func spotlight(others: Int, in size: CGSize, gap: CGFloat = gap) -> Spotlight? {
        guard size.width > 0, size.height > 0 else { return nil }
        if others <= 0 { return Spotlight(speaker: CGRect(origin: .zero, size: size), strip: []) }
        let landscape = size.width > size.height
        let share: CGFloat = others <= 2 ? 0.26 : (others <= 4 ? 0.32 : 0.38)
        if landscape {
            let stripWidth = max(80, size.width * share)
            let speakerArea = CGSize(width: size.width - stripWidth - gap, height: size.height)
            let strip = grid(count: others, in: CGSize(width: stripWidth, height: size.height), gap: gap).map { $0.offsetBy(dx: speakerArea.width + gap, dy: 0) }
            return Spotlight(speaker: CGRect(origin: .zero, size: speakerArea), strip: strip)
        }
        let stripHeight = max(70, size.height * share)
        let speakerArea = CGSize(width: size.width, height: size.height - stripHeight - gap)
        let strip = grid(count: others, in: CGSize(width: size.width, height: stripHeight), gap: gap).map { $0.offsetBy(dx: 0, dy: speakerArea.height + gap) }
        return Spotlight(speaker: CGRect(origin: .zero, size: speakerArea), strip: strip)
    }

    /// Whether lime's slim return bar shows for a minimised group call (LIME-148b item 00): when I am not in that group's chat, whose lime call
    /// circle is the way back there, and not while the floating video window is up.
    static func returnBarShows(inCall: Bool, minimized: Bool, windowUp: Bool, viewingThatChat: Bool) -> Bool {
        inCall && minimized && !windowUp && !viewingThatChat
    }
}
