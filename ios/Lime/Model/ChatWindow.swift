import Foundation

/// The newest rows a chat shows at first, and how it grows (LIME-164). A chat is laid out whole inside its window, so its height is exact and it
/// opens at the newest message on the first frame however long it is; older rows are added in pages as you scroll near the top.
enum ChatWindow {
    /// The rows shown when a chat opens.
    static let first = 60
    /// How many older rows each page adds.
    static let page = 60

    /// The rows of `all` that the window shows: the newest `window` of them.
    static func shown<T>(_ all: [T], window: Int) -> ArraySlice<T> { all.suffix(max(0, window)) }

    /// How many rows are older than the window.
    static func hidden(total: Int, window: Int) -> Int { max(0, total - window) }

    /// The window after one more page.
    static func grown(window: Int, total: Int) -> Int { min(total, window + page) }

    /// A window that includes the row at `index` (of `total`, oldest first) with some context above it: never smaller than `window`.
    static func covering(index: Int, total: Int, window: Int, context: Int = 20) -> Int {
        guard index >= 0, index < total else { return window }
        return max(window, min(total, total - index + context))
    }
}
